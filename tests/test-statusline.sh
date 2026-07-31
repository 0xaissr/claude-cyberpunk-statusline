#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STATUSLINE="$PROJECT_DIR/statusline.sh"
SAMPLE="$SCRIPT_DIR/sample-input.json"

PASS=0
FAIL=0

# check <label> <expected> <actual>
check() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "✓ $label"; ((PASS++))
  else
    echo "✗ $label — expected: $expected, got: $actual"; ((FAIL++))
  fi
}

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

test_cost_uses_claude_only_ccusage() {
  local home_tmp bin_tmp cfg out
  home_tmp=$(mktemp -d)
  bin_tmp=$(mktemp -d)
  cfg=$(mktemp)
  printf '{"theme":"terminal-glitch","symbol_set":"unicode","spacing":"normal","style":"classic","separator":"|","blocks":["cost"],"bar_width":6,"show_icons":false,"account_type":"subscription"}' > "$cfg"
  cat > "$bin_tmp/ccusage" <<'SH'
#!/bin/sh
if [ "$1" = "claude" ] && [ "$2" = "daily" ]; then
  printf '7.89\n'
  exit 0
fi
if [ "$1" = "daily" ]; then
  printf '99.99\n'
  exit 0
fi
exit 1
SH
  chmod +x "$bin_tmp/ccusage"

  out=$(cat "$SAMPLE" | HOME="$home_tmp" PATH="$bin_tmp:$PATH" CONFIG_OVERRIDE="$cfg" bash "$STATUSLINE" 2>/dev/null || true)
  rm -rf "$home_tmp" "$bin_tmp"
  rm -f "$cfg"
  if echo "$out" | grep -q '\$7.89' && ! echo "$out" | grep -q '\$99.99'; then
    echo "✓ test_cost_uses_claude_only_ccusage: cost 只取 Claude 用量"; ((PASS++))
  else
    echo "✗ test_cost_uses_claude_only_ccusage: cost 應使用 ccusage claude daily — got: $out"; ((FAIL++))
  fi
}

# ── tokens block ─────────────────────────────────────────────────────────
# 只放 tokens 一個區塊、ascii symbol、關掉 icon 以外的雜訊，讓斷言鎖在數字本身。
_tokens_cfg() {
  printf '{"theme":"terminal-glitch","symbol_set":"ascii","spacing":"normal","style":"classic","separator":"|","blocks":["tokens"],"bar_width":6,"show_icons":true,"account_type":"subscription"}'
}

# _tokens_render <transcript_file> [extra_env_assignments...]
# 回傳去掉 ANSI 的第一行輸出。HOME 指向暫存目錄，避免污染真實快取。
_tokens_render() {
  local transcript="$1"; shift
  local cfg home out
  cfg=$(mktemp)
  home=$(mktemp -d)
  _tokens_cfg > "$cfg"
  out=$(printf '{"session_id":"fixture","transcript_path":"%s"}' "$transcript" \
    | env HOME="$home" CONFIG_OVERRIDE="$cfg" "$@" bash "$STATUSLINE" 2>/dev/null \
    | head -1 | sed 's/\x1b\[[0-9;]*m//g')
  rm -rf "$home"; rm -f "$cfg"
  printf '%s' "$out"
}

# _tokens_entry <msg_id> <req_id> <input> <cache_creation> <cache_read> <output>
_tokens_entry() {
  printf '{"type":"assistant","requestId":"%s","message":{"id":"%s","model":"claude-opus-5","usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s}}}\n' \
    "$2" "$1" "$3" "$4" "$5" "$6"
}

test_tokens_sums_session_transcript() {
  local t=$(mktemp)
  # 1000+2000+500=3500, 4000+8000+1500=13500 → 17000 → "17K"
  { _tokens_entry m1 r1 1000 2000 9999 500
    _tokens_entry m2 r2 4000 8000 9999 1500; } > "$t"
  local out=$(_tokens_render "$t")
  rm -f "$t"
  check "test_tokens_sums_session_transcript: 加總 input+cache_creation+output" " [#] 17K " "$out"
}

test_tokens_excludes_cache_read() {
  local t=$(mktemp)
  # cache_read 高達 5,000,000；若被計入會顯示 M 量級而非 3K
  { _tokens_entry m1 r1 1000 2000 5000000 500; } > "$t"
  local out=$(_tokens_render "$t")
  rm -f "$t"
  check "test_tokens_excludes_cache_read: cache_read 不計入" " [#] 3K " "$out"
}

test_tokens_dedupes_retried_request() {
  local t=$(mktemp)
  # 同一組 message.id|requestId 出現兩次，只能算一次
  { _tokens_entry m1 r1 10000 20000 9999 5000
    _tokens_entry m1 r1 10000 20000 9999 5000; } > "$t"
  local out=$(_tokens_render "$t")
  rm -f "$t"
  check "test_tokens_dedupes_retried_request: 重複列只計一次" " [#] 35K " "$out"
}

test_tokens_resolves_by_session_id() {
  # 不給 transcript_path，改由 session_id 在 $HOME/.claude/projects/*/ 找
  local home=$(mktemp -d) cfg=$(mktemp)
  mkdir -p "$home/.claude/projects/some-project"
  _tokens_entry m1 r1 1000000 500000 9999 234567 \
    > "$home/.claude/projects/some-project/abc-123.jsonl"
  _tokens_cfg > "$cfg"
  local out=$(printf '{"session_id":"abc-123"}' \
    | env HOME="$home" CONFIG_OVERRIDE="$cfg" bash "$STATUSLINE" 2>/dev/null \
    | head -1 | sed 's/\x1b\[[0-9;]*m//g')
  rm -rf "$home"; rm -f "$cfg"
  # 1,734,567 → 無條件捨去到一位小數 → 1.7M
  check "test_tokens_resolves_by_session_id: 用 session_id 找到 transcript" " [#] 1.7M " "$out"
}

test_tokens_degraded_without_transcript() {
  local home=$(mktemp -d) cfg=$(mktemp)
  _tokens_cfg > "$cfg"
  local out=$(printf '{"session_id":"no-such-session"}' \
    | env HOME="$home" CONFIG_OVERRIDE="$cfg" bash "$STATUSLINE" 2>/dev/null \
    | head -1 | sed 's/\x1b\[[0-9;]*m//g')
  rm -rf "$home"; rm -f "$cfg"
  check "test_tokens_degraded_without_transcript: 無 transcript 顯示 --" " [#] -- " "$out"
}

test_tokens_number_formatting() {
  local cfg=$(mktemp) home=$(mktemp -d)
  _tokens_cfg > "$cfg"
  # 邊界重點：999999 不可進位成 "1000K"，必須維持 999K（跨單位溢位防護）
  local n expected out
  while IFS='|' read -r n expected; do
    out=$(printf '{"session_id":"x"}' \
      | env HOME="$home" CONFIG_OVERRIDE="$cfg" SESSION_TOKENS_OVERRIDE="$n" bash "$STATUSLINE" 2>/dev/null \
      | head -1 | sed 's/\x1b\[[0-9;]*m//g')
    check "test_tokens_number_formatting: $n" " [#] $expected " "$out"
  done <<'EOF'
0|0
999|999
1000|1K
999999|999K
1000000|1.0M
12456789|12.4M
EOF
  rm -rf "$home"; rm -f "$cfg"
}

# ── fmt_price ────────────────────────────────────────────────────────────
# 直接 source statusline.sh 會執行整支腳本，因此改用 bash -c 抽出函式定義後求值。
_call_fmt_price() {
  local body
  body=$(awk '/^fmt_price\(\)/,/^}/' "$STATUSLINE")
  bash -c "$body; fmt_price \"\$1\"" _ "$1"
}

test_fmt_price_formatting() {
  local n expected out
  while IFS='|' read -r n expected; do
    out=$(_call_fmt_price "$n")
    check "test_fmt_price_formatting: $n" "$expected" "$out"
  done <<'EOF'
0|0.0000
0.3442|0.3442
0.9999|0.9999
1|1.00
1.894|1.89
89.2|89.20
1234.5|1234.50
EOF
  out=$(_call_fmt_price "")
  check "test_fmt_price_formatting: 空字串降級" "--" "$out"
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

test_credit_exhausted_hidden() {
  # credit 用光（utilization 100）時應隱藏 credit 區塊，只保留 spend（enterprise limit）
  local cfg=$(mktemp) cache=$(mktemp)
  printf '{"theme":"terminal-glitch","symbol_set":"nerd","spacing":"normal","style":"classic","separator":"|","blocks":["model","rate_5h","rate_7d","time"],"bar_width":6,"show_icons":false,"account_type":"auto"}' > "$cfg"
  printf '{"account_type":"quota","credit":{"utilization":100,"resets_at":%s},"spend":{"used_cents":12156,"limit_cents":50000,"utilization":24,"currency":"USD","resets_at":%s}}' "$(($(date +%s)+7776000))" "$(($(date +%s)+1814400))" > "$cache"
  local out=$(cat "$SAMPLE" | CONFIG_OVERRIDE="$cfg" USAGE_CACHE_OVERRIDE="$cache" bash "$STATUSLINE" 2>/dev/null || true)
  rm -f "$cfg" "$cache"
  if echo "$out" | grep -q 'CR'; then
    echo "✗ test_credit_exhausted_hidden: credit 用光時仍出現 CR — got: $out"; ((FAIL++))
  elif echo "$out" | grep -q '122/'; then
    echo "✓ test_credit_exhausted_hidden: credit 用光時隱藏 CR、保留 spend"; ((PASS++))
  else
    echo "✗ test_credit_exhausted_hidden: spend 未顯示 — got: $out"; ((FAIL++))
  fi
}

test_burn_block_renders_rate() {
  # burn 區塊：too_fast 歷史，確認輸出含速率數字（actual ≈ 20）
  local HTMP2; HTMP2=$(mktemp)
  local NOW2; NOW2=$(date +%s)
  local R2=$(( NOW2 + 4*86400 ))
  local PR2=$(( R2 - 7*86400 ))
  jq -cn --argjson t $(( NOW2 - 7*86400 )) --argjson r $PR2 \
    '{ts:$t,account_type:"subscription",metric:"seven_day",utilization:90,resets_at:$r}' > "$HTMP2"
  jq -cn --argjson t $(( NOW2 - 3*86400 )) --argjson r $R2 \
    '{ts:$t,account_type:"subscription",metric:"seven_day",utilization:0,resets_at:$r}' >> "$HTMP2"
  jq -cn --argjson t $NOW2 --argjson r $R2 \
    '{ts:$t,account_type:"subscription",metric:"seven_day",utilization:60,resets_at:$r}' >> "$HTMP2"
  local CFG2; CFG2=$(mktemp)
  echo '{"blocks":["model","burn"],"style":"classic","separator":"|","account_type":"subscription"}' > "$CFG2"
  local OUT
  OUT=$(echo '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/tmp"},"rate_limits":{"seven_day":{"used_percentage":60,"resets_at":'"$R2"'}}}' \
    | HISTORY_FILE="$HTMP2" USAGE_CACHE_OVERRIDE="$SCRIPT_DIR/core/fixtures/usage-subscription.json" CONFIG_OVERRIDE="$CFG2" bash "$STATUSLINE" 2>/dev/null)
  rm -f "$HTMP2" "$CFG2"
  # 格式：實際 〈關係符〉 健康（實際 20%/d > 健康 10%/d → "20.0 > 10.0"）
  check "burn block renders rate" "yes" "$(echo "$OUT" | grep -qE '[0-9]+(\.[0-9]+)? [><=] [0-9]+(\.[0-9]+)?' && echo yes || echo no)"
  check "burn block shows 20.0 > 10.0" "yes" "$(echo "$OUT" | grep -qE '20\.0 > 10\.0' && echo yes || echo no)"
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
  test_cost_uses_claude_only_ccusage
  test_credit_block_quota
  test_credit_absent_hidden
  test_credit_exhausted_hidden
  test_burn_history_subscription
  test_burn_block_renders_rate
  test_tokens_sums_session_transcript
  test_tokens_excludes_cache_read
  test_tokens_dedupes_retried_request
  test_tokens_resolves_by_session_id
  test_tokens_degraded_without_transcript
  test_tokens_number_formatting
  test_fmt_price_formatting

  echo "======================================"
  echo "Results: $PASS passed, $FAIL failed"

  if [[ $FAIL -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
}

main
