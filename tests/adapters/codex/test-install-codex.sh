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
  local home_tmp config out
  home_tmp=$(mktemp -d)
  config="$home_tmp/codex-statusline.json"

  out=$(HOME="$home_tmp" CODEX_STATUSLINE_CONFIG="$config" CODEX_BIN_OVERRIDE=/bin/echo bash "$INSTALLER" --dry-run --theme tokyo-night --no-alias 2>&1 || true)

  assert_contains "dry run names Codex installer" "codex statusline installer" "$out"
  assert_contains "dry run reports official mode" "mode: official" "$out"
  assert_contains "dry run reports theme" "theme: tokyo-night" "$out"
  assert_contains "dry run reports Codex config" "adapters/codex/config.json" "$out"
  assert_contains "dry run reports Codex TOML config" ".codex/config.toml" "$out"
  assert_contains "dry run reports official status_line" "status_line" "$out"
  assert_contains "dry run reports alias choice" "alias codex: no" "$out"
  if echo "$out" | grep -Fq "status_line_command"; then
    fail "official dry run does not mention unsupported status_line_command" "$out"
  else
    pass "official dry run does not mention unsupported status_line_command"
  fi
  if echo "$out" | grep -Fq "install-patched.sh"; then
    fail "official dry run does not delegate patched installer" "$out"
  else
    pass "official dry run does not delegate patched installer"
  fi

  if [ -e "$config" ]; then
    fail "dry run does not create Codex config" "$config exists"
  else
    pass "dry run does not create Codex config"
  fi

  rm -rf "$home_tmp"
}

test_noninteractive_theme_writes_official_config_without_build() {
  local home_tmp fake_bin fake_installer log config toml real_jq out
  home_tmp=$(mktemp -d)
  fake_bin="$home_tmp/fake-bin"
  fake_installer="$home_tmp/install-patched.sh"
  log="$home_tmp/commands.log"
  config="$home_tmp/codex-statusline.json"
  toml="$home_tmp/.codex/config.toml"
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

  mkdir -p "$(dirname "$toml")"
  printf '[tui]\nstatus_line_command = "bash %s/adapters/codex/statusline.sh --line"\n' "$PROJECT_DIR" > "$toml"

  out=$(HOME="$home_tmp" \
    PATH="$fake_bin:$PATH" \
    FAKE_LOG="$log" \
    REAL_JQ="$real_jq" \
    CODEX_STATUSLINE_CONFIG="$config" \
    CODEX_PATCHED_INSTALLER_OVERRIDE="$fake_installer" \
    CODEX_CONFIG_TOML="$toml" \
    CODEX_BIN_OVERRIDE=/bin/echo \
    bash "$INSTALLER" --theme tokyo-night --no-alias 2>&1 || true)

  if [ -f "$config" ] && "$real_jq" -e '.theme == "tokyo-night" and (.blocks | index("cost")) and (.blocks | index("burn"))' "$config" >/dev/null; then
    pass "installer writes Codex-specific statusline config"
  else
    fail "installer writes Codex-specific statusline config" "$(cat "$config" 2>/dev/null || printf '%s' "$out")"
  fi

  if grep -Fq 'status_line = ["model-with-reasoning", "project-name", "five-hour-limit", "weekly-limit", "run-state", "context-used"]' "$toml"; then
    pass "installer writes official Codex status_line"
  else
    fail "installer writes official Codex status_line" "$(cat "$toml" 2>/dev/null || printf '%s' "$out")"
  fi

  if grep -Fq "status_line_command" "$toml"; then
    fail "official installer removes unsupported status_line_command" "$(cat "$toml")"
  else
    pass "official installer removes unsupported status_line_command"
  fi

  if [ -e "$log" ]; then
    fail "official installer does not call patched installer" "$(cat "$log")"
  else
    pass "official installer does not call patched installer"
  fi

  if [ -e "$home_tmp/.claude" ]; then
    fail "installer does not create Claude state" "$home_tmp/.claude exists"
  else
    pass "installer does not create Claude state"
  fi

  rm -rf "$home_tmp"
}

test_patched_mode_delegates_to_patched_installer() {
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
    bash "$INSTALLER" --patched --theme tokyo-night --no-alias 2>&1 || true)

  assert_contains "patched mode reports patched mode" "mode: patched" "$out"
  assert_contains "patched mode delegates to patched installer" "$fake_installer" "$(cat "$log" 2>/dev/null)"
  assert_contains "patched mode passes Codex config to patched installer" "CODEX_STATUSLINE_CONFIG=$config" "$(cat "$log" 2>/dev/null)"

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
test_noninteractive_theme_writes_official_config_without_build
test_patched_mode_delegates_to_patched_installer
test_rejects_unknown_theme_before_writes

echo "PASS=$PASS FAIL=$FAIL"
exit "$FAIL"
