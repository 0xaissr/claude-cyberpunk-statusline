#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
INSTALLER="$PROJECT_DIR/install-codex.sh"

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

test_dry_run_reports_guided_codex_steps() {
  local home_tmp out
  home_tmp=$(mktemp -d)

  out=$(HOME="$home_tmp" CODEX_BIN_OVERRIDE=/bin/echo bash "$INSTALLER" --dry-run --theme tokyo-night --no-alias 2>&1 || true)

  assert_contains "dry run names Codex installer" "codex statusline installer" "$out"
  assert_contains "dry run reports theme" "theme: tokyo-night" "$out"
  assert_contains "dry run reports Codex config" "adapters/codex/config.json" "$out"
  assert_contains "dry run delegates patched installer" "adapters/codex/install-patched.sh --dry-run" "$out"
  assert_contains "dry run reports alias choice" "alias codex: no" "$out"

  if [ -e "$PROJECT_DIR/adapters/codex/config.json" ]; then
    fail "dry run does not create Codex config" "$PROJECT_DIR/adapters/codex/config.json exists"
  else
    pass "dry run does not create Codex config"
  fi

  rm -rf "$home_tmp"
}

test_noninteractive_theme_writes_codex_config_and_delegates() {
  local home_tmp fake_bin fake_installer log config real_jq out
  home_tmp=$(mktemp -d)
  fake_bin="$home_tmp/fake-bin"
  fake_installer="$home_tmp/install-patched.sh"
  log="$home_tmp/commands.log"
  config="$home_tmp/codex-statusline.json"
  real_jq=$(command -v jq)
  mkdir -p "$fake_bin"

  cat > "$fake_bin/jq" <<'SH'
#!/bin/sh
exec "$REAL_JQ" "$@"
SH

  cat > "$fake_installer" <<'SH'
#!/bin/sh
echo "$0 $*" >> "$FAKE_LOG"
echo "CODEX_STATUSLINE_CONFIG=$CODEX_STATUSLINE_CONFIG" >> "$FAKE_LOG"
exit 0
SH

  chmod +x "$fake_bin/jq" "$fake_installer"

  out=$(HOME="$home_tmp" \
    PATH="$fake_bin:$PATH" \
    FAKE_LOG="$log" \
    REAL_JQ="$real_jq" \
    CODEX_STATUSLINE_CONFIG="$config" \
    CODEX_PATCHED_INSTALLER_OVERRIDE="$fake_installer" \
    CODEX_BIN_OVERRIDE=/bin/echo \
    bash "$INSTALLER" --theme tokyo-night --no-alias 2>&1 || true)

  if [ -f "$config" ] && "$real_jq" -e '.theme == "tokyo-night" and (.blocks | index("cost")) and (.blocks | index("burn"))' "$config" >/dev/null; then
    pass "installer writes Codex-specific statusline config"
  else
    fail "installer writes Codex-specific statusline config" "$(cat "$config" 2>/dev/null || printf '%s' "$out")"
  fi

  assert_contains "installer delegates to patched installer" "$fake_installer" "$(cat "$log" 2>/dev/null)"
  assert_contains "installer passes Codex config to patched installer" "CODEX_STATUSLINE_CONFIG=$config" "$(cat "$log" 2>/dev/null)"

  if [ -e "$home_tmp/.claude" ]; then
    fail "installer does not create Claude state" "$home_tmp/.claude exists"
  else
    pass "installer does not create Claude state"
  fi

  rm -rf "$home_tmp"
}

test_rejects_unknown_theme_before_writes() {
  local home_tmp config out
  home_tmp=$(mktemp -d)
  config="$home_tmp/codex-statusline.json"

  out=$(HOME="$home_tmp" CODEX_STATUSLINE_CONFIG="$config" CODEX_BIN_OVERRIDE=/bin/echo bash "$INSTALLER" --theme not-a-theme --no-alias 2>&1 || true)

  assert_contains "unknown theme is rejected" "unknown theme: not-a-theme" "$out"
  if [ -e "$config" ]; then
    fail "unknown theme does not write config" "$(cat "$config")"
  else
    pass "unknown theme does not write config"
  fi

  rm -rf "$home_tmp"
}

test_dry_run_reports_guided_codex_steps
test_noninteractive_theme_writes_codex_config_and_delegates
test_rejects_unknown_theme_before_writes

echo "PASS=$PASS FAIL=$FAIL"
exit "$FAIL"
