#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LIB="$PROJECT_DIR/adapters/codex/lib-config.sh"

PASS=0
FAIL=0

pass() {
  echo "✓ $1"
  ((PASS++))
}

fail() {
  echo "✗ $1 — $2"
  ((FAIL++))
}

assert_contains() {
  local label="$1" needle="$2" file="$3"
  if grep -Fq "$needle" "$file"; then
    pass "$label"
  else
    fail "$label" "missing: $needle"
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" file="$3"
  if grep -Fq "$needle" "$file"; then
    fail "$label" "unexpected: $needle"
  else
    pass "$label"
  fi
}

test_set_adds_tui_command_and_preserves_existing_status_line() {
  # shellcheck source=/dev/null
  source "$LIB"
  local tmp
  tmp=$(mktemp)
  cat > "$tmp" <<'TOML'
model = "gpt-5.5"

[tui]
status_line = ["model-with-reasoning", "context-remaining"]
notifications = false

[projects."/tmp/example"]
trust_level = "trusted"
TOML

  _codex_set_status_line_command "$tmp" 'bash /repo/adapters/codex/statusline.sh --line'

  assert_contains "set keeps status_line" 'status_line = ["model-with-reasoning", "context-remaining"]' "$tmp"
  assert_contains "set adds status_line_command" 'status_line_command = "bash /repo/adapters/codex/statusline.sh --line"' "$tmp"
  assert_contains "set preserves unrelated table" '[projects."/tmp/example"]' "$tmp"
  rm -f "$tmp" "$tmp".bak.*
}

test_set_appends_tui_when_missing() {
  # shellcheck source=/dev/null
  source "$LIB"
  local tmp
  tmp=$(mktemp)
  printf 'model = "gpt-5.5"\n' > "$tmp"

  _codex_set_status_line_command "$tmp" 'bash /repo/adapters/codex/statusline.sh --line'

  assert_contains "append creates tui table" '[tui]' "$tmp"
  assert_contains "append adds command" 'status_line_command = "bash /repo/adapters/codex/statusline.sh --line"' "$tmp"
  rm -f "$tmp" "$tmp".bak.*
}

test_remove_only_project_owned_command() {
  # shellcheck source=/dev/null
  source "$LIB"
  local tmp
  tmp=$(mktemp)
  cat > "$tmp" <<'TOML'
[tui]
status_line = ["model"]
status_line_command = "bash /repo/adapters/codex/statusline.sh --line"
notifications = false
TOML

  _codex_remove_status_line_command "$tmp" "/repo"

  assert_not_contains "remove deletes project command" 'status_line_command' "$tmp"
  assert_contains "remove keeps status_line" 'status_line = ["model"]' "$tmp"
  assert_contains "remove keeps notifications" 'notifications = false' "$tmp"
  rm -f "$tmp" "$tmp".bak.*
}

test_remove_preserves_foreign_command() {
  # shellcheck source=/dev/null
  source "$LIB"
  local tmp
  tmp=$(mktemp)
  cat > "$tmp" <<'TOML'
[tui]
status_line_command = "bash /other/project/statusline.sh --line"
TOML

  _codex_remove_status_line_command "$tmp" "/repo"

  assert_contains "remove preserves foreign command" 'status_line_command = "bash /other/project/statusline.sh --line"' "$tmp"
  rm -f "$tmp" "$tmp".bak.*
}

test_set_adds_tui_command_and_preserves_existing_status_line
test_set_appends_tui_when_missing
test_remove_only_project_owned_command
test_remove_preserves_foreign_command

echo "PASS=$PASS FAIL=$FAIL"
exit "$FAIL"
