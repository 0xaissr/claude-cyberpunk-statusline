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

test_real_flow_with_fake_tools_installs_binary_and_config() {
  local home_tmp fake_bin log config output source_cache out
  home_tmp=$(mktemp -d)
  fake_bin="$home_tmp/fake-bin"
  log="$home_tmp/commands.log"
  config="$home_tmp/.codex/config.toml"
  output="$home_tmp/.local/bin/codex-cyberpunk"
  source_cache="$home_tmp/source"
  mkdir -p "$fake_bin"

  cat > "$fake_bin/git" <<'SH'
#!/bin/sh
echo "git $*" >> "$FAKE_LOG"
if [ "$1" = "clone" ]; then
  for arg in "$@"; do
    dest="$arg"
  done
  mkdir -p "$dest/codex-rs"
  printf '[workspace]\n' > "$dest/codex-rs/Cargo.toml"
  mkdir -p "$dest/.git"
  exit 0
fi
if [ "$1" = "-C" ] && [ "$3" = "apply" ]; then
  exit 0
fi
exit 0
SH

  cat > "$fake_bin/cargo" <<'SH'
#!/bin/sh
echo "cargo $*" >> "$FAKE_LOG"
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--manifest-path" ]; then
    manifest="$2"
    break
  fi
  shift
done
root="$(dirname "$manifest")"
mkdir -p "$root/target/release"
printf '#!/bin/sh\necho codex-cyberpunk\n' > "$root/target/release/codex"
chmod +x "$root/target/release/codex"
SH
  chmod +x "$fake_bin/git" "$fake_bin/cargo"

  out=$(HOME="$home_tmp" \
    PATH="$fake_bin:$PATH" \
    FAKE_LOG="$log" \
    CODEX_BIN_OVERRIDE=/bin/echo \
    CODEX_SOURCE_REPO_OVERRIDE=/fake/codex.git \
    CODEX_PATCH_CACHE="$source_cache" \
    CODEX_OUTPUT_BIN_OVERRIDE="$output" \
    CODEX_CONFIG_TOML="$config" \
    bash "$INSTALLER" 2>&1 || true)

  if [ -x "$output" ]; then
    pass "real flow installs output binary"
  else
    fail "real flow installs output binary" "$out"
  fi

  if grep -Fq 'status_line_command = "bash ' "$config" && grep -Fq 'adapters/codex/statusline.sh" --line' "$config"; then
    pass "real flow writes Codex status_line_command"
  else
    fail "real flow writes Codex status_line_command" "$(cat "$config" 2>/dev/null)"
  fi

  assert_contains "real flow clones source" "git clone" "$(cat "$log")"
  assert_contains "real flow applies patch" "git -C $source_cache apply" "$(cat "$log")"
  assert_contains "real flow builds codex cli" "cargo build --release -p codex-cli --bin codex" "$(cat "$log")"

  if [ -e "$home_tmp/.claude" ]; then
    fail "real flow does not create Claude state" "$home_tmp/.claude exists"
  else
    pass "real flow does not create Claude state"
  fi

  rm -rf "$home_tmp"
}

test_dry_run_reports_plan_without_writes
test_dry_run_does_not_reference_claude
test_real_flow_with_fake_tools_installs_binary_and_config

echo "PASS=$PASS FAIL=$FAIL"
exit "$FAIL"
