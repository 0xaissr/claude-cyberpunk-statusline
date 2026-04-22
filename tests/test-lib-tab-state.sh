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

echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "FAIL: $FAIL test(s)"
  exit 1
fi
echo "PASS: $PASS test(s)"
