#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
UNINSTALLER="$PROJECT_DIR/adapters/codex/uninstall-patched.sh"

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

test_dry_run_reports_removals_without_writes() {
  local home_tmp config before after out
  home_tmp=$(mktemp -d)
  mkdir -p "$home_tmp/.codex"
  config="$home_tmp/.codex/config.toml"
  cat > "$config" <<TOML
[tui]
status_line = ["model"]
status_line_command = "bash $PROJECT_DIR/adapters/codex/statusline.sh --line"
TOML
  before=$(cat "$config")

  out=$(HOME="$home_tmp" bash "$UNINSTALLER" --dry-run 2>&1 || true)
  after=$(cat "$config")

  assert_contains "dry run reports status_line_command removal" "status_line_command" "$out"
  assert_contains "dry run reports output binary removal" "codex-cyberpunk" "$out"
  assert_contains "dry run labels dry-run" "dry-run" "$out"

  if [ "$before" = "$after" ]; then
    pass "dry run leaves config unchanged"
  else
    fail "dry run leaves config unchanged" "config changed"
  fi

  if [ -e "$home_tmp/.claude" ]; then
    fail "dry run does not create Claude state" "$home_tmp/.claude exists"
  else
    pass "dry run does not create Claude state"
  fi

  rm -rf "$home_tmp"
}

test_dry_run_avoids_claude_paths() {
  local home_tmp out
  home_tmp=$(mktemp -d)
  out=$(HOME="$home_tmp" bash "$UNINSTALLER" --dry-run 2>&1 || true)

  if echo "$out" | grep -Fq ".claude"; then
    fail "dry run avoids Claude paths" "$out"
  else
    pass "dry run avoids Claude paths"
  fi

  rm -rf "$home_tmp"
}

test_dry_run_reports_removals_without_writes
test_dry_run_avoids_claude_paths

echo "PASS=$PASS FAIL=$FAIL"
exit "$FAIL"
