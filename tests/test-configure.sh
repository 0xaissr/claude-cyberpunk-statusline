#!/usr/bin/env bash
# Tests for configure.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGURE="$PROJECT_DIR/configure.sh"

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
  for fn in step_theme step_blocks step_spacing step_separator step_done; do
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
  for fn in draw_header draw_footer read_key render_preview draw_preview; do
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

# ── Test: second-line block configuration ────────────────────────────────
test_blocks_line2() {
  echo "▸ test_blocks_line2"

  if grep -q 'step_blocks_line2' "$CONFIGURE"; then
    pass "step_blocks_line2 present"
  else
    fail "step_blocks_line2" "not found"
  fi

  if grep -q 'line2_ids=("session" "last_chat")' "$CONFIGURE"; then
    pass "second line offers session and last_chat"
  else
    fail "line2_ids" "expected line2_ids=(\"session\" \"last_chat\")"
  fi

  if grep -q '"blocks_line2"' "$CONFIGURE"; then
    pass "blocks_line2 written to config"
  else
    fail "blocks_line2 field" "not emitted by render_preview or save"
  fi

  # 第二列允許零選取，故不可用 :- 回退 —— 空字串會被誤退回 cur_blocks_line2，
  # 使用者就永遠關不掉第二列
  if grep -q 'sel_blocks_line2_set' "$CONFIGURE"; then
    pass "sel_blocks_line2_set flag present"
  else
    fail "sel_blocks_line2_set" "not found — empty selection would fall back"
  fi

  if grep -q '\${sel_blocks_line2:-' "$CONFIGURE"; then
    fail "sel_blocks_line2 fallback" "must not use :- (breaks empty selection)"
  else
    pass "no :- fallback on sel_blocks_line2"
  fi

  # 第一列的 tokens 已由 session 取代
  if grep -q '"tokens"' "$CONFIGURE"; then
    fail "first line blocks" "still references tokens"
  else
    pass "first line no longer offers tokens"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────
echo "=== configure.sh tests ==="
test_exists
test_requires_tty
test_step_functions
test_tui_primitives
test_startup_checks
test_blocks_line2

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
