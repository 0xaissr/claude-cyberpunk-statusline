#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
INSTALLER="$PROJECT_DIR/adapters/codex/install-patched.sh"

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
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -Fq -- "$needle"; then
    pass "$label"
  else
    fail "$label" "missing: $needle — got: $haystack"
  fi
}

test_dry_run_reports_plan_without_writes() {
  local home_tmp out
  home_tmp=$(mktemp -d)

  out=$(HOME="$home_tmp" CODEX_BIN_OVERRIDE=/bin/echo bash "$INSTALLER" --dry-run 2>&1 || true)

  assert_contains "dry run names codex binary" "/bin/echo" "$out"
  assert_contains "dry run names renderer path" "adapters/codex/statusline.sh" "$out"
  assert_contains "dry run names renderer mode" "--line" "$out"
  assert_contains "dry run names output binary" "codex-cyberpunk" "$out"
  assert_contains "dry run labels dry-run" "dry-run" "$out"

  if [ -e "$home_tmp/.local/bin" ]; then
    fail "dry run does not create local bin" "$home_tmp/.local/bin exists"
  else
    pass "dry run does not create local bin"
  fi

  rm -rf "$home_tmp"
}

test_dry_run_does_not_reference_claude() {
  local out
  out=$(HOME="$(mktemp -d)" CODEX_BIN_OVERRIDE=/bin/echo bash "$INSTALLER" --dry-run 2>&1 || true)
  if echo "$out" | grep -Fq ".claude"; then
    fail "dry run avoids Claude paths" "$out"
  else
    pass "dry run avoids Claude paths"
  fi
}

test_dry_run_reports_plan_without_writes
test_dry_run_does_not_reference_claude

echo "PASS=$PASS FAIL=$FAIL"
exit "$FAIL"
