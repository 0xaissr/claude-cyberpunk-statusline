#!/usr/bin/env bash
# Tests for configure.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGURE="$PROJECT_DIR/scripts/configure.sh"

PASS=0
FAIL=0

pass() { PASS=$((PASS+1)); echo "  ✔ $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ✗ $1: $2"; }

# ── Test: script exists and is executable ─────────────────────────────────
test_exists() {
  echo "▸ test_exists"
  if [ -x "$CONFIGURE" ]; then
    pass "configure.sh is executable"
  else
    fail "configure.sh" "not found or not executable"
  fi
}

# ── Test: exits with error when stdin is not a TTY ────────────────────────
test_requires_tty() {
  echo "▸ test_requires_tty"
  local output
  output=$(echo "" | bash "$CONFIGURE" 2>&1) || true
  if echo "$output" | grep -q "interactive terminal"; then
    pass "rejects non-TTY stdin"
  else
    fail "TTY check" "did not reject piped stdin"
  fi
}

# ── Test: script contains all 5 step functions ────────────────────────────
test_step_functions() {
  echo "▸ test_step_functions"
  local missing=0
  for fn in step_symbols step_theme step_blocks step_spacing step_separator step_done; do
    if grep -q "^${fn}()" "$CONFIGURE"; then
      pass "$fn exists"
    else
      fail "$fn" "function not found"
      missing=$((missing + 1))
    fi
  done
}

# ── Test: script contains TUI primitives ──────────────────────────────────
test_tui_primitives() {
  echo "▸ test_tui_primitives"
  for fn in draw_header draw_footer read_key render_preview draw_preview menu_select; do
    if grep -q "^${fn}()" "$CONFIGURE"; then
      pass "$fn exists"
    else
      fail "$fn" "function not found"
    fi
  done
}

# ── Test: startup checks are present ──────────────────────────────────────
test_startup_checks() {
  echo "▸ test_startup_checks"
  if grep -q '\-t 0' "$CONFIGURE"; then
    pass "TTY check present"
  else
    fail "TTY check" "not found"
  fi
  if grep -q 'jq' "$CONFIGURE"; then
    pass "jq check present"
  else
    fail "jq check" "not found"
  fi
  if grep -q 'tput cols' "$CONFIGURE"; then
    pass "terminal size check present"
  else
    fail "terminal size" "not found"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────
echo "=== configure.sh tests ==="
test_exists
test_requires_tty
test_step_functions
test_tui_primitives
test_startup_checks

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
