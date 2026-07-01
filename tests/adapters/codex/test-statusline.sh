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
test_no_claude_files_referenced

echo "PASS=$PASS FAIL=$FAIL"
exit "$FAIL"
