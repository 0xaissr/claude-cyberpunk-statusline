#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STATUSLINE="$PROJECT_DIR/statusline.sh"
SAMPLE="$SCRIPT_DIR/sample-input.json"

PASS=0
FAIL=0

test_exists() {
  if [[ -f "$STATUSLINE" ]] && [[ -x "$STATUSLINE" ]]; then
    echo "✓ test_exists: statusline.sh exists and is executable"
    ((PASS++))
  else
    echo "✗ test_exists: statusline.sh does not exist or is not executable"
    ((FAIL++))
  fi
}

test_default_output() {
  if [[ ! -f "$STATUSLINE" ]]; then
    echo "✗ test_default_output: statusline.sh not found, skipping"
    ((FAIL++))
    return
  fi

  output=$(cat "$SAMPLE" | bash "$STATUSLINE" 2>/dev/null || true)
  if [[ -n "$output" ]]; then
    echo "✓ test_default_output: produced non-empty output"
    ((PASS++))
  else
    echo "✗ test_default_output: output is empty"
    ((FAIL++))
  fi
}

test_theme_json() {
  local themes_dir="$PROJECT_DIR/themes"

  if [[ ! -d "$themes_dir" ]]; then
    echo "⊘ test_theme_json: themes directory not found, skipping"
    return
  fi

  local all_valid=true
  while IFS= read -r theme_file; do
    if ! jq empty "$theme_file" 2>/dev/null; then
      echo "✗ test_theme_json: $theme_file is not valid JSON"
      ((FAIL++))
      all_valid=false
    fi
  done < <(find "$themes_dir" -maxdepth 1 -name "*.json" -type f)

  if $all_valid && [[ $(find "$themes_dir" -maxdepth 1 -name "*.json" -type f | wc -l) -gt 0 ]]; then
    echo "✓ test_theme_json: all theme files are valid JSON"
    ((PASS++))
  elif [[ $(find "$themes_dir" -maxdepth 1 -name "*.json" -type f | wc -l) -eq 0 ]]; then
    echo "⊘ test_theme_json: no theme files found"
  fi
}

test_each_theme() {
  local themes_dir="$PROJECT_DIR/themes"

  if [[ ! -d "$themes_dir" ]]; then
    echo "⊘ test_each_theme: themes directory not found, skipping"
    return
  fi

  if [[ ! -f "$STATUSLINE" ]]; then
    echo "✗ test_each_theme: statusline.sh not found, skipping"
    ((FAIL++))
    return
  fi

  local all_passed=true
  while IFS= read -r theme_file; do
    local theme_name=$(basename "$theme_file" .json)
    local config_tmp=$(mktemp)

    cat > "$config_tmp" <<EOF
{
  "theme": "$theme_name",
  "symbol_set": "unicode",
  "spacing": "normal",
  "separator": "│",
  "blocks": ["model", "context", "rate_5h", "rate_7d", "directory", "git", "time"],
  "bar_width": 10
}
EOF

    local output=$(cat "$SAMPLE" | CONFIG_OVERRIDE="$config_tmp" bash "$STATUSLINE" 2>/dev/null || true)
    rm -f "$config_tmp"

    if [[ -n "$output" ]]; then
      echo "✓ test_each_theme: theme '$theme_name' produced output"
      ((PASS++))
    else
      echo "✗ test_each_theme: theme '$theme_name' produced empty output"
      ((FAIL++))
      all_passed=false
    fi
  done < <(find "$themes_dir" -maxdepth 1 -name "*.json" -type f)

  if [[ $(find "$themes_dir" -maxdepth 1 -name "*.json" -type f | wc -l) -eq 0 ]]; then
    echo "⊘ test_each_theme: no theme files found"
  fi
}

test_spacing_modes() {
  if [[ ! -f "$STATUSLINE" ]]; then
    echo "✗ test_spacing_modes: statusline.sh not found, skipping"
    ((FAIL++))
    return
  fi

  local modes=("compact" "ultra-compact")
  local all_passed=true

  for mode in "${modes[@]}"; do
    local config_tmp=$(mktemp)

    cat > "$config_tmp" <<EOF
{
  "theme": "terminal-glitch",
  "symbol_set": "unicode",
  "spacing": "$mode",
  "separator": "│",
  "blocks": ["model", "context", "rate_5h", "rate_7d"],
  "bar_width": 10
}
EOF

    local output=$(cat "$SAMPLE" | CONFIG_OVERRIDE="$config_tmp" bash "$STATUSLINE" 2>/dev/null || true)
    rm -f "$config_tmp"

    if [[ -n "$output" ]]; then
      echo "✓ test_spacing_modes: mode '$mode' produced output"
      ((PASS++))
    else
      echo "✗ test_spacing_modes: mode '$mode' produced empty output"
      ((FAIL++))
      all_passed=false
    fi
  done
}

test_spend_block_quota() {
  local cfg=$(mktemp) cache=$(mktemp)
  printf '{"theme":"terminal-glitch","symbol_set":"nerd","spacing":"ultra-compact","style":"classic","separator":"|","blocks":["model","rate_5h","rate_7d","time"],"bar_width":6,"show_icons":true,"account_type":"auto"}' > "$cfg"
  printf '{"account_type":"quota","spend":{"used_cents":12156,"limit_cents":50000,"utilization":24,"currency":"USD","resets_at":%s}}' "$(($(date +%s)+1814400))" > "$cache"
  local out=$(cat "$SAMPLE" | CONFIG_OVERRIDE="$cfg" USAGE_CACHE_OVERRIDE="$cache" bash "$STATUSLINE" 2>/dev/null || true)
  rm -f "$cfg" "$cache"
  if echo "$out" | grep -q '\$122/\$500' && echo "$out" | grep -q '24%'; then
    echo "✓ test_spend_block_quota: spend block 顯示金額與百分比"; ((PASS++))
  else
    echo "✗ test_spend_block_quota: 未顯示 spend 金額/百分比 — got: $out"; ((FAIL++))
  fi
}

test_spend_replaces_rate() {
  local cfg=$(mktemp) cache=$(mktemp)
  printf '{"theme":"terminal-glitch","symbol_set":"nerd","spacing":"normal","style":"classic","separator":"|","blocks":["model","rate_5h","rate_7d","time"],"bar_width":6,"show_icons":false,"account_type":"auto"}' > "$cfg"
  printf '{"account_type":"quota","spend":{"used_cents":12156,"limit_cents":50000,"utilization":24,"currency":"USD","resets_at":%s}}' "$(($(date +%s)+1814400))" > "$cache"
  local out=$(cat "$SAMPLE" | CONFIG_OVERRIDE="$cfg" USAGE_CACHE_OVERRIDE="$cache" bash "$STATUSLINE" 2>/dev/null || true)
  rm -f "$cfg" "$cache"
  if echo "$out" | grep -qE '5H|7D'; then
    echo "✗ test_spend_replaces_rate: quota 模式仍出現 5H/7D — got: $out"; ((FAIL++))
  else
    echo "✓ test_spend_replaces_rate: quota 模式已移除 5H/7D"; ((PASS++))
  fi
}

test_spend_degraded() {
  local cfg=$(mktemp) cache=$(mktemp)
  printf '{"theme":"terminal-glitch","symbol_set":"nerd","spacing":"ultra-compact","style":"classic","separator":"|","blocks":["model","rate_5h","time"],"bar_width":6,"show_icons":true,"account_type":"quota"}' > "$cfg"
  printf '{"account_type":"unknown"}' > "$cache"
  local out=$(cat "$SAMPLE" | CONFIG_OVERRIDE="$cfg" USAGE_CACHE_OVERRIDE="$cache" bash "$STATUSLINE" 2>/dev/null || true)
  rm -f "$cfg" "$cache"
  if echo "$out" | grep -q '\$--'; then
    echo "✓ test_spend_degraded: 無資料時顯示 \$-- 占位"; ((PASS++))
  else
    echo "✗ test_spend_degraded: 未顯示 \$-- 占位 — got: $out"; ((FAIL++))
  fi
}

test_subscription_keeps_rate() {
  local cfg=$(mktemp) cache=$(mktemp)
  printf '{"theme":"terminal-glitch","symbol_set":"nerd","spacing":"normal","style":"classic","separator":"|","blocks":["model","rate_5h","rate_7d","time"],"bar_width":6,"show_icons":false,"account_type":"auto"}' > "$cfg"
  printf '{"account_type":"subscription"}' > "$cache"
  local out=$(cat "$SAMPLE" | CONFIG_OVERRIDE="$cfg" USAGE_CACHE_OVERRIDE="$cache" bash "$STATUSLINE" 2>/dev/null || true)
  rm -f "$cfg" "$cache"
  if echo "$out" | grep -qE '5H|7D'; then
    echo "✓ test_subscription_keeps_rate: 訂閱制維持 5H/7D"; ((PASS++))
  else
    echo "✗ test_subscription_keeps_rate: 訂閱制遺失 5H/7D — got: $out"; ((FAIL++))
  fi
}

test_credit_block_quota() {
  local cfg=$(mktemp) cache=$(mktemp)
  printf '{"theme":"terminal-glitch","symbol_set":"nerd","spacing":"normal","style":"classic","separator":"|","blocks":["model","rate_5h","rate_7d","time"],"bar_width":6,"show_icons":false,"account_type":"auto"}' > "$cfg"
  printf '{"account_type":"quota","credit":{"utilization":8,"resets_at":%s},"spend":{"used_cents":12156,"limit_cents":50000,"utilization":24,"currency":"USD","resets_at":%s}}' "$(($(date +%s)+7776000))" "$(($(date +%s)+1814400))" > "$cache"
  local out=$(cat "$SAMPLE" | CONFIG_OVERRIDE="$cfg" USAGE_CACHE_OVERRIDE="$cache" bash "$STATUSLINE" 2>/dev/null || true)
  rm -f "$cfg" "$cache"
  local cr_pos=$(echo "$out" | grep -bo 'CR' | head -1 | cut -d: -f1)
  local sp_pos=$(echo "$out" | grep -bo '122/' | head -1 | cut -d: -f1)
  if echo "$out" | grep -q 'CR' && echo "$out" | grep -q '8%' && [ -n "$cr_pos" ] && [ -n "$sp_pos" ] && [ "$cr_pos" -lt "$sp_pos" ]; then
    echo "✓ test_credit_block_quota: credit 區塊顯示且在 spend 左側"; ((PASS++))
  else
    echo "✗ test_credit_block_quota: credit 未顯示或順序錯誤 — got: $out"; ((FAIL++))
  fi
}

test_credit_absent_hidden() {
  local cfg=$(mktemp) cache=$(mktemp)
  printf '{"theme":"terminal-glitch","symbol_set":"nerd","spacing":"normal","style":"classic","separator":"|","blocks":["model","rate_5h","rate_7d","time"],"bar_width":6,"show_icons":false,"account_type":"auto"}' > "$cfg"
  printf '{"account_type":"quota","spend":{"used_cents":12156,"limit_cents":50000,"utilization":24,"currency":"USD","resets_at":%s}}' "$(($(date +%s)+1814400))" > "$cache"
  local out=$(cat "$SAMPLE" | CONFIG_OVERRIDE="$cfg" USAGE_CACHE_OVERRIDE="$cache" bash "$STATUSLINE" 2>/dev/null || true)
  rm -f "$cfg" "$cache"
  if echo "$out" | grep -q 'CR'; then
    echo "✗ test_credit_absent_hidden: 無 credit 時仍出現 CR — got: $out"; ((FAIL++))
  else
    echo "✓ test_credit_absent_hidden: 無 credit 時隱藏 credit 區塊"; ((PASS++))
  fi
}

test_burn_history_subscription() {
  # burn history：subscription 輸入跑一次 statusline 後，history 檔應有一筆 seven_day 列
  local HTMP; HTMP=$(mktemp); rm -f "$HTMP"
  local SAMPLE_7D=$(( $(date +%s) + 4*86400 ))
  local cfg=$(mktemp) cache=$(mktemp)
  printf '{"theme":"terminal-glitch","symbol_set":"unicode","spacing":"normal","style":"classic","separator":"|","blocks":["model","rate_5h","rate_7d","time"],"bar_width":6,"show_icons":false,"account_type":"auto"}' > "$cfg"
  printf '{"account_type":"subscription"}' > "$cache"
  echo '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":50},"rate_limits":{"seven_day":{"used_percentage":33,"resets_at":'"$SAMPLE_7D"'}}}' \
    | HISTORY_FILE="$HTMP" USAGE_CACHE_OVERRIDE="$cache" CONFIG_OVERRIDE="$cfg" bash "$STATUSLINE" >/dev/null 2>&1
  rm -f "$cfg" "$cache"
  local got_metric got_util
  got_metric=$(tail -n1 "$HTMP" 2>/dev/null | jq -r '.metric // "none"')
  got_util=$(tail -n1 "$HTMP" 2>/dev/null | jq -r '.utilization')
  rm -f "$HTMP"
  if [ "$got_metric" = "seven_day" ]; then
    echo "✓ test_burn_history_subscription: history 有 seven_day 列"; ((PASS++))
  else
    echo "✗ test_burn_history_subscription: metric 應為 seven_day，實際得到 '$got_metric'"; ((FAIL++))
  fi
  if [ "$got_util" = "33" ]; then
    echo "✓ test_burn_history_subscription: utilization=33"; ((PASS++))
  else
    echo "✗ test_burn_history_subscription: utilization 應為 33，實際得到 '$got_util'"; ((FAIL++))
  fi
}

main() {
  echo "Running cyberpunk-statusline tests..."
  echo "======================================"

  test_exists
  test_default_output
  test_theme_json
  test_each_theme
  test_spacing_modes
  test_spend_block_quota
  test_spend_replaces_rate
  test_spend_degraded
  test_subscription_keeps_rate
  test_credit_block_quota
  test_credit_absent_hidden
  test_burn_history_subscription

  echo "======================================"
  echo "Results: $PASS passed, $FAIL failed"

  if [[ $FAIL -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
}

main
