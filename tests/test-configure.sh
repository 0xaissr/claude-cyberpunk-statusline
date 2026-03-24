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

# ── Main ──────────────────────────────────────────────────────────────────
echo "=== configure.sh tests ==="
test_exists
test_requires_tty

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
