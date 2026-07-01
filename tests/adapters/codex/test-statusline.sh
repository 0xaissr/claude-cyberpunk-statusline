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

test_real_token_count_session_outputs_resets_and_cost() {
  local home_tmp reset_5h reset_7d
  home_tmp=$(mktemp -d)
  reset_5h=$(($(date +%s) + 7200))
  reset_7d=$(($(date +%s) + 604800))
  mkdir -p "$home_tmp/.codex/sessions/2026/07/01"
  cat > "$home_tmp/.codex/sessions/2026/07/01/rollout-real.jsonl" <<JSONL
{"timestamp":"2026-07-01T08:28:14.789Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":73866,"cached_input_tokens":56832,"output_tokens":1378,"reasoning_output_tokens":106,"total_tokens":131117},"last_token_usage":{"input_tokens":22913,"cached_input_tokens":13184,"output_tokens":470,"reasoning_output_tokens":51,"total_tokens":23383},"model_context_window":258400},"rate_limits":{"limit_id":"codex","primary":{"used_percent":39.0,"window_minutes":300,"resets_at":$reset_5h},"secondary":{"used_percent":6.0,"window_minutes":10080,"resets_at":$reset_7d},"plan_type":"pro"}}}
JSONL
  printf 'model = "gpt-5.5"\nmodel_reasoning_effort = "medium"\n' > "$home_tmp/.codex/config.toml"

  local out
  out=$(HOME="$home_tmp" CYBERPUNK_STATUSLINE_ROOT="$PROJECT_DIR" CODEX_STATUSLINE_DISABLE_CACHE=1 bash "$RENDERER" --line 2>/dev/null || true)
  rm -rf "$home_tmp"

  check_contains "real token count includes reset countdown" "↻" "$out"
  check_contains "real token count includes estimated cost" "\$0.15" "$out"
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
test_real_token_count_session_outputs_resets_and_cost
test_recent_render_is_cached
test_no_claude_files_referenced

echo "PASS=$PASS FAIL=$FAIL"
exit "$FAIL"
