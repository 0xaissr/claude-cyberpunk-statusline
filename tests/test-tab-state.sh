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
  # accent_1 = #28783C → (40, 120, 60) max=120 → boosted to (67, 200, 100)
  assert_contains "$out" $'\e]6;1;bg;red;brightness;67\a'   "running: red=67 (boosted)"
  assert_contains "$out" $'\e]6;1;bg;green;brightness;200\a' "running: green=200 (boosted)"
  assert_contains "$out" $'\e]6;1;bg;blue;brightness;100\a' "running: blue=100 (boosted)"
}

test_error_emits_rgb() {
  echo "▸ test_error_emits_rgb"
  local out; out=$(run_state error)
  # alert = #A02828 → (160, 40, 40) max=160 → boosted to (200, 50, 50)
  assert_contains "$out" $'\e]6;1;bg;red;brightness;200\a' "error: red=200 (boosted)"
  assert_contains "$out" $'\e]6;1;bg;green;brightness;50\a' "error: green=50 (boosted)"
  assert_contains "$out" $'\e]6;1;bg;blue;brightness;50\a'  "error: blue=50 (boosted)"
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
  # tab_state enabled but no 'running' key → should fall back to _default_palette running=accent_1
  cat > "$tmpdir/config.json" <<JSON
{"theme":"test-theme","tab_state":{"enabled":true}}
JSON
  cp "$SCRIPT_DIR/fixtures/tab-state/themes/test-theme.json" "$tmpdir/themes/"
  local out
  out=$(TAB_STATE_OUT=/dev/stdout TERM_PROGRAM=iTerm.app \
    CYBERPUNK_STATUSLINE_REPO_DIR="$tmpdir" bash "$TAB_STATE" running 2>&1)
  rm -rf "$tmpdir"
  # accent_1 = #28783C → (40, 120, 60) → boosted red=67
  assert_contains "$out" $'\e]6;1;bg;red;brightness;67\a' "fallback: running uses accent_1 (boosted)"
}

test_theme_switch_changes_rgb() {
  echo "▸ test_theme_switch_changes_rgb"
  local tmpdir; tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/themes"
  cat > "$tmpdir/config.json" <<JSON
{"theme":"alt-theme","tab_state":{"enabled":true,"running":"accent_1"}}
JSON
  # alt theme: accent_1 = #112233 → (17, 34, 51) max=51 → boosted to (67, 133, 200)
  cat > "$tmpdir/themes/alt-theme.json" <<'JSON'
{"colors":{"accent_1":"#112233"}}
JSON
  local out
  out=$(TAB_STATE_OUT=/dev/stdout TERM_PROGRAM=iTerm.app \
    CYBERPUNK_STATUSLINE_REPO_DIR="$tmpdir" bash "$TAB_STATE" running 2>&1)
  rm -rf "$tmpdir"
  assert_contains "$out" $'\e]6;1;bg;red;brightness;67\a'   "theme switch: red=67 (boosted)"
  assert_contains "$out" $'\e]6;1;bg;green;brightness;133\a' "theme switch: green=133 (boosted)"
  assert_contains "$out" $'\e]6;1;bg;blue;brightness;200\a' "theme switch: blue=200 (boosted)"
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
  # Per-state emoji prefix
  assert_contains "$(run_state running)" $'\e]1;🟢 '  "running title has 🟢 prefix"
  assert_contains "$(run_state waiting)" $'\e]1;🟡 '  "waiting title has 🟡 prefix"
  assert_contains "$(run_state idle)"    $'\e]1;🔵 '  "idle title has 🔵 prefix"
  assert_contains "$(run_state error)"   $'\e]1;🔴 '  "error title has 🔴 prefix"
}

test_boost_keeps_bright_colors() {
  echo "▸ test_boost_keeps_bright_colors"
  local tmpdir; tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/themes"
  cat > "$tmpdir/config.json" <<JSON
{"theme":"bright","tab_state":{"enabled":true,"running":"accent_1"}}
JSON
  # bright color: accent_1 = #00F5FF → (0, 245, 255) max=255 → no boost expected
  cat > "$tmpdir/themes/bright.json" <<'JSON'
{"colors":{"accent_1":"#00F5FF"}}
JSON
  local out
  out=$(TAB_STATE_OUT=/dev/stdout TERM_PROGRAM=iTerm.app \
    CYBERPUNK_STATUSLINE_REPO_DIR="$tmpdir" bash "$TAB_STATE" running 2>&1)
  rm -rf "$tmpdir"
  assert_contains "$out" $'\e]6;1;bg;red;brightness;0\a'    "bright color: red untouched"
  assert_contains "$out" $'\e]6;1;bg;green;brightness;245\a' "bright color: green untouched"
  assert_contains "$out" $'\e]6;1;bg;blue;brightness;255\a' "bright color: blue untouched"
}

test_boost_lifts_dim_colors() {
  echo "▸ test_boost_lifts_dim_colors"
  local tmpdir; tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/themes"
  cat > "$tmpdir/config.json" <<JSON
{"theme":"dim","tab_state":{"enabled":true,"running":"accent_1"}}
JSON
  # dim color: accent_1 = #285C8C → (40, 92, 140) max=140 → boosted to (57, 131, 200)
  cat > "$tmpdir/themes/dim.json" <<'JSON'
{"colors":{"accent_1":"#285C8C"}}
JSON
  local out
  out=$(TAB_STATE_OUT=/dev/stdout TERM_PROGRAM=iTerm.app \
    CYBERPUNK_STATUSLINE_REPO_DIR="$tmpdir" bash "$TAB_STATE" running 2>&1)
  rm -rf "$tmpdir"
  # 40*200/140=57.14, 92*200/140=131.43, 140*200/140=200 → (57,131,200) after +0.5 round
  assert_contains "$out" $'\e]6;1;bg;red;brightness;57\a'    "dim color: red boosted to 57"
  assert_contains "$out" $'\e]6;1;bg;green;brightness;131\a' "dim color: green boosted to 131"
  assert_contains "$out" $'\e]6;1;bg;blue;brightness;200\a'  "dim color: blue boosted to 200"
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
test_boost_keeps_bright_colors
test_boost_lifts_dim_colors
test_explicit_none_resets
test_waiting_none_still_attention

echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "FAIL: $FAIL test(s) failed"
  exit 1
fi
echo "PASS: $PASS test(s)"
