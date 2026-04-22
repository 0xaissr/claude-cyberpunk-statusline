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

assert_contains() {
  local output="$1" expected="$2" name="$3"
  if [[ "$output" == *"$expected"* ]]; then
    pass "$name"
  else
    fail "$name" "missing literal: $(printf '%q' "$expected")"
  fi
}

test_running_emits_rgb() {
  echo "▸ test_running_emits_rgb"
  local out; out=$(run_state running)
  # accent_1 = #28783C → (40, 120, 60)
  assert_contains "$out" $'\e]6;1;bg;red;brightness;40\a'   "running: red=40"
  assert_contains "$out" $'\e]6;1;bg;green;brightness;120\a' "running: green=120"
  assert_contains "$out" $'\e]6;1;bg;blue;brightness;60\a'  "running: blue=60"
}

test_error_emits_rgb() {
  echo "▸ test_error_emits_rgb"
  local out; out=$(run_state error)
  # alert = #A02828 → (160, 40, 40)
  assert_contains "$out" $'\e]6;1;bg;red;brightness;160\a'  "error: red=160"
  assert_contains "$out" $'\e]6;1;bg;green;brightness;40\a' "error: green=40"
  assert_contains "$out" $'\e]6;1;bg;blue;brightness;40\a'  "error: blue=40"
}

test_running_emits_rgb
test_error_emits_rgb

test_waiting_emits_attention() {
  echo "▸ test_waiting_emits_attention"
  local out; out=$(run_state waiting)
  assert_contains "$out" $'\e]1337;RequestAttention=yes\a' "waiting: RequestAttention"
}

test_clear_resets() {
  echo "▸ test_clear_resets"
  local out; out=$(run_state clear)
  assert_contains "$out" $'\e]6;1;bg;*;default\a' "clear: reset"
}

test_waiting_emits_attention
test_clear_resets

test_missing_state_uses_default() {
  echo "▸ test_missing_state_uses_default"
  local tmpdir; tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/themes"
  # tab_state enabled but no 'running' key → should fall back to DEFAULTS[running]=accent_1
  cat > "$tmpdir/config.json" <<JSON
{"theme":"test-theme","tab_state":{"enabled":true}}
JSON
  cp "$SCRIPT_DIR/fixtures/tab-state/themes/test-theme.json" "$tmpdir/themes/"
  local out
  out=$(TAB_STATE_OUT=/dev/stdout TERM_PROGRAM=iTerm.app \
    CYBERPUNK_STATUSLINE_REPO_DIR="$tmpdir" bash "$TAB_STATE" running 2>&1)
  rm -rf "$tmpdir"
  # accent_1 = #28783C → (40, 120, 60)
  assert_contains "$out" $'\e]6;1;bg;red;brightness;40\a' "fallback: running uses accent_1"
}

test_theme_switch_changes_rgb() {
  echo "▸ test_theme_switch_changes_rgb"
  local tmpdir; tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/themes"
  cat > "$tmpdir/config.json" <<JSON
{"theme":"alt-theme","tab_state":{"enabled":true,"running":"accent_1"}}
JSON
  # alt theme: accent_1 = #112233 → (17, 34, 51)
  cat > "$tmpdir/themes/alt-theme.json" <<'JSON'
{"colors":{"accent_1":"#112233"}}
JSON
  local out
  out=$(TAB_STATE_OUT=/dev/stdout TERM_PROGRAM=iTerm.app \
    CYBERPUNK_STATUSLINE_REPO_DIR="$tmpdir" bash "$TAB_STATE" running 2>&1)
  rm -rf "$tmpdir"
  assert_contains "$out" $'\e]6;1;bg;red;brightness;17\a'  "theme switch: red=17"
  assert_contains "$out" $'\e]6;1;bg;green;brightness;34\a' "theme switch: green=34"
  assert_contains "$out" $'\e]6;1;bg;blue;brightness;51\a' "theme switch: blue=51"
}

test_palette_typo_no_color() {
  echo "▸ test_palette_typo_no_color"
  local tmpdir; tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/themes"
  cat > "$tmpdir/config.json" <<JSON
{"theme":"test-theme","tab_state":{"enabled":true,"running":"nonexistent"}}
JSON
  cp "$SCRIPT_DIR/fixtures/tab-state/themes/test-theme.json" "$tmpdir/themes/"
  local out
  out=$(TAB_STATE_OUT=/dev/stdout TERM_PROGRAM=iTerm.app \
    CYBERPUNK_STATUSLINE_REPO_DIR="$tmpdir" bash "$TAB_STATE" running 2>&1)
  rm -rf "$tmpdir"
  if [[ "$out" != *"brightness;"* && "$out" != *"*;default"* ]]; then
    pass "typo palette: no bg color emitted"
  else
    fail "typo palette" "expected no bg escape; got: $(printf '%q' "$out")"
  fi
}

test_emits_tab_title() {
  echo "▸ test_emits_tab_title"
  local out; out=$(run_state running)
  if [[ "$out" == *$'\e]1;'*$'\a'* ]]; then
    pass "running emits tab title escape (\\e]1;...\\a)"
  else
    fail "tab title" "no \\e]1;...\\a in output: $(printf '%q' "$out")"
  fi
}

test_explicit_none_resets() {
  echo "▸ test_explicit_none_resets"
  local tmpdir; tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/themes"
  # Explicit palette=none → must emit reset, not RGB
  cat > "$tmpdir/config.json" <<JSON
{"theme":"test-theme","tab_state":{"enabled":true,"idle":"none"}}
JSON
  cp "$SCRIPT_DIR/fixtures/tab-state/themes/test-theme.json" "$tmpdir/themes/"
  local out
  out=$(TAB_STATE_OUT=/dev/stdout TERM_PROGRAM=iTerm.app \
    CYBERPUNK_STATUSLINE_REPO_DIR="$tmpdir" bash "$TAB_STATE" idle 2>&1)
  rm -rf "$tmpdir"
  assert_contains "$out" $'\e]6;1;bg;*;default\a' "explicit none: reset emitted"
  if [[ "$out" != *"brightness;"* ]]; then
    pass "explicit none: no RGB emitted"
  else
    fail "explicit none RGB" "expected no brightness; got: $(printf '%q' "$out")"
  fi
}

test_waiting_none_still_attention() {
  echo "▸ test_waiting_none_still_attention"
  local tmpdir; tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/themes"
  cat > "$tmpdir/config.json" <<JSON
{"theme":"test-theme","tab_state":{"enabled":true,"waiting":"none"}}
JSON
  cp "$SCRIPT_DIR/fixtures/tab-state/themes/test-theme.json" "$tmpdir/themes/"
  local out
  out=$(TAB_STATE_OUT=/dev/stdout TERM_PROGRAM=iTerm.app \
    CYBERPUNK_STATUSLINE_REPO_DIR="$tmpdir" bash "$TAB_STATE" waiting 2>&1)
  rm -rf "$tmpdir"
  assert_contains "$out" $'\e]1337;RequestAttention=yes\a' "waiting+none: attention still sent"
  assert_contains "$out" $'\e]6;1;bg;*;default\a' "waiting+none: reset emitted"
}

test_missing_state_uses_default
test_theme_switch_changes_rgb
test_palette_typo_no_color
test_emits_tab_title
test_explicit_none_resets
test_waiting_none_still_attention

echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "FAIL: $FAIL test(s) failed"
  exit 1
fi
echo "PASS: $PASS test(s)"
