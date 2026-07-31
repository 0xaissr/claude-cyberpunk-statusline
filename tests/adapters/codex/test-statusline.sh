#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RENDERER="$PROJECT_DIR/adapters/codex/statusline.sh"

PASS=0
FAIL=0

check_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -Fq -- "$needle"; then
    echo "✓ $label"
    ((PASS++))
  else
    echo "✗ $label — missing: $needle — got: $haystack"
    ((FAIL++))
  fi
}

test_no_sessions_outputs_placeholders() {
  local home_tmp
  home_tmp=$(mktemp -d)
  mkdir -p "$home_tmp/.codex"
  printf 'model = "gpt-5.5"\nmodel_reasoning_effort = "medium"\n' > "$home_tmp/.codex/config.toml"

  local out
  out=$(HOME="$home_tmp" CYBERPUNK_STATUSLINE_ROOT="$PROJECT_DIR" bash "$RENDERER" --line 2>/dev/null || true)
  rm -rf "$home_tmp"

  check_contains "no sessions includes model" "gpt-5.5" "$out"
  check_contains "no sessions uses statusline block style" "CTX" "$out"
  check_contains "no sessions includes context placeholder" "--" "$out"
  check_contains "no sessions includes rate label" "5H" "$out"
}

test_fixture_session_outputs_usage() {
  local home_tmp
  home_tmp=$(mktemp -d)
  mkdir -p "$home_tmp/.codex/sessions/2026/07/01"
  cp "$SCRIPT_DIR/fixtures/rate-session.jsonl" "$home_tmp/.codex/sessions/2026/07/01/rollout-test.jsonl"
  printf 'model = "gpt-5.5"\nmodel_reasoning_effort = "xhigh"\n' > "$home_tmp/.codex/config.toml"

  local out
  out=$(HOME="$home_tmp" CYBERPUNK_STATUSLINE_ROOT="$PROJECT_DIR" bash "$RENDERER" --line 2>/dev/null || true)
  rm -rf "$home_tmp"

  check_contains "fixture includes effort" "Xhigh" "$out"
  check_contains "fixture includes context" "42%" "$out"
  check_contains "fixture includes 5h" "68%" "$out"
  check_contains "fixture includes 7d" "86%" "$out"
}

test_real_token_count_session_outputs_usage() {
  local home_tmp
  home_tmp=$(mktemp -d)
  mkdir -p "$home_tmp/.codex/sessions/2026/07/01"
  cp "$SCRIPT_DIR/fixtures/real-token-count-session.jsonl" "$home_tmp/.codex/sessions/2026/07/01/rollout-real.jsonl"
  printf 'model = "gpt-5.5"\nmodel_reasoning_effort = "medium"\n' > "$home_tmp/.codex/config.toml"

  local out
  out=$(HOME="$home_tmp" CYBERPUNK_STATUSLINE_ROOT="$PROJECT_DIR" bash "$RENDERER" --line 2>/dev/null || true)
  rm -rf "$home_tmp"

  check_contains "real token count includes context percent" "5%" "$out"
  check_contains "real token count includes 5h percent" "39%" "$out"
  check_contains "real token count includes 7d percent" "6%" "$out"
}

test_real_token_count_session_outputs_resets_and_fallback_cost() {
  local home_tmp bin_tmp reset_5h reset_7d
  home_tmp=$(mktemp -d)
  bin_tmp=$(mktemp -d)
  reset_5h=$(($(date +%s) + 7200))
  reset_7d=$(($(date +%s) + 604800))
  mkdir -p "$home_tmp/.codex/sessions/2026/07/01"
  cat > "$home_tmp/.codex/sessions/2026/07/01/rollout-real.jsonl" <<JSONL
{"timestamp":"2026-07-01T08:28:14.789Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":73866,"cached_input_tokens":56832,"output_tokens":1378,"reasoning_output_tokens":106,"total_tokens":131117},"last_token_usage":{"input_tokens":22913,"cached_input_tokens":13184,"output_tokens":470,"reasoning_output_tokens":51,"total_tokens":23383},"model_context_window":258400},"rate_limits":{"limit_id":"codex","primary":{"used_percent":39.0,"window_minutes":300,"resets_at":$reset_5h},"secondary":{"used_percent":6.0,"window_minutes":10080,"resets_at":$reset_7d},"plan_type":"pro"}}}
JSONL
  printf 'model = "gpt-5.5"\nmodel_reasoning_effort = "medium"\n' > "$home_tmp/.codex/config.toml"
  cat > "$bin_tmp/npx" <<'SH'
#!/bin/sh
exit 1
SH
  chmod +x "$bin_tmp/npx"

  local out
  out=$(HOME="$home_tmp" PATH="$bin_tmp:/usr/bin:/bin" CYBERPUNK_STATUSLINE_ROOT="$PROJECT_DIR" CODEX_STATUSLINE_DISABLE_CACHE=1 bash "$RENDERER" --line 2>/dev/null || true)
  rm -rf "$home_tmp" "$bin_tmp"

  check_contains "real token count includes reset countdown" "↻" "$out"
  check_contains "real token count includes fallback estimated cost" "\$0.15" "$out"
}

test_ccusage_codex_cost_wins_when_available() {
  local home_tmp bin_tmp
  home_tmp=$(mktemp -d)
  bin_tmp=$(mktemp -d)
  mkdir -p "$home_tmp/.codex/sessions/2026/07/01"
  cp "$SCRIPT_DIR/fixtures/real-token-count-session.jsonl" "$home_tmp/.codex/sessions/2026/07/01/rollout-real.jsonl"
  printf 'model = "gpt-5.5"\nmodel_reasoning_effort = "medium"\n' > "$home_tmp/.codex/config.toml"
  cat > "$bin_tmp/ccusage" <<'SH'
#!/bin/sh
if [ "$1" = "codex" ] && [ "$2" = "daily" ]; then
  printf '{"totals":{"costUSD":12.34}}\n'
  exit 0
fi
exit 1
SH
  chmod +x "$bin_tmp/ccusage"

  local out
  out=$(HOME="$home_tmp" PATH="$bin_tmp:$PATH" CYBERPUNK_STATUSLINE_ROOT="$PROJECT_DIR" CODEX_STATUSLINE_DISABLE_CACHE=1 bash "$RENDERER" --line 2>/dev/null || true)
  rm -rf "$home_tmp" "$bin_tmp"

  check_contains "ccusage codex cost wins" "\$12.34" "$out"
}

test_npx_ccusage_codex_cost_wins_when_global_missing() {
  local home_tmp bin_tmp
  home_tmp=$(mktemp -d)
  bin_tmp=$(mktemp -d)
  mkdir -p "$home_tmp/.codex/sessions/2026/07/01"
  cp "$SCRIPT_DIR/fixtures/real-token-count-session.jsonl" "$home_tmp/.codex/sessions/2026/07/01/rollout-real.jsonl"
  printf 'model = "gpt-5.5"\nmodel_reasoning_effort = "medium"\n' > "$home_tmp/.codex/config.toml"
  cat > "$bin_tmp/npx" <<'SH'
#!/bin/sh
if [ "$1" = "ccusage@latest" ] && [ "$2" = "codex" ] && [ "$3" = "daily" ]; then
  printf '{"totals":{"costUSD":56.78}}\n'
  exit 0
fi
exit 1
SH
  chmod +x "$bin_tmp/npx"

  local out
  out=$(HOME="$home_tmp" PATH="$bin_tmp:/usr/bin:/bin" CYBERPUNK_STATUSLINE_ROOT="$PROJECT_DIR" CODEX_STATUSLINE_DISABLE_CACHE=1 bash "$RENDERER" --line 2>/dev/null || true)
  rm -rf "$home_tmp" "$bin_tmp"

  check_contains "npx ccusage codex cost wins" "\$56.78" "$out"
}

test_latest_session_skips_empty_newer_rollout() {
  local home_tmp
  home_tmp=$(mktemp -d)
  mkdir -p "$home_tmp/.codex/sessions/2026/07/01"
  cp "$SCRIPT_DIR/fixtures/rate-session.jsonl" "$home_tmp/.codex/sessions/2026/07/01/rollout-a.jsonl"
  printf '{"timestamp":"2026-07-01T09:00:00Z","type":"session_meta","payload":{}}\n' > "$home_tmp/.codex/sessions/2026/07/01/rollout-z.jsonl"
  printf 'model = "gpt-5.5"\nmodel_reasoning_effort = "medium"\n' > "$home_tmp/.codex/config.toml"

  local out
  out=$(HOME="$home_tmp" CYBERPUNK_STATUSLINE_ROOT="$PROJECT_DIR" CODEX_STATUSLINE_DISABLE_CACHE=1 bash "$RENDERER" --line 2>/dev/null || true)
  rm -rf "$home_tmp"

  check_contains "latest session skips empty newer rollout" "42%" "$out"
}

test_recent_render_is_cached() {
  local home_tmp
  home_tmp=$(mktemp -d)
  mkdir -p "$home_tmp/.codex/sessions/2026/07/01"
  cp "$SCRIPT_DIR/fixtures/rate-session.jsonl" "$home_tmp/.codex/sessions/2026/07/01/rollout-cache.jsonl"
  printf 'model = "gpt-5.5"\nmodel_reasoning_effort = "medium"\n' > "$home_tmp/.codex/config.toml"

  local first second third
  first=$(HOME="$home_tmp" CYBERPUNK_STATUSLINE_ROOT="$PROJECT_DIR" bash "$RENDERER" --line 2>/dev/null || true)
  cat > "$home_tmp/.codex/sessions/2026/07/01/rollout-cache.jsonl" <<'JSONL'
{"type":"usage","context_used_percent":7,"five_hour_percent":8,"weekly_percent":9}
JSONL
  second=$(HOME="$home_tmp" CYBERPUNK_STATUSLINE_ROOT="$PROJECT_DIR" bash "$RENDERER" --line 2>/dev/null || true)
  third=$(HOME="$home_tmp" CYBERPUNK_STATUSLINE_ROOT="$PROJECT_DIR" CODEX_STATUSLINE_DISABLE_CACHE=1 bash "$RENDERER" --line 2>/dev/null || true)
  rm -rf "$home_tmp"

  check_contains "cache keeps recent context percent" "42%" "$second"
  check_contains "cache bypass refreshes context percent" "7%" "$third"
  check_contains "cache initial render includes context percent" "42%" "$first"
}

# ── tokens block ─────────────────────────────────────────────────────────
# 顯式指定只含 session 的 config，讓斷言不受主 config.json 的區塊順序影響。
_tokens_only_config() {
  printf '{"theme":"terminal-glitch","symbol_set":"ascii","spacing":"normal","style":"classic","separator":"|","blocks":["session"],"bar_width":6,"show_icons":true,"account_type":"subscription"}' > "$1"
}

# _render_tokens <rollout_file_content_source> —— 以指定 rollout 內容跑一次 adapter
_render_tokens() {
  local rollout_src="$1"
  local home_tmp cfg out
  home_tmp=$(mktemp -d)
  cfg=$(mktemp)
  mkdir -p "$home_tmp/.codex/sessions/2026/07/01"
  cp "$rollout_src" "$home_tmp/.codex/sessions/2026/07/01/rollout-tokens.jsonl"
  printf 'model = "gpt-5.5"\nmodel_reasoning_effort = "medium"\n' > "$home_tmp/.codex/config.toml"
  _tokens_only_config "$cfg"

  out=$(HOME="$home_tmp" CYBERPUNK_STATUSLINE_ROOT="$PROJECT_DIR" \
    CODEX_STATUSLINE_CONFIG="$cfg" bash "$RENDERER" --line 2>/dev/null || true)
  rm -rf "$home_tmp"; rm -f "$cfg"
  printf '%s' "$out"
}

# 抽出 codex_session_tokens 的函式定義單獨執行，斷言精確 token 數
# （經 fmt_tokens 格式化後會失去分辨力）
_codex_tokens_fn() {
  bash -c "$(awk '/^codex_session_tokens\(\)/,/^}/' "$RENDERER"); codex_session_tokens \"\$1\"" _ "$1"
}

check_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "✓ $label"; ((PASS++))
  else
    echo "✗ $label — expected: $expected, got: $actual"; ((FAIL++))
  fi
}

test_session_tokens_from_real_fixture() {
  # 不再扣除 cached：73866 + 0(缺 cache_write，走 // 0) + 1378 = 75244 → 75K
  local out
  out=$(_render_tokens "$SCRIPT_DIR/fixtures/real-token-count-session.jsonl")
  check_contains "session tokens includes cached input" "75K" "$out"
}

test_session_tokens_counts_cache_write_not_reasoning() {
  # 2,000,000 + 250,000 + 100,000 = 2,350,000（cached 不再相減）
  # reasoning_output_tokens(40,000) 已含在 output_tokens 內，重複相加會變 2,390,000
  # 兩者經 fmt_tokens 都會印成 2.3M，故此處直接斷言整數
  local roll
  roll=$(mktemp)
  cat > "$roll" <<'JSON'
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":2000000,"cached_input_tokens":1500000,"cache_write_input_tokens":250000,"output_tokens":100000,"reasoning_output_tokens":40000,"total_tokens":2100000},"last_token_usage":{"total_tokens":51200},"model_context_window":258400}}}
JSON
  local out
  out=$(_codex_tokens_fn "$roll")
  rm -f "$roll"
  check_eq "session tokens = input + cache_write + output, no reasoning" "2350000" "$out"
}

test_codex_tokens_includes_cached() {
  local f
  f=$(mktemp)
  # input_tokens 已內含 cached_input_tokens；不再相減
  # 100000 + 5000 + 20000 = 125000（若仍相減會得 45000）
  printf '{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100000,"cached_input_tokens":80000,"cache_write_input_tokens":5000,"output_tokens":20000}}}}\n' > "$f"
  local out
  out=$(_codex_tokens_fn "$f")
  rm -f "$f"
  check_eq "session tokens does not subtract cached_input_tokens" "125000" "$out"
}

test_codex_config_uses_session_block() {
  # adapters/codex/config.json 是 gitignored 的使用者執行期設定，全新 clone 上根本不存在，
  # 因此只驗證兩個真正進版控的預設來源。
  local bad=""
  grep -q '"session"' "$PROJECT_DIR/adapters/codex/statusline.sh" || bad="fallback_config 缺 session"
  grep -q '"tokens"'  "$PROJECT_DIR/adapters/codex/statusline.sh" && bad="$bad; fallback_config 仍含 tokens"
  grep -q '"session"' "$PROJECT_DIR/install-codex.sh" || bad="$bad; install-codex.sh 缺 session"
  grep -q '"tokens"'  "$PROJECT_DIR/install-codex.sh" && bad="$bad; install-codex.sh 仍含 tokens"
  if [ -z "$bad" ]; then
    echo "✓ codex committed defaults use session instead of tokens"; ((PASS++))
  else
    echo "✗ codex defaults not migrated — $bad"; ((FAIL++))
  fi
}

test_session_tokens_degraded_without_token_count() {
  local out
  out=$(_render_tokens "$SCRIPT_DIR/fixtures/rate-session.jsonl")
  check_contains "session tokens degrades to placeholder" "[#] --" "$out"
}

test_no_claude_files_referenced() {
  if grep -R "\.claude" "$PROJECT_DIR/adapters/codex" >/dev/null 2>&1; then
    echo "✗ codex adapter references .claude"
    ((FAIL++))
  else
    echo "✓ codex adapter does not reference .claude"
    ((PASS++))
  fi
}

test_no_sessions_outputs_placeholders
test_fixture_session_outputs_usage
test_real_token_count_session_outputs_usage
test_real_token_count_session_outputs_resets_and_fallback_cost
test_ccusage_codex_cost_wins_when_available
test_npx_ccusage_codex_cost_wins_when_global_missing
test_latest_session_skips_empty_newer_rollout
test_recent_render_is_cached
test_session_tokens_from_real_fixture
test_session_tokens_counts_cache_write_not_reasoning
test_codex_tokens_includes_cached
test_codex_config_uses_session_block
test_session_tokens_degraded_without_token_count
test_no_claude_files_referenced

echo "PASS=$PASS FAIL=$FAIL"
exit "$FAIL"
