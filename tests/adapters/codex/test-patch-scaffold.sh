#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PATCH_FILE="$PROJECT_DIR/adapters/codex/patches/status-line-command.patch"
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

test_patch_file_exists_and_names_key() {
  if [ -f "$PATCH_FILE" ]; then
    pass "patch file exists"
  else
    fail "patch file exists" "$PATCH_FILE missing"
    return
  fi

  assert_contains "patch mentions status_line_command" "status_line_command" "$(cat "$PATCH_FILE")"
}

test_installer_dry_run_references_patch() {
  local home_tmp out
  home_tmp=$(mktemp -d)
  out=$(HOME="$home_tmp" CODEX_BIN_OVERRIDE=/bin/echo bash "$INSTALLER" --dry-run 2>&1 || true)

  assert_contains "dry run names patch file" "status-line-command.patch" "$out"
  assert_contains "dry run names unsupported safety" "unsupported" "$out"

  rm -rf "$home_tmp"
}

test_patch_file_exists_and_names_key
test_installer_dry_run_references_patch

echo "PASS=$PASS FAIL=$FAIL"
exit "$FAIL"
