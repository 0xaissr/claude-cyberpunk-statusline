#!/usr/bin/env bash
# tab-state.sh unit tests
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TAB_STATE="$PROJECT_DIR/tab-state.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s: %s\n' "$1" "$2" >&2; }

test_exists() {
  echo "▸ test_exists"
  if [ -x "$TAB_STATE" ]; then
    pass "tab-state.sh exists and is executable"
  else
    fail "tab-state.sh" "not found or not executable"
  fi
}

test_exists

run_state() {
  local state="$1" term="${2:-iTerm.app}"
  TAB_STATE_OUT=/dev/stdout TERM_PROGRAM="$term" \
    CYBERPUNK_STATUSLINE_REPO_DIR="$SCRIPT_DIR/fixtures/tab-state" \
    bash "$TAB_STATE" "$state" 2>&1
}

test_non_iterm_silent() {
  echo "▸ test_non_iterm_silent"
  local out; out=$(run_state running Apple_Terminal)
  if [ -z "$out" ]; then
    pass "non-iTerm2 produces no output"
  else
    fail "non-iTerm2" "expected empty, got: $(printf '%q' "$out")"
  fi
}

test_invalid_state() {
  echo "▸ test_invalid_state"
  TAB_STATE_OUT=/dev/stdout TERM_PROGRAM=iTerm.app bash "$TAB_STATE" bogus >/dev/null 2>&1
  if [ "$?" -ne 0 ]; then
    pass "invalid state exits nonzero"
  else
    fail "invalid state" "expected nonzero exit, got 0"
  fi
}

test_non_iterm_silent
test_invalid_state

test_disabled_silent() {
  echo "▸ test_disabled_silent"
  local tmpdir; tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/themes"
  cat > "$tmpdir/config.json" <<JSON
{"theme":"test-theme","tab_state":{"enabled":false,"running":"accent_1"}}
JSON
  cp "$SCRIPT_DIR/fixtures/tab-state/themes/test-theme.json" "$tmpdir/themes/"
  local out
  out=$(TAB_STATE_OUT=/dev/stdout TERM_PROGRAM=iTerm.app \
    CYBERPUNK_STATUSLINE_REPO_DIR="$tmpdir" bash "$TAB_STATE" running 2>&1)
  rm -rf "$tmpdir"
  if [ -z "$out" ]; then
    pass "enabled=false produces no output"
  else
    fail "enabled=false" "expected empty, got: $(printf '%q' "$out")"
  fi
}

test_missing_config_silent() {
  echo "▸ test_missing_config_silent"
  local tmpdir; tmpdir=$(mktemp -d)
  local out
  out=$(TAB_STATE_OUT=/dev/stdout TERM_PROGRAM=iTerm.app \
    CYBERPUNK_STATUSLINE_REPO_DIR="$tmpdir" bash "$TAB_STATE" running 2>&1)
  rm -rf "$tmpdir"
  if [ -z "$out" ]; then
    pass "missing config produces no output"
  else
    fail "missing config" "expected empty, got: $(printf '%q' "$out")"
  fi
}

test_disabled_silent
test_missing_config_silent

echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "FAIL: $FAIL test(s) failed"
  exit 1
fi
echo "PASS: $PASS test(s)"
