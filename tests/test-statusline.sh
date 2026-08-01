#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STATUSLINE="$PROJECT_DIR/statusline.sh"
SAMPLE="$SCRIPT_DIR/sample-input.json"

# 多數測試用 home=$(mktemp -d)，那會讓 statusline 的 COST_CACHE_DIR 指向空目錄，
# 於是每一個這種測試都以為定價快取過期、各自 spawn 一次 1.67MB 的背景下載
# （實測讓整套從秒級變成 >120s，還會狂敲上游）。指向 /dev/null：非空字串會
# 停掉背景抓取，而 -s /dev/null 為假會讓 PRICING_JSON 維持 {}，剛好強制所有
# 斷言走內建定價表——這正是它們要驗的東西，也讓結果不受網路狀態影響。
# 唯一真的要連網的是 test_builtin_pricing_matches_upstream，它直接呼叫
# core/fetch-pricing.sh，不受這個 override 影響。
export PRICING_CACHE_OVERRIDE=/dev/null

PASS=0
FAIL=0
SKIP=0

# check <label> <expected> <actual>
check() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "✓ $label"; ((PASS++))
  else
    echo "✗ $label — expected: $expected, got: $actual"; ((FAIL++))
  fi
}

# skip <label> <reason> — for checks that need something the environment may
# not have (e.g. network). Not counted as a failure; surfaced in the summary
# so a permanently-skipped test can't hide.
skip() {
  echo "⊘ $1 — skipped: $2"; ((SKIP++))
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
  printf '{"theme":"terminal-glitch","symbol_set":"ascii","spacing":"normal","style":"classic","separator":"|","blocks":["session"],"bar_width":6,"show_icons":true,"account_type":"subscription"}'
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
  # (1000+2000+9999+500) + (4000+8000+9999+1500) = 36998 → "36K"
  # 成本：opus 5。in 5000*5 + cw 10000*10 + cr 19998*0.5 + out 2000*25
  #      = 25000 + 100000 + 9999 + 50000 = 184999 (per 1e6) = $0.184999 → $0.18
  { _tokens_entry m1 r1 1000 2000 9999 500
    _tokens_entry m2 r2 4000 8000 9999 1500; } > "$t"
  local out=$(_tokens_render "$t")
  rm -f "$t"
  check "test_tokens_sums_session_transcript: 四類 token 全加總" " [#] 36K \$0.18 " "$out"
}

test_tokens_dedupes_retried_request() {
  local t=$(mktemp)
  # 同一組 message.id|requestId 出現兩次，只能算一次
  # 10000+20000+9999+5000 = 44999 → "44K"
  # opus 5 成本：10000*5 + 20000*10 + 9999*0.5 + 5000*25
  #          = 50000 + 200000 + 4999.5 + 125000 = 379999.5 /1e6 = $0.3799995 → $0.38
  { _tokens_entry m1 r1 10000 20000 9999 5000
    _tokens_entry m1 r1 10000 20000 9999 5000; } > "$t"
  local out=$(_tokens_render "$t")
  rm -f "$t"
  check "test_tokens_dedupes_retried_request: 重複列只計一次" " [#] 44K \$0.38 " "$out"
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
  # 1,744,566 → 無條件捨去到一位小數 → 1.7M
  # opus 5 成本：1000000*5 + 500000*10 + 9999*0.5 + 234567*25
  #          = 5000000 + 5000000 + 4999.5 + 5864175 = 15869174.5 /1e6 → $15.87
  check "test_tokens_resolves_by_session_id: 用 session_id 找到 transcript" " [#] 1.7M \$15.87 " "$out"
}

test_session_includes_cache_read() {
  local t=$(mktemp)
  # cache_read 高達 5,000,000；必須被計入
  { _tokens_entry m1 r1 1000 2000 5000000 500; } > "$t"
  local out=$(_tokens_render "$t")
  rm -f "$t"
  # 1000+2000+5000000+500 = 5003500 → 5.0M
  # opus 5 成本：1000*5 + 2000*10 + 5000000*0.5 + 500*25
  #          = 5000 + 20000 + 2500000 + 12500 = 2537500 /1e6 → $2.54
  check "test_session_includes_cache_read: cache_read 計入 token" " [#] 5.0M \$2.54 " "$out"
}

test_session_prices_by_model() {
  local t=$(mktemp)
  # sonnet 單價：in 3 / cw(1h) 6 / cr 0.30 / out 15
  # 1000*3 + 2000*6 + 4000*0.30 + 500*15 = 3000+12000+1200+7500 = 23700 /1e6
  printf '{"type":"assistant","requestId":"r1","message":{"id":"m1","model":"claude-sonnet-5","usage":{"input_tokens":1000,"cache_creation_input_tokens":2000,"cache_read_input_tokens":4000,"output_tokens":500}}}\n' > "$t"
  local out=$(_tokens_render "$t")
  rm -f "$t"
  check "test_session_prices_by_model: sonnet 用 sonnet 單價" " [#] 7K \$0.02 " "$out"
}

# 內建定價表是 fallback（$PRICES 查不到時才用），但仍必須大致正確——2026-08-01
# 那次 bug 就是它從第一天起就填成 Opus 4.1 的 $15/$75，整整高估 3 倍且一個月沒人
# 發現。這個測試拿它跟上游對帳。
#
# 門檻刻意設成「差距達 2 倍才算失敗」而不是要求完全相等：上游會反映促銷價（例如
# Sonnet 5 到 2026-08-31 的 $2/$10 相對標準價 $3/$15 就是 1.5 倍），內建表則刻意
# 保守地放長期標準價。要抓的是「整個世代的價格都過時了」這種量級錯誤，不是追蹤
# 每一檔促銷。
test_builtin_pricing_matches_upstream() {
  local label="test_builtin_pricing_matches_upstream"
  local upstream
  upstream=$(bash "$PROJECT_DIR/core/fetch-pricing.sh" 2>/dev/null) || {
    skip "$label" "抓不到上游定價（離線？）"; return; }

  # eval 出 JQ_PRICE_FN 後直接用，不要再套一層 bash -c —— 之前那版寫成
  # `jq -cn "$JQ_PRICE_FN" 'builtin(...)'`，jq 會把第二個參數當成**檔名**而非
  # filter，於是每次都失敗回空字串，比對變成空對空、測試恆綠。突變測試（把內建
  # 表改回 $15/$75）才抓出這個假綠。
  local JQ_PRICE_FN=""
  eval "$(awk "/^JQ_PRICE_FN=/,/;'\$/" "$STATUSLINE")"
  if [ -z "$JQ_PRICE_FN" ]; then
    check "$label: 抽得到內建定價表" "non-empty" ""; return
  fi

  local m bad=""
  for m in claude-opus-5 claude-opus-4-8 claude-sonnet-5 claude-haiku-4-5; do
    local up
    up=$(printf '%s' "$upstream" | jq -c --arg m "$m" '.[$m] // empty')
    [ -z "$up" ] && continue
    # builtin() 不吃 $PRICES，可以獨立呼叫
    local bi
    bi=$(jq -cn "$JQ_PRICE_FN builtin(\"$m\")" 2>/dev/null)
    # 抽不到值代表測試本身壞了，必須紅——不能靜悄悄跳過而讓整條恆綠。
    if [ -z "$bi" ]; then
      bad="$bad\n    $m → 無法對內建表求值（測試壞了，不是定價問題）"
      continue
    fi
    local verdict
    verdict=$(jq -rn --argjson a "$bi" --argjson b "$up" '
      [ "i","o","cr" ]
      | map(. as $f
            | ($a[$f] // 0) as $x | ($b[$f] // 0) as $y
            | select($y > 0 and (($x / $y) >= 2 or ($x / $y) <= 0.5))
            | "\($f): 內建 \($x) vs 上游 \($y)")
      | join("; ")')
    [ -n "$verdict" ] && bad="$bad\n    $m → $verdict"
  done

  if [ -z "$bad" ]; then
    check "$label: 內建表與上游同一量級" "" ""
  else
    check "$label: 內建表與上游同一量級" "" "$(printf '%b' "$bad")"
  fi
}

# cache write 的兩種 TTL 單價不同（5m 是 input 的 1.25 倍、1h 是 2 倍）。
# usage.cache_creation 有分項時必須各自計價，不能一律套同一個單價。
test_cache_write_ttl_priced_separately() {
  local t=$(mktemp)
  # opus 5：cw5=6.25 / cw1h=10。100000 全走 5m vs 全走 1h 要差 375000/1e6=$0.375
  # 全 5m：100000*6.25 = 625000 /1e6 → $0.62（fmt_price 截到兩位）
  printf '{"type":"assistant","requestId":"r1","message":{"id":"m1","model":"claude-opus-5","usage":{"cache_creation_input_tokens":100000,"cache_creation":{"ephemeral_5m_input_tokens":100000,"ephemeral_1h_input_tokens":0}}}}\n' > "$t"
  check "test_cache_write_ttl_priced_separately: 全 5m 用 1.25x 單價" " [#] 100K \$0.62 " "$(_tokens_render "$t")"
  # 全 1h：100000*10 = 1000000 /1e6 → $1.00
  printf '{"type":"assistant","requestId":"r1","message":{"id":"m1","model":"claude-opus-5","usage":{"cache_creation_input_tokens":100000,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":100000}}}}\n' > "$t"
  check "test_cache_write_ttl_priced_separately: 全 1h 用 2x 單價" " [#] 100K \$1.00 " "$(_tokens_render "$t")"
  # 無 cache_creation 分項（舊 transcript）→ 退回 1h 單價，與上一筆同價
  printf '{"type":"assistant","requestId":"r1","message":{"id":"m1","model":"claude-opus-5","usage":{"cache_creation_input_tokens":100000}}}\n' > "$t"
  check "test_cache_write_ttl_priced_separately: 缺分項退回 1h 單價" " [#] 100K \$1.00 " "$(_tokens_render "$t")"
  rm -f "$t"
}

# group_by 會依 message.id 排序，若直接取 last 會拿到字典序最大的 m9 而非檔案順序的
# 最後一筆 m1。這個 fixture 的兩筆刻意讓字典序與檔案順序相反。
test_scan_last_chat_uses_file_order() {
  local t=$(mktemp)
  { _tokens_entry m9 r9 1 0 0 1
    _tokens_entry m1 r1 1000 0 0 1000; } > "$t"
  local out
  out=$(bash -c "$(awk "/^JQ_PRICE_FN=/,/;'\$/" "$STATUSLINE"); $(awk '/^_scan_transcript\(\)/,/^}/' "$STATUSLINE"); JQ=\$(command -v jq); PRICING_JSON='{}'; _scan_transcript \"$t\"")
  rm -f "$t"
  check "test_scan_last_chat_uses_file_order: session 加總兩筆" "2002" "$(echo "$out" | cut -d'|' -f1)"
  check "test_scan_last_chat_uses_file_order: last_chat 取檔案順序最後一筆" "2000" "$(echo "$out" | cut -d'|' -f3)"
}

test_session_degraded_without_transcript() {
  local home=$(mktemp -d) cfg=$(mktemp)
  _tokens_cfg > "$cfg"
  local out=$(printf '{"session_id":"no-such-session"}' \
    | env HOME="$home" CONFIG_OVERRIDE="$cfg" bash "$STATUSLINE" 2>/dev/null \
    | head -1 | sed 's/\x1b\[[0-9;]*m//g')
  rm -rf "$home"; rm -f "$cfg"
  check "test_session_degraded_without_transcript: 無 transcript 顯示 --" " [#] -- " "$out"
}

_last_chat_cfg() {
  printf '{"theme":"terminal-glitch","symbol_set":"ascii","spacing":"normal","style":"classic","separator":"|","blocks":["last_chat"],"bar_width":6,"show_icons":true,"account_type":"subscription"}'
}

test_last_chat_uses_final_message() {
  local t=$(mktemp) cfg=$(mktemp) home=$(mktemp -d)
  # 兩筆訊息，last_chat 只取最後一筆：4000+8000+1000+1500 = 14500 → 14K
  # opus 5 成本：4000*5 + 1500*25 + 8000*10 + 1000*0.5 = 20000+37500+80000+500
  #          = 138000 /1e6 = $0.138
  { _tokens_entry m1 r1 1000 2000 9999 500
    _tokens_entry m2 r2 4000 8000 1000 1500; } > "$t"
  _last_chat_cfg > "$cfg"
  local out=$(printf '{"session_id":"fixture","transcript_path":"%s"}' "$t" \
    | env HOME="$home" CONFIG_OVERRIDE="$cfg" bash "$STATUSLINE" 2>/dev/null \
    | head -1 | sed 's/\x1b\[[0-9;]*m//g')
  rm -rf "$home"; rm -f "$cfg" "$t"
  check "test_last_chat_uses_final_message: 只取最後一筆訊息" " [L] 14K \$0.14 " "$out"
}

test_session_without_cost_omits_dollar() {
  # Codex adapter 只餵 token 不餵金額，此時不可印出 $
  local cfg=$(mktemp) home=$(mktemp -d)
  _tokens_cfg > "$cfg"
  local out=$(printf '{"session_id":"x"}' \
    | env HOME="$home" CONFIG_OVERRIDE="$cfg" SESSION_TOKENS_OVERRIDE="123456" \
          bash "$STATUSLINE" 2>/dev/null \
    | head -1 | sed 's/\x1b\[[0-9;]*m//g')
  rm -rf "$home"; rm -f "$cfg"
  check "test_session_without_cost_omits_dollar: 無金額時只印 token" " [#] 123K " "$out"
}

test_line2_renders_second_row() {
  local t=$(mktemp) cfg=$(mktemp) home=$(mktemp -d)
  _tokens_entry m1 r1 1000 2000 1000 500 > "$t"
  printf '{"theme":"terminal-glitch","symbol_set":"ascii","spacing":"normal","style":"classic","separator":"|","blocks":["model"],"blocks_line2":["session","last_chat"],"bar_width":6,"show_icons":true,"account_type":"subscription"}' > "$cfg"
  local out=$(printf '{"session_id":"fixture","transcript_path":"%s","model":{"display_name":"Opus 5"}}' "$t" \
    | env HOME="$home" CONFIG_OVERRIDE="$cfg" bash "$STATUSLINE" 2>/dev/null \
    | sed 's/\x1b\[[0-9;]*m//g')
  rm -rf "$home"; rm -f "$cfg" "$t"
  local line2=$(printf '%s' "$out" | sed -n '2p')
  # 4500 tokens → "4K"；成本 1000*5 + 2000*10 + 1000*0.5 + 500*25
  #             = 5000 + 20000 + 500 + 12500 = 38000 /1e6 → $0.038
  # 只有一筆訊息，故 last_chat 與 session 數值相同
  # SEP 實測為 " | "，與區塊自帶的前後空白相加後是兩個空格（實測驗證過）
  check "test_line2_renders_second_row: 第二列有 session 與 last_chat" " [#] 4K \$0.04  |  [L] 4K \$0.04 " "$line2"
}

test_line2_absent_when_empty() {
  local t=$(mktemp) cfg=$(mktemp) home=$(mktemp -d)
  _tokens_entry m1 r1 1000 2000 1000 500 > "$t"
  printf '{"theme":"terminal-glitch","symbol_set":"ascii","spacing":"normal","style":"classic","separator":"|","blocks":["model"],"blocks_line2":[],"bar_width":6,"show_icons":true,"account_type":"subscription"}' > "$cfg"
  local out=$(printf '{"session_id":"fixture","transcript_path":"%s","model":{"display_name":"Opus 5"}}' "$t" \
    | env HOME="$home" CONFIG_OVERRIDE="$cfg" bash "$STATUSLINE" 2>/dev/null \
    | sed 's/\x1b\[[0-9;]*m//g')
  rm -rf "$home"; rm -f "$cfg" "$t"
  local nonempty=$(printf '%s' "$out" | grep -c '[^[:space:]]')
  check "test_line2_absent_when_empty: 空陣列時只有一列" "1" "$nonempty"
}

test_line2_absent_when_missing() {
  # 舊 config 沒有 blocks_line2 欄位，不應憑空多出第二列
  local t=$(mktemp) cfg=$(mktemp) home=$(mktemp -d)
  _tokens_entry m1 r1 1000 2000 1000 500 > "$t"
  printf '{"theme":"terminal-glitch","symbol_set":"ascii","spacing":"normal","style":"classic","separator":"|","blocks":["model"],"bar_width":6,"show_icons":true,"account_type":"subscription"}' > "$cfg"
  local out=$(printf '{"session_id":"fixture","transcript_path":"%s","model":{"display_name":"Opus 5"}}' "$t" \
    | env HOME="$home" CONFIG_OVERRIDE="$cfg" bash "$STATUSLINE" 2>/dev/null \
    | sed 's/\x1b\[[0-9;]*m//g')
  rm -rf "$home"; rm -f "$cfg" "$t"
  local nonempty=$(printf '%s' "$out" | grep -c '[^[:space:]]')
  check "test_line2_absent_when_missing: 欄位缺漏時只有一列" "1" "$nonempty"
}

test_legacy_tokens_maps_to_session() {
  # 舊 config 的 blocks 含 "tokens"，應映射成 session 區塊
  local t=$(mktemp) cfg=$(mktemp) home=$(mktemp -d)
  _tokens_entry m1 r1 1000 2000 1000 500 > "$t"
  printf '{"theme":"terminal-glitch","symbol_set":"ascii","spacing":"normal","style":"classic","separator":"|","blocks":["tokens"],"bar_width":6,"show_icons":true,"account_type":"subscription"}' > "$cfg"
  local out=$(printf '{"session_id":"fixture","transcript_path":"%s"}' "$t" \
    | env HOME="$home" CONFIG_OVERRIDE="$cfg" bash "$STATUSLINE" 2>/dev/null \
    | head -1 | sed 's/\x1b\[[0-9;]*m//g')
  rm -rf "$home"; rm -f "$cfg" "$t"
  check "test_legacy_tokens_maps_to_session: 舊 tokens 名稱仍可用" " [#] 4K \$0.04 " "$out"
}

test_line2_rainbow_colors_differ() {
  # rainbow 下第二列的兩個區塊必須拿到不同背景色
  local t=$(mktemp) cfg=$(mktemp) home=$(mktemp -d)
  _tokens_entry m1 r1 1000 2000 1000 500 > "$t"
  printf '{"theme":"terminal-glitch","symbol_set":"ascii","spacing":"normal","style":"rainbow","separator":"","head":"sharp","tail":"sharp","blocks":["model"],"blocks_line2":["session","last_chat"],"bar_width":6,"show_icons":true,"account_type":"subscription"}' > "$cfg"
  local line2=$(printf '{"session_id":"fixture","transcript_path":"%s","model":{"display_name":"Opus 5"}}' "$t" \
    | env HOME="$home" CONFIG_OVERRIDE="$cfg" bash "$STATUSLINE" 2>/dev/null \
    | sed -n '2p')
  rm -rf "$home"; rm -f "$cfg" "$t"
  # 抽出所有 48;2;R;G;B 背景色碼，去重後應有 2 種以上
  local n=$(printf '%s' "$line2" | grep -o '48;2;[0-9]*;[0-9]*;[0-9]*' | sort -u | wc -l | tr -d ' ')
  if [ "$n" -ge 2 ]; then
    echo "✓ test_line2_rainbow_colors_differ: 兩區塊背景色不同（$n 種）"; ((PASS++))
  else
    echo "✗ test_line2_rainbow_colors_differ: 應有至少 2 種背景色，實際 $n"; ((FAIL++))
  fi
}

# cost 區塊（_refresh_cost 本地 fallback）與 session/last_chat 區塊
# （_scan_transcript）曾各自維護一份 12 個數字的定價表，兩份一旦分岔，
# 同一條 status line 上的金額就會互相矛盾。兩者現在共用同一個
# $JQ_PRICE_FN（見 statusline.sh 開頭），這裡把同一筆合成 transcript
# 分別餵給兩條路徑，斷言算出的美元金額一致 —— 之後只要有人各改各的，
# 這個測試就會先炸。
test_cost_and_session_pricing_agree() {
  local home cache_dir today ts price_fn refresh_out scan_out scan_cost scan_rounded
  home=$(mktemp -d)
  mkdir -p "$home/.claude/projects/proj"
  today=$(date +%Y-%m-%d)
  ts="${today}T12:00:00.000Z"
  printf '{"type":"assistant","timestamp":"%s","requestId":"r1","message":{"id":"m1","model":"claude-opus-5","usage":{"input_tokens":1000,"cache_creation_input_tokens":2000,"cache_read_input_tokens":9999,"output_tokens":500}}}\n' "$ts" \
    > "$home/.claude/projects/proj/fixture.jsonl"

  cache_dir=$(mktemp -d)
  price_fn=$(awk "/^JQ_PRICE_FN=/,/;'\$/" "$STATUSLINE")

  # 路徑一：_refresh_cost 的本地 JSONL fallback（PATH 刻意不含 ccusage/npx，
  # 逼它走 fallback 分支）
  refresh_out=$(bash -c "
    $price_fn
    COST_CACHE_DIR=\"$cache_dir\"
    COST_CACHE=\"$cache_dir/daily-cost\"
    JQ=\$(command -v jq)
    PRICING_JSON='{}'   # 這條測的是內建表，不要讓網路快取影響結果
    $(awk '/^_refresh_cost\(\)/,/^}/' "$STATUSLINE")
    HOME=\"$home\" PATH=/usr/bin:/bin _refresh_cost
    cat \"$cache_dir/daily-cost\" 2>/dev/null
  ")

  # 路徑二：_scan_transcript（session/last_chat 用的那條）
  scan_out=$(bash -c "
    $price_fn
    JQ=\$(command -v jq)
    PRICING_JSON='{}'
    $(awk '/^_scan_transcript\(\)/,/^}/' "$STATUSLINE")
    _scan_transcript \"$home/.claude/projects/proj/fixture.jsonl\"
  ")
  rm -rf "$home" "$cache_dir"

  scan_cost=$(printf '%s' "$scan_out" | cut -d'|' -f2)
  scan_rounded=$(awk -v v="$scan_cost" 'BEGIN{printf "%.2f", v+0}')
  check "test_cost_and_session_pricing_agree: 兩條路徑算出同一筆金額" "$scan_rounded" "$refresh_out"
}

# blocks_line2 是手動編輯的設定面，打錯字（例如 "sesion"）機率比其他地方高。
# rainbow 樣式下，case 沒接住的區塊本來還是會印出頭尾 powerline glyph，
# 變成中間沒內容的孤兒符號；classic 則是內容留白但分隔符仍在。兩者都必須
# 整段跳過該區塊，全部打錯字時整列不輸出。
test_line2_unknown_block_skipped_rainbow() {
  local cfg=$(mktemp) home=$(mktemp -d)
  printf '{"theme":"terminal-glitch","symbol_set":"ascii","spacing":"normal","style":"rainbow","separator":"","head":"sharp","tail":"sharp","blocks":["model"],"blocks_line2":["sesion"],"bar_width":6,"show_icons":true,"account_type":"subscription"}' > "$cfg"
  local line2=$(cat "$SAMPLE" | env HOME="$home" CONFIG_OVERRIDE="$cfg" bash "$STATUSLINE" 2>/dev/null | sed -n '2p')
  rm -rf "$home"; rm -f "$cfg"
  check "test_line2_unknown_block_skipped_rainbow: 全部打錯字時第二列整段不輸出" "0" "${#line2}"
}

test_line2_unknown_block_skipped_alongside_known_rainbow() {
  # blocks_line2 為 ["sesion","last_chat"]：前者是錯字、後者有效。
  # 打錯字的那個不佔位（不消耗 idx 0 的頭部 glyph），有效的那個仍要正常
  # 渲染出內容 —— 用 grep 而非精確比對，因為 rainbow 頭尾本身就是合法的
  # powerline glyph，不是需要斷言不存在的東西。
  local t=$(mktemp) cfg=$(mktemp) home=$(mktemp -d)
  _tokens_entry m1 r1 1000 2000 1000 500 > "$t"
  printf '{"theme":"terminal-glitch","symbol_set":"ascii","spacing":"normal","style":"rainbow","separator":"","head":"sharp","tail":"sharp","blocks":["model"],"blocks_line2":["sesion","last_chat"],"bar_width":6,"show_icons":true,"account_type":"subscription"}' > "$cfg"
  local line2=$(printf '{"session_id":"fixture","transcript_path":"%s","model":{"display_name":"Opus 5"}}' "$t" \
    | env HOME="$home" CONFIG_OVERRIDE="$cfg" bash "$STATUSLINE" 2>/dev/null \
    | sed -n '2p' | sed 's/\x1b\[[0-9;]*m//g')
  rm -rf "$home"; rm -f "$cfg" "$t"
  if printf '%s' "$line2" | grep -q '\[L\] 4K \$0.04'; then
    echo "✓ test_line2_unknown_block_skipped_alongside_known_rainbow: 打錯字的區塊被跳過，正常區塊仍渲染"; ((PASS++))
  else
    echo "✗ test_line2_unknown_block_skipped_alongside_known_rainbow: last_chat 內容遺失 — got: $line2"; ((FAIL++))
  fi
}

test_tokens_number_formatting() {
  local cfg=$(mktemp) home=$(mktemp -d)
  _tokens_cfg > "$cfg"
  # 邊界重點：999999 不可進位成 "1000K"，必須維持 999K（跨單位溢位防護）
  local n expected out
  while IFS='|' read -r n expected; do
    out=$(printf '{"session_id":"x"}' \
      | env HOME="$home" CONFIG_OVERRIDE="$cfg" \
            SESSION_TOKENS_OVERRIDE="$n" SESSION_COST_OVERRIDE="1.5" \
            bash "$STATUSLINE" 2>/dev/null \
      | head -1 | sed 's/\x1b\[[0-9;]*m//g')
    check "test_tokens_number_formatting: $n" " [#] $expected \$1.50 " "$out"
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
0|0.00
0.3442|0.34
0.9999|1.00
1|1.00
1.894|1.89
89.2|89.20
1234.5|1234.50
0.0000015|0.00
EOF
  out=$(_call_fmt_price "")
  check "test_fmt_price_formatting: 空字串降級" "--" "$out"
  out=$(_call_fmt_price "abc")
  check "test_fmt_price_formatting: 非數字降級" "--" "$out"
  out=$(_call_fmt_price "nan")
  check "test_fmt_price_formatting: nan 降級" "--" "$out"
  out=$(_call_fmt_price "inf")
  check "test_fmt_price_formatting: inf 降級" "--" "$out"
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

test_themes_have_usage_blocks() {
  local themes_dir="$PROJECT_DIR/themes"
  local missing=""
  while IFS= read -r f; do
    local m
    m=$(jq -r '
      [ (if .symbols.nerd.session    then empty else "symbols.nerd.session"    end),
        (if .symbols.unicode.session then empty else "symbols.unicode.session" end),
        (if .symbols.ascii.session   then empty else "symbols.ascii.session"   end),
        (if .symbols.nerd.last_chat    then empty else "symbols.nerd.last_chat"    end),
        (if .symbols.unicode.last_chat then empty else "symbols.unicode.last_chat" end),
        (if .symbols.ascii.last_chat   then empty else "symbols.ascii.last_chat"   end),
        (if .blocks.session   then empty else "blocks.session"   end),
        (if .blocks.last_chat then empty else "blocks.last_chat" end)
      ] | join(",")' "$f" 2>/dev/null)
    [ -n "$m" ] && missing="$missing $(basename "$f"):$m"
  done < <(find "$themes_dir" -name "*.json" -type f)

  if [ -z "$missing" ]; then
    echo "✓ test_themes_have_usage_blocks: 所有主題都有 session/last_chat 定義"; ((PASS++))
  else
    echo "✗ test_themes_have_usage_blocks: 缺漏 —$missing"; ((FAIL++))
  fi
}

main() {
  echo "Running cyberpunk-statusline tests..."
  echo "======================================"

  test_exists
  test_default_output
  test_theme_json
  test_each_theme
  test_themes_have_usage_blocks
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
  test_tokens_dedupes_retried_request
  test_tokens_resolves_by_session_id
  test_session_includes_cache_read
  test_session_prices_by_model
  test_builtin_pricing_matches_upstream
  test_cache_write_ttl_priced_separately
  test_scan_last_chat_uses_file_order
  test_session_degraded_without_transcript
  test_last_chat_uses_final_message
  test_session_without_cost_omits_dollar
  test_line2_renders_second_row
  test_line2_absent_when_empty
  test_line2_absent_when_missing
  test_legacy_tokens_maps_to_session
  test_line2_rainbow_colors_differ
  test_line2_unknown_block_skipped_rainbow
  test_line2_unknown_block_skipped_alongside_known_rainbow
  test_cost_and_session_pricing_agree
  test_tokens_number_formatting
  test_fmt_price_formatting

  echo "======================================"
  if [ "$SKIP" -gt 0 ]; then
    echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
  else
    echo "Results: $PASS passed, $FAIL failed"
  fi

  if [[ $FAIL -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
}

main
