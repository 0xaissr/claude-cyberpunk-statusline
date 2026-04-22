#!/usr/bin/env bash
# _lib_tab_state.sh unit tests
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LIB="$PROJECT_DIR/_lib_tab_state.sh"
JQ=$(command -v jq)

PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s: %s\n' "$1" "$2" >&2; }

# Each test creates its own tmpdir with settings.json + scripts/
# Stores tmpdir in TEST_TMPDIR; exports overrides directly into current shell.
setup_env() {
  TEST_TMPDIR=$(mktemp -d)
  export CLAUDE_SETTINGS_OVERRIDE="$TEST_TMPDIR/settings.json"
  export CLAUDE_SCRIPTS_DIR_OVERRIDE="$TEST_TMPDIR/scripts"
  echo '{}' > "$CLAUDE_SETTINGS_OVERRIDE"
}

test_install_merges_six_hooks() {
  echo "▸ test_install_merges_six_hooks"
  setup_env
  local d="$TEST_TMPDIR"
  source "$LIB"
  _install_tab_state_hooks "$PROJECT_DIR"
  local rc=$?
  if [ "$rc" -ne 0 ]; then fail "install rc" "expected 0, got $rc"; rm -rf "$d"; return; fi
  for ev in SessionStart UserPromptSubmit PreToolUse Notification Stop SessionEnd; do
    if "$JQ" -e --arg ev "$ev" '.hooks[$ev] | length > 0' "$CLAUDE_SETTINGS_OVERRIDE" >/dev/null; then
      pass "$ev hook installed"
    else
      fail "$ev" "hook missing after install"
    fi
  done
  rm -rf "$d"
}

test_install_preserves_existing_hooks() {
  echo "▸ test_install_preserves_existing_hooks"
  setup_env
  local d="$TEST_TMPDIR"
  cat > "$CLAUDE_SETTINGS_OVERRIDE" <<'JSON'
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo userA"}]}]}}
JSON
  source "$LIB"
  _install_tab_state_hooks "$PROJECT_DIR"
  local count; count=$("$JQ" '.hooks.Stop | length' "$CLAUDE_SETTINGS_OVERRIDE")
  if [ "$count" = "2" ]; then
    pass "existing Stop hook preserved, ours appended"
  else
    fail "Stop hook count" "expected 2, got $count"
  fi
  rm -rf "$d"
}

test_install_creates_symlink() {
  echo "▸ test_install_creates_symlink"
  setup_env
  local d="$TEST_TMPDIR"
  source "$LIB"
  _install_tab_state_hooks "$PROJECT_DIR"
  if [ -L "$CLAUDE_SCRIPTS_DIR_OVERRIDE/tab-state.sh" ]; then
    pass "symlink created"
  else
    fail "symlink" "not created at $CLAUDE_SCRIPTS_DIR_OVERRIDE/tab-state.sh"
  fi
  rm -rf "$d"
}

test_install_merges_six_hooks
test_install_preserves_existing_hooks
test_install_creates_symlink

test_remove_clears_our_hooks() {
  echo "▸ test_remove_clears_our_hooks"
  setup_env
  local d="$TEST_TMPDIR"
  source "$LIB"
  _install_tab_state_hooks "$PROJECT_DIR"
  _remove_tab_state_hooks
  local total
  total=$("$JQ" '[.hooks // {} | to_entries[] | .value[] | .hooks[]? | .command | select(contains("tab-state.sh"))] | length' "$CLAUDE_SETTINGS_OVERRIDE")
  if [ "$total" = "0" ]; then
    pass "no tab-state commands remain"
  else
    fail "remove" "still $total tab-state hook(s) present"
  fi
  if [ ! -L "$CLAUDE_SCRIPTS_DIR_OVERRIDE/tab-state.sh" ]; then
    pass "symlink removed"
  else
    fail "symlink" "still present after remove"
  fi
  rm -rf "$d"
}

test_remove_preserves_other_user_hooks() {
  echo "▸ test_remove_preserves_other_user_hooks"
  setup_env
  local d="$TEST_TMPDIR"
  cat > "$CLAUDE_SETTINGS_OVERRIDE" <<'JSON'
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo userA"}]}]}}
JSON
  source "$LIB"
  _install_tab_state_hooks "$PROJECT_DIR"
  _remove_tab_state_hooks
  local count; count=$("$JQ" '.hooks.Stop | length' "$CLAUDE_SETTINGS_OVERRIDE")
  if [ "$count" = "1" ]; then
    pass "user's Stop hook still there"
  else
    fail "remove preserve" "expected 1 Stop hook, got $count"
  fi
  local cmd; cmd=$("$JQ" -r '.hooks.Stop[0].hooks[0].command' "$CLAUDE_SETTINGS_OVERRIDE")
  if [ "$cmd" = "echo userA" ]; then
    pass "user's command untouched"
  else
    fail "remove preserve" "wrong command: $cmd"
  fi
  rm -rf "$d"
}

test_remove_empty_settings_safe() {
  echo "▸ test_remove_empty_settings_safe"
  setup_env
  local d="$TEST_TMPDIR"
  source "$LIB"
  _remove_tab_state_hooks
  local rc=$?
  if [ "$rc" = "0" ]; then
    pass "remove on empty settings is no-op"
  else
    fail "remove empty" "exited nonzero: $rc"
  fi
  rm -rf "$d"
}

test_remove_clears_our_hooks
test_remove_preserves_other_user_hooks
test_remove_empty_settings_safe

test_detect_foreign_finds_claude_cli() {
  echo "▸ test_detect_foreign_finds_claude_cli"
  setup_env
  local d="$TEST_TMPDIR"
  # Simulate an existing claude-cli install: a hook pointing at /some/other/tab-state.sh
  cat > "$CLAUDE_SETTINGS_OVERRIDE" <<'JSON'
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/other/path/tab-state.sh idle"}]}]}}
JSON
  source "$LIB"
  local our_path="$CLAUDE_SCRIPTS_DIR_OVERRIDE/tab-state.sh"
  local found; found=$(_detect_foreign_tab_state_hooks "$our_path")
  if [[ "$found" == *"/other/path/tab-state.sh"* ]]; then
    pass "foreign hook detected"
  else
    fail "detect foreign" "expected /other/path, got: $found"
  fi
  rm -rf "$d"
}

test_detect_foreign_ignores_own() {
  echo "▸ test_detect_foreign_ignores_own"
  setup_env
  local d="$TEST_TMPDIR"
  source "$LIB"
  _install_tab_state_hooks "$PROJECT_DIR"
  local our_path="$CLAUDE_SCRIPTS_DIR_OVERRIDE/tab-state.sh"
  local found; found=$(_detect_foreign_tab_state_hooks "$our_path")
  if [ -z "$found" ]; then
    pass "own hooks not flagged as foreign"
  else
    fail "detect foreign" "falsely detected: $found"
  fi
  rm -rf "$d"
}

test_detect_foreign_finds_claude_cli
test_detect_foreign_ignores_own

echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "FAIL: $FAIL test(s)"
  exit 1
fi
echo "PASS: $PASS test(s)"
