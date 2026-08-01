#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
INSTALLER="$PROJECT_DIR/adapters/codex/install-patched.sh"
# Resolved up front: the preflight tests run with a PATH that deliberately has
# almost nothing on it, so `bash` has to be reached by absolute path.
BASH_BIN="$(command -v bash)"

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
  local home_tmp fake_bin log config output source_cache statusline_config out
  home_tmp=$(mktemp -d)
  fake_bin="$home_tmp/fake-bin"
  log="$home_tmp/commands.log"
  config="$home_tmp/.codex/config.toml"
  output="$home_tmp/.local/bin/codex-cyberpunk"
  source_cache="$home_tmp/source"
  statusline_config="$home_tmp/codex-statusline.json"
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
    CODEX_STATUSLINE_CONFIG="$statusline_config" \
    bash "$INSTALLER" 2>&1 || true)

  if [ -x "$output" ]; then
    pass "real flow installs output binary"
  else
    fail "real flow installs output binary" "$out"
  fi

  if grep -Fq "CODEX_STATUSLINE_CONFIG=\\\"$statusline_config\\\" bash" "$config" \
    && grep -Fq 'adapters/codex/statusline.sh\" --line"' "$config"; then
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

# A PATH holding only what the script needs before its preflight check runs, so
# "cargo is absent" is a property of the fixture rather than of the dev machine.
make_cargoless_path() {
  local fake_bin="$1"
  mkdir -p "$fake_bin"
  ln -sf "$(command -v dirname)" "$fake_bin/dirname"
  cat > "$fake_bin/git" <<'SH'
#!/bin/sh
echo "git $*" >> "$FAKE_LOG"
exit 0
SH
  chmod +x "$fake_bin/git"
}

test_missing_cargo_aborts_before_touching_anything() {
  local home_tmp fake_bin log source_cache output out status
  home_tmp=$(mktemp -d)
  fake_bin="$home_tmp/fake-bin"
  log="$home_tmp/commands.log"
  source_cache="$home_tmp/source"
  output="$home_tmp/.local/bin/codex-cyberpunk"
  make_cargoless_path "$fake_bin"

  out=$(HOME="$home_tmp" \
    PATH="$fake_bin" \
    FAKE_LOG="$log" \
    CODEX_BIN_OVERRIDE=/bin/echo \
    CODEX_PATCH_CACHE="$source_cache" \
    CODEX_OUTPUT_BIN_OVERRIDE="$output" \
    "$BASH_BIN" "$INSTALLER" 2>&1)
  status=$?

  if [ "$status" -eq 1 ]; then
    pass "missing cargo exits 1"
  else
    fail "missing cargo exits 1" "got status $status — $out"
  fi

  assert_contains "missing cargo is named" "missing required tools: cargo" "$out"
  assert_contains "missing cargo points at rustup" "https://rustup.rs" "$out"

  if [ -e "$log" ]; then
    fail "missing cargo aborts before cloning" "git ran: $(cat "$log")"
  else
    pass "missing cargo aborts before cloning"
  fi

  if [ -e "$source_cache" ]; then
    fail "missing cargo leaves no source cache" "$source_cache exists"
  else
    pass "missing cargo leaves no source cache"
  fi

  if [ -e "$output" ]; then
    fail "missing cargo installs no binary" "$output exists"
  else
    pass "missing cargo installs no binary"
  fi

  rm -rf "$home_tmp"
}

test_dry_run_warns_about_missing_cargo_without_failing() {
  local home_tmp fake_bin out status
  home_tmp=$(mktemp -d)
  fake_bin="$home_tmp/fake-bin"
  make_cargoless_path "$fake_bin"

  out=$(HOME="$home_tmp" \
    PATH="$fake_bin" \
    FAKE_LOG="$home_tmp/commands.log" \
    CODEX_BIN_OVERRIDE=/bin/echo \
    "$BASH_BIN" "$INSTALLER" --dry-run 2>&1)
  status=$?

  if [ "$status" -eq 0 ]; then
    pass "dry run with missing cargo still exits 0"
  else
    fail "dry run with missing cargo still exits 0" "got status $status — $out"
  fi

  assert_contains "dry run warns about missing cargo" "missing required tools: cargo" "$out"
  assert_contains "dry run still reports no writes" "dry-run: no files were changed" "$out"

  rm -rf "$home_tmp"
}

test_plan_lists_required_tools() {
  local out
  out=$(HOME="$(mktemp -d)" CODEX_BIN_OVERRIDE=/bin/echo bash "$INSTALLER" --dry-run 2>&1 || true)
  assert_contains "plan lists required tools" "requires: git, cargo" "$out"
}

test_dry_run_reports_plan_without_writes
test_dry_run_does_not_reference_claude
test_plan_lists_required_tools
test_missing_cargo_aborts_before_touching_anything
test_dry_run_warns_about_missing_cargo_without_failing
test_real_flow_with_fake_tools_installs_binary_and_config

echo "PASS=$PASS FAIL=$FAIL"
exit "$FAIL"
