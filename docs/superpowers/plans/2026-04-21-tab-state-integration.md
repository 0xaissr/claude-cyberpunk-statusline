# iTerm2 Tab-State Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 claude-cli 的 iTerm2 tab 底色切換整份搬進 cyberpunk-statusline，讓顏色跟 theme palette 綁定，使用者能在 configure wizard 裡挑每個 state（running/waiting/idle/error）要用的 palette 名。

**Architecture:** 新增 `tab-state.sh`（runtime script，每次 hook 觸發時讀 config.json + theme JSON 解析 palette → hex → RGB → iTerm2 escape sequence）、`_lib_tab_state.sh`（install/remove hooks 共用 helpers）；`configure.sh` 新增 Step 8 讓使用者開關與自訂 palette 映射。`uninstall.sh` 對稱呼叫 lib 的 teardown。

**Tech Stack:** Bash 3.2+（macOS 預設）、jq、iTerm2 OSC escape sequences（`\e]6;1;bg;...;brightness;N\a`、`\e]1337;RequestAttention=yes\a`）。

**Spec:** `docs/superpowers/specs/2026-04-21-tab-state-integration-design.md`

---

## File Structure

**Create:**
- `tab-state.sh` — runtime script，接受 `running|waiting|idle|error|clear`，輸出 iTerm2 escape sequence
- `_lib_tab_state.sh` — helper 函式（`_install_tab_state_hooks` / `_remove_tab_state_hooks` / `_detect_foreign_tab_state_hooks`）
- `tests/test-tab-state.sh` — tab-state.sh 單元測試
- `tests/test-lib-tab-state.sh` — lib helper 單元測試
- `tests/fixtures/tab-state/` — 測試用 fixture（config.json + themes/）

**Modify:**
- `configure.sh` — `TOTAL_STEPS` 7→8；新增 `step_tab_state`；`step_done` 寫 `tab_state` 欄位並呼叫 install/remove；main dispatch 加 step 8
- `uninstall.sh` — source lib 後偵測並 teardown
- `README.md` / `docs/README.zh-TW.md` — 新增「iTerm2 tab tinting」章節
- `LOG.md` — changelog 條目

---

## Task 1: Create empty `tab-state.sh` + failing smoke test

**Files:**
- Create: `tab-state.sh`
- Create: `tests/test-tab-state.sh`

- [ ] **Step 1: Write failing smoke test**

Create `tests/test-tab-state.sh`:

```bash
#!/usr/bin/env bash
# tab-state.sh unit tests
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TAB_STATE="$PROJECT_DIR/tab-state.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s: %s\n' "$1" "$2" >&2; }

test_exists() {
  echo "▸ test_exists"
  if [ -x "$TAB_STATE" ]; then
    pass "tab-state.sh exists and is executable"
  else
    fail "tab-state.sh" "not found or not executable"
  fi
}

test_exists

echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "FAIL: $FAIL test(s) failed"
  exit 1
fi
echo "PASS: $PASS test(s)"
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
chmod +x tests/test-tab-state.sh
bash tests/test-tab-state.sh
```
Expected: `✗ tab-state.sh: not found or not executable` + exit 1.

- [ ] **Step 3: Create empty executable `tab-state.sh`**

```bash
cat > tab-state.sh <<'EOF'
#!/usr/bin/env bash
# Claude Code session state → iTerm2 tab background
exit 0
EOF
chmod +x tab-state.sh
```

- [ ] **Step 4: Run test to confirm it passes**

```bash
bash tests/test-tab-state.sh
```
Expected: `✓ tab-state.sh exists and is executable` + `PASS: 1 test(s)`.

- [ ] **Step 5: Commit**

```bash
git add tab-state.sh tests/test-tab-state.sh
git commit -m "test(tab-state): 新增 tab-state.sh 骨架與第一支煙霧測試"
```

---

## Task 2: Non-iTerm2 silent exit + invalid state error

**Files:**
- Modify: `tab-state.sh`
- Modify: `tests/test-tab-state.sh`

- [ ] **Step 1: Add tests for non-iTerm2 and invalid state**

Append to `tests/test-tab-state.sh` (before the summary block):

```bash
run_state() {
  local state="$1" term="${2:-iTerm.app}"
  TAB_STATE_OUT=/dev/stdout TERM_PROGRAM="$term" \
    CYBERPUNK_STATUSLINE_REPO_DIR="$SCRIPT_DIR/fixtures/tab-state" \
    bash "$TAB_STATE" "$state" 2>&1
}

test_non_iterm_silent() {
  echo "▸ test_non_iterm_silent"
  local out; out=$(run_state running Apple_Terminal)
  if [ -z "$out" ]; then
    pass "non-iTerm2 produces no output"
  else
    fail "non-iTerm2" "expected empty, got: $(printf '%q' "$out")"
  fi
}

test_invalid_state() {
  echo "▸ test_invalid_state"
  TAB_STATE_OUT=/dev/stdout TERM_PROGRAM=iTerm.app bash "$TAB_STATE" bogus >/dev/null 2>&1
  if [ "$?" -ne 0 ]; then
    pass "invalid state exits nonzero"
  else
    fail "invalid state" "expected nonzero exit, got 0"
  fi
}

test_non_iterm_silent
test_invalid_state
```

- [ ] **Step 2: Run tests, confirm two new ones fail**

```bash
bash tests/test-tab-state.sh
```
Expected: `test_non_iterm_silent` passes (empty output), `test_invalid_state` fails (current stub returns 0).

- [ ] **Step 3: Replace `tab-state.sh` with state dispatcher**

```bash
cat > tab-state.sh <<'EOF'
#!/usr/bin/env bash
# Claude Code session state → iTerm2 tab background
# Usage: tab-state.sh {running|waiting|idle|error|clear}

[[ "$TERM_PROGRAM" != "iTerm.app" ]] && exit 0

state="${1-}"
case "$state" in
  running|waiting|idle|error|clear)
    exit 0
    ;;
  *)
    echo "usage: $0 {running|waiting|idle|error|clear}" >&2
    exit 1
    ;;
esac
EOF
```

- [ ] **Step 4: Run tests, confirm all pass**

```bash
bash tests/test-tab-state.sh
```
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add tab-state.sh tests/test-tab-state.sh
git commit -m "feat(tab-state): 加入 state 分派、非 iTerm2 靜默與無效參數錯誤"
```

---

## Task 3: Symlink-safe path resolution + config/enabled gating

**Files:**
- Modify: `tab-state.sh`
- Modify: `tests/test-tab-state.sh`
- Create: `tests/fixtures/tab-state/config.json`
- Create: `tests/fixtures/tab-state/themes/test-theme.json`

- [ ] **Step 1: Create fixture files**

```bash
mkdir -p tests/fixtures/tab-state/themes

cat > tests/fixtures/tab-state/config.json <<'EOF'
{
  "theme": "test-theme",
  "tab_state": {
    "enabled": true,
    "running": "accent_1",
    "waiting": "warning",
    "idle": "accent_3",
    "error": "alert"
  }
}
EOF

cat > tests/fixtures/tab-state/themes/test-theme.json <<'EOF'
{
  "colors": {
    "accent_1": "#28783C",
    "accent_2": "#FF2DD1",
    "accent_3": "#285C8C",
    "warning":  "#C89600",
    "alert":    "#A02828",
    "dim":      "#666666",
    "bg_primary": "#0A0E1A",
    "bg_panel":   "#141824"
  }
}
EOF
```

- [ ] **Step 2: Add enabled-gating test**

Append to `tests/test-tab-state.sh` (before summary):

```bash
test_disabled_silent() {
  echo "▸ test_disabled_silent"
  local tmpdir; tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/themes"
  cat > "$tmpdir/config.json" <<JSON
{"theme":"test-theme","tab_state":{"enabled":false,"running":"accent_1"}}
JSON
  cp "$SCRIPT_DIR/fixtures/tab-state/themes/test-theme.json" "$tmpdir/themes/"
  local out
  out=$(TAB_STATE_OUT=/dev/stdout TERM_PROGRAM=iTerm.app \
    CYBERPUNK_STATUSLINE_REPO_DIR="$tmpdir" bash "$TAB_STATE" running 2>&1)
  rm -rf "$tmpdir"
  if [ -z "$out" ]; then
    pass "enabled=false produces no output"
  else
    fail "enabled=false" "expected empty, got: $(printf '%q' "$out")"
  fi
}

test_missing_config_silent() {
  echo "▸ test_missing_config_silent"
  local tmpdir; tmpdir=$(mktemp -d)
  local out
  out=$(TAB_STATE_OUT=/dev/stdout TERM_PROGRAM=iTerm.app \
    CYBERPUNK_STATUSLINE_REPO_DIR="$tmpdir" bash "$TAB_STATE" running 2>&1)
  rm -rf "$tmpdir"
  if [ -z "$out" ]; then
    pass "missing config produces no output"
  else
    fail "missing config" "expected empty, got: $(printf '%q' "$out")"
  fi
}

test_disabled_silent
test_missing_config_silent
```

- [ ] **Step 3: Run tests, confirm new ones fail**

```bash
bash tests/test-tab-state.sh
```
Expected: both fail — stub script currently ignores config.

- [ ] **Step 4: Replace `tab-state.sh` with symlink-safe resolve + config loader**

```bash
cat > tab-state.sh <<'EOF'
#!/usr/bin/env bash
# Claude Code session state → iTerm2 tab background
# Usage: tab-state.sh {running|waiting|idle|error|clear}

[[ "$TERM_PROGRAM" != "iTerm.app" ]] && exit 0

# Resolve symlink chain back to repo root (portable: no GNU readlink -f)
SCRIPT_SRC="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SRC" ]; do
  _DIR="$(cd -P "$(dirname "$SCRIPT_SRC")" && pwd)"
  SCRIPT_SRC="$(readlink "$SCRIPT_SRC")"
  [[ "$SCRIPT_SRC" != /* ]] && SCRIPT_SRC="$_DIR/$SCRIPT_SRC"
done
REPO_DIR="${CYBERPUNK_STATUSLINE_REPO_DIR:-$(cd -P "$(dirname "$SCRIPT_SRC")" && pwd)}"
CONFIG="$REPO_DIR/config.json"
JQ=$(command -v jq 2>/dev/null || echo /opt/homebrew/bin/jq)

: "${TAB_STATE_OUT:=/dev/tty}"
[[ -w "$TAB_STATE_OUT" ]] || exit 0

state="${1-}"
case "$state" in
  running|waiting|idle|error)
    [[ -f "$CONFIG" ]] || exit 0
    enabled=$("$JQ" -r '.tab_state.enabled // false' "$CONFIG" 2>/dev/null)
    [[ "$enabled" != "true" ]] && exit 0
    ;;
  clear)
    : # handled later
    ;;
  *)
    echo "usage: $0 {running|waiting|idle|error|clear}" >&2
    exit 1
    ;;
esac
EOF
```

- [ ] **Step 5: Run tests, confirm all pass**

```bash
bash tests/test-tab-state.sh
```
Expected: 5 tests pass (all current + 2 new).

- [ ] **Step 6: Commit**

```bash
git add tab-state.sh tests/test-tab-state.sh tests/fixtures/tab-state/
git commit -m "feat(tab-state): 加入 symlink-safe repo 解析與 enabled 閘門"
```

---

## Task 4: Palette → hex → RGB → escape sequence emission

**Files:**
- Modify: `tab-state.sh`
- Modify: `tests/test-tab-state.sh`

- [ ] **Step 1: Add RGB emission test**

Append to `tests/test-tab-state.sh` (before summary):

```bash
assert_contains() {
  local output="$1" expected="$2" name="$3"
  if [[ "$output" == *"$expected"* ]]; then
    pass "$name"
  else
    fail "$name" "missing literal: $(printf '%q' "$expected")"
  fi
}

test_running_emits_rgb() {
  echo "▸ test_running_emits_rgb"
  local out; out=$(run_state running)
  # accent_1 = #28783C → (40, 120, 60)
  assert_contains "$out" $'\e]6;1;bg;red;brightness;40\a'   "running: red=40"
  assert_contains "$out" $'\e]6;1;bg;green;brightness;120\a' "running: green=120"
  assert_contains "$out" $'\e]6;1;bg;blue;brightness;60\a'  "running: blue=60"
}

test_error_emits_rgb() {
  echo "▸ test_error_emits_rgb"
  local out; out=$(run_state error)
  # alert = #A02828 → (160, 40, 40)
  assert_contains "$out" $'\e]6;1;bg;red;brightness;160\a'  "error: red=160"
  assert_contains "$out" $'\e]6;1;bg;green;brightness;40\a' "error: green=40"
  assert_contains "$out" $'\e]6;1;bg;blue;brightness;40\a'  "error: blue=40"
}

test_running_emits_rgb
test_error_emits_rgb
```

- [ ] **Step 2: Run tests, confirm new ones fail**

```bash
bash tests/test-tab-state.sh
```
Expected: `test_running_emits_rgb` / `test_error_emits_rgb` fail — no escape sequences emitted yet.

- [ ] **Step 3: Extend `tab-state.sh` to resolve palette and emit RGB**

Replace the `running|waiting|idle|error)` branch body with the full resolve+emit logic. Final full content of `tab-state.sh`:

```bash
#!/usr/bin/env bash
# Claude Code session state → iTerm2 tab background
# Usage: tab-state.sh {running|waiting|idle|error|clear}

[[ "$TERM_PROGRAM" != "iTerm.app" ]] && exit 0

SCRIPT_SRC="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SRC" ]; do
  _DIR="$(cd -P "$(dirname "$SCRIPT_SRC")" && pwd)"
  SCRIPT_SRC="$(readlink "$SCRIPT_SRC")"
  [[ "$SCRIPT_SRC" != /* ]] && SCRIPT_SRC="$_DIR/$SCRIPT_SRC"
done
REPO_DIR="${CYBERPUNK_STATUSLINE_REPO_DIR:-$(cd -P "$(dirname "$SCRIPT_SRC")" && pwd)}"
CONFIG="$REPO_DIR/config.json"
JQ=$(command -v jq 2>/dev/null || echo /opt/homebrew/bin/jq)

declare -A DEFAULTS=(
  [running]=accent_1 [waiting]=warning [idle]=accent_3 [error]=alert
)

: "${TAB_STATE_OUT:=/dev/tty}"
[[ -w "$TAB_STATE_OUT" ]] || exit 0

state="${1-}"
case "$state" in
  running|waiting|idle|error)
    [[ -f "$CONFIG" ]] || exit 0
    enabled=$("$JQ" -r '.tab_state.enabled // false' "$CONFIG" 2>/dev/null)
    [[ "$enabled" != "true" ]] && exit 0

    palette=$("$JQ" -r --arg s "$state" '.tab_state[$s] // empty' "$CONFIG" 2>/dev/null)
    palette="${palette:-${DEFAULTS[$state]}}"
    theme=$("$JQ" -r '.theme // "terminal-glitch"' "$CONFIG" 2>/dev/null)
    theme_file="$REPO_DIR/themes/$theme.json"
    [[ -f "$theme_file" ]] || exit 0
    hex=$("$JQ" -r --arg k "$palette" '.colors[$k] // empty' "$theme_file" 2>/dev/null)
    [[ -z "$hex" || "${hex:0:1}" != "#" || "${#hex}" -ne 7 ]] && exit 0

    r=$((16#${hex:1:2}))
    g=$((16#${hex:3:2}))
    b=$((16#${hex:5:2}))
    printf '\e]6;1;bg;red;brightness;%d\a'   "$r" > "$TAB_STATE_OUT"
    printf '\e]6;1;bg;green;brightness;%d\a' "$g" > "$TAB_STATE_OUT"
    printf '\e]6;1;bg;blue;brightness;%d\a'  "$b" > "$TAB_STATE_OUT"
    ;;
  clear)
    : # handled in next task
    ;;
  *)
    echo "usage: $0 {running|waiting|idle|error|clear}" >&2
    exit 1
    ;;
esac
```

- [ ] **Step 4: Run tests, confirm all pass**

```bash
bash tests/test-tab-state.sh
```
Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add tab-state.sh tests/test-tab-state.sh
git commit -m "feat(tab-state): 解析 palette → hex → RGB 並輸出 iTerm2 escape sequence"
```

---

## Task 5: `waiting` RequestAttention + `clear` reset

**Files:**
- Modify: `tab-state.sh`
- Modify: `tests/test-tab-state.sh`

- [ ] **Step 1: Add tests for waiting attention and clear reset**

Append to `tests/test-tab-state.sh`:

```bash
test_waiting_emits_attention() {
  echo "▸ test_waiting_emits_attention"
  local out; out=$(run_state waiting)
  assert_contains "$out" $'\e]1337;RequestAttention=yes\a' "waiting: RequestAttention"
}

test_clear_resets() {
  echo "▸ test_clear_resets"
  local out; out=$(run_state clear)
  assert_contains "$out" $'\e]6;1;bg;*;default\a' "clear: reset"
}

test_waiting_emits_attention
test_clear_resets
```

- [ ] **Step 2: Run tests, confirm new ones fail**

```bash
bash tests/test-tab-state.sh
```
Expected: both new tests fail.

- [ ] **Step 3: Add RequestAttention and clear emit in `tab-state.sh`**

In the state loop, **after the last `printf '\e]6;1;bg;blue...'` line** (inside `running|waiting|idle|error)` branch), add:

```bash
    [[ "$state" == "waiting" ]] && printf '\e]1337;RequestAttention=yes\a' > "$TAB_STATE_OUT"
```

Replace the `clear)` branch body:

```bash
  clear)
    printf '\e]6;1;bg;*;default\a' > "$TAB_STATE_OUT"
    ;;
```

- [ ] **Step 4: Run tests, confirm all pass**

```bash
bash tests/test-tab-state.sh
```
Expected: 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add tab-state.sh tests/test-tab-state.sh
git commit -m "feat(tab-state): waiting 呼叫 RequestAttention、clear 重設底色"
```

---

## Task 6: Missing state key falls back to DEFAULTS + theme switch awareness

**Files:**
- Modify: `tests/test-tab-state.sh`
- (no code change needed; DEFAULTS already in script from Task 4)

- [ ] **Step 1: Add fallback and theme-switch tests**

Append to `tests/test-tab-state.sh`:

```bash
test_missing_state_uses_default() {
  echo "▸ test_missing_state_uses_default"
  local tmpdir; tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/themes"
  # tab_state enabled but no 'running' key → should fall back to DEFAULTS[running]=accent_1
  cat > "$tmpdir/config.json" <<JSON
{"theme":"test-theme","tab_state":{"enabled":true}}
JSON
  cp "$SCRIPT_DIR/fixtures/tab-state/themes/test-theme.json" "$tmpdir/themes/"
  local out
  out=$(TAB_STATE_OUT=/dev/stdout TERM_PROGRAM=iTerm.app \
    CYBERPUNK_STATUSLINE_REPO_DIR="$tmpdir" bash "$TAB_STATE" running 2>&1)
  rm -rf "$tmpdir"
  # accent_1 = #28783C → (40, 120, 60)
  assert_contains "$out" $'\e]6;1;bg;red;brightness;40\a' "fallback: running uses accent_1"
}

test_theme_switch_changes_rgb() {
  echo "▸ test_theme_switch_changes_rgb"
  local tmpdir; tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/themes"
  cat > "$tmpdir/config.json" <<JSON
{"theme":"alt-theme","tab_state":{"enabled":true,"running":"accent_1"}}
JSON
  # alt theme: accent_1 = #112233 → (17, 34, 51)
  cat > "$tmpdir/themes/alt-theme.json" <<'JSON'
{"colors":{"accent_1":"#112233"}}
JSON
  local out
  out=$(TAB_STATE_OUT=/dev/stdout TERM_PROGRAM=iTerm.app \
    CYBERPUNK_STATUSLINE_REPO_DIR="$tmpdir" bash "$TAB_STATE" running 2>&1)
  rm -rf "$tmpdir"
  assert_contains "$out" $'\e]6;1;bg;red;brightness;17\a'  "theme switch: red=17"
  assert_contains "$out" $'\e]6;1;bg;green;brightness;34\a' "theme switch: green=34"
  assert_contains "$out" $'\e]6;1;bg;blue;brightness;51\a' "theme switch: blue=51"
}

test_palette_typo_silent() {
  echo "▸ test_palette_typo_silent"
  local tmpdir; tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/themes"
  cat > "$tmpdir/config.json" <<JSON
{"theme":"test-theme","tab_state":{"enabled":true,"running":"nonexistent"}}
JSON
  cp "$SCRIPT_DIR/fixtures/tab-state/themes/test-theme.json" "$tmpdir/themes/"
  local out
  out=$(TAB_STATE_OUT=/dev/stdout TERM_PROGRAM=iTerm.app \
    CYBERPUNK_STATUSLINE_REPO_DIR="$tmpdir" bash "$TAB_STATE" running 2>&1)
  rm -rf "$tmpdir"
  if [ -z "$out" ]; then
    pass "typo palette name: no output"
  else
    fail "typo palette" "expected empty, got: $(printf '%q' "$out")"
  fi
}

test_missing_state_uses_default
test_theme_switch_changes_rgb
test_palette_typo_silent
```

- [ ] **Step 2: Run tests, confirm all pass**

```bash
bash tests/test-tab-state.sh
```
Expected: 12 tests pass. If `test_missing_state_uses_default` fails, verify `DEFAULTS` dictionary is populated in script (Task 4 Step 3).

- [ ] **Step 3: Commit**

```bash
git add tests/test-tab-state.sh
git commit -m "test(tab-state): 驗證 DEFAULTS fallback、theme 切換與 palette typo 靜默"
```

---

## Task 7: `_lib_tab_state.sh` — `_install_tab_state_hooks`

**Files:**
- Create: `_lib_tab_state.sh`
- Create: `tests/test-lib-tab-state.sh`

- [ ] **Step 1: Create test file with first install test**

Create `tests/test-lib-tab-state.sh`:

```bash
#!/usr/bin/env bash
# _lib_tab_state.sh unit tests
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LIB="$PROJECT_DIR/_lib_tab_state.sh"
JQ=$(command -v jq)

PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s: %s\n' "$1" "$2" >&2; }

# Each test creates its own tmpdir with settings.json + scripts/
setup_env() {
  local d; d=$(mktemp -d)
  export CLAUDE_SETTINGS_OVERRIDE="$d/settings.json"
  export CLAUDE_SCRIPTS_DIR_OVERRIDE="$d/scripts"
  echo '{}' > "$CLAUDE_SETTINGS_OVERRIDE"
  echo "$d"
}

test_install_merges_six_hooks() {
  echo "▸ test_install_merges_six_hooks"
  local d; d=$(setup_env)
  source "$LIB"
  _install_tab_state_hooks "$PROJECT_DIR"
  local rc=$?
  if [ "$rc" -ne 0 ]; then fail "install rc" "expected 0, got $rc"; rm -rf "$d"; return; fi
  for ev in SessionStart UserPromptSubmit PreToolUse Notification Stop SessionEnd; do
    if "$JQ" -e --arg ev "$ev" '.hooks[$ev] | length > 0' "$CLAUDE_SETTINGS_OVERRIDE" >/dev/null; then
      pass "$ev hook installed"
    else
      fail "$ev" "hook missing after install"
    fi
  done
  rm -rf "$d"
}

test_install_preserves_existing_hooks() {
  echo "▸ test_install_preserves_existing_hooks"
  local d; d=$(setup_env)
  cat > "$CLAUDE_SETTINGS_OVERRIDE" <<'JSON'
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo userA"}]}]}}
JSON
  source "$LIB"
  _install_tab_state_hooks "$PROJECT_DIR"
  local count; count=$("$JQ" '.hooks.Stop | length' "$CLAUDE_SETTINGS_OVERRIDE")
  if [ "$count" = "2" ]; then
    pass "existing Stop hook preserved, ours appended"
  else
    fail "Stop hook count" "expected 2, got $count"
  fi
  rm -rf "$d"
}

test_install_creates_symlink() {
  echo "▸ test_install_creates_symlink"
  local d; d=$(setup_env)
  source "$LIB"
  _install_tab_state_hooks "$PROJECT_DIR"
  if [ -L "$CLAUDE_SCRIPTS_DIR_OVERRIDE/tab-state.sh" ]; then
    pass "symlink created"
  else
    fail "symlink" "not created at $CLAUDE_SCRIPTS_DIR_OVERRIDE/tab-state.sh"
  fi
  rm -rf "$d"
}

test_install_merges_six_hooks
test_install_preserves_existing_hooks
test_install_creates_symlink

echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "FAIL: $FAIL test(s)"
  exit 1
fi
echo "PASS: $PASS test(s)"
```

- [ ] **Step 2: Run tests, confirm they fail**

```bash
chmod +x tests/test-lib-tab-state.sh
bash tests/test-lib-tab-state.sh
```
Expected: fail because `_lib_tab_state.sh` does not exist.

- [ ] **Step 3: Create `_lib_tab_state.sh` with `_install_tab_state_hooks`**

```bash
cat > _lib_tab_state.sh <<'EOF'
#!/usr/bin/env bash
# Shared helpers for managing iTerm2 tab-state hooks in ~/.claude/settings.json.
# Meant to be sourced by configure.sh and uninstall.sh.

_tab_state_settings_path() {
  echo "${CLAUDE_SETTINGS_OVERRIDE:-$HOME/.claude/settings.json}"
}

_tab_state_scripts_dir() {
  echo "${CLAUDE_SCRIPTS_DIR_OVERRIDE:-$HOME/.claude/scripts}"
}

_install_tab_state_hooks() {
  local repo_dir="$1"
  local settings; settings=$(_tab_state_settings_path)
  local scripts_dir; scripts_dir=$(_tab_state_scripts_dir)
  local jq_bin; jq_bin=$(command -v jq) || return 1

  mkdir -p "$scripts_dir" || return 1
  ln -sfn "$repo_dir/tab-state.sh" "$scripts_dir/tab-state.sh" || return 1

  if [ -f "$settings" ]; then
    cp "$settings" "$settings.bak.$(date +%Y%m%d-%H%M%S)" || return 1
  else
    mkdir -p "$(dirname "$settings")"
    echo '{}' > "$settings"
  fi

  local hook_cmd_prefix="$scripts_dir/tab-state.sh"
  local new_hooks; new_hooks=$(cat <<JSON
{
  "hooks": {
    "SessionStart":     [{"hooks": [{"type": "command", "command": "$hook_cmd_prefix idle"}]}],
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "$hook_cmd_prefix running"}]}],
    "PreToolUse":       [{"matcher": "*", "hooks": [{"type": "command", "command": "$hook_cmd_prefix running"}]}],
    "Notification":     [{"hooks": [{"type": "command", "command": "$hook_cmd_prefix waiting"}]}],
    "Stop":             [{"hooks": [{"type": "command", "command": "$hook_cmd_prefix idle"}]}],
    "SessionEnd":       [{"hooks": [{"type": "command", "command": "$hook_cmd_prefix clear"}]}]
  }
}
JSON
)

  local tmp; tmp=$(mktemp)
  "$jq_bin" -s '
    .[0] as $orig | .[1] as $new |
    $orig | .hooks = (
      ($orig.hooks // {}) as $old_hooks |
      reduce ($new.hooks | keys[]) as $event (
        $old_hooks;
        .[$event] = ((.[$event] // []) + $new.hooks[$event])
      )
    )
  ' "$settings" <(echo "$new_hooks") > "$tmp" || { rm -f "$tmp"; return 1; }

  "$jq_bin" empty "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$settings"
}
EOF
```

- [ ] **Step 4: Run tests, confirm all pass**

```bash
bash tests/test-lib-tab-state.sh
```
Expected: 8 pass, 0 fail (6 hook-installed + 1 preserve + 1 symlink).

- [ ] **Step 5: Commit**

```bash
git add _lib_tab_state.sh tests/test-lib-tab-state.sh
git commit -m "feat(lib): 新增 _install_tab_state_hooks 含 backup、symlink 與 hooks merge"
```

---

## Task 8: `_remove_tab_state_hooks`

**Files:**
- Modify: `_lib_tab_state.sh`
- Modify: `tests/test-lib-tab-state.sh`

- [ ] **Step 1: Add removal tests**

Append to `tests/test-lib-tab-state.sh` (before summary):

```bash
test_remove_clears_our_hooks() {
  echo "▸ test_remove_clears_our_hooks"
  local d; d=$(setup_env)
  source "$LIB"
  _install_tab_state_hooks "$PROJECT_DIR"
  _remove_tab_state_hooks
  local total
  total=$("$JQ" '[.hooks // {} | to_entries[] | .value[] | .hooks[]? | .command | select(contains("tab-state.sh"))] | length' "$CLAUDE_SETTINGS_OVERRIDE")
  if [ "$total" = "0" ]; then
    pass "no tab-state commands remain"
  else
    fail "remove" "still $total tab-state hook(s) present"
  fi
  if [ ! -L "$CLAUDE_SCRIPTS_DIR_OVERRIDE/tab-state.sh" ]; then
    pass "symlink removed"
  else
    fail "symlink" "still present after remove"
  fi
  rm -rf "$d"
}

test_remove_preserves_other_user_hooks() {
  echo "▸ test_remove_preserves_other_user_hooks"
  local d; d=$(setup_env)
  cat > "$CLAUDE_SETTINGS_OVERRIDE" <<'JSON'
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo userA"}]}]}}
JSON
  source "$LIB"
  _install_tab_state_hooks "$PROJECT_DIR"
  _remove_tab_state_hooks
  local count; count=$("$JQ" '.hooks.Stop | length' "$CLAUDE_SETTINGS_OVERRIDE")
  if [ "$count" = "1" ]; then
    pass "user's Stop hook still there"
  else
    fail "remove preserve" "expected 1 Stop hook, got $count"
  fi
  local cmd; cmd=$("$JQ" -r '.hooks.Stop[0].hooks[0].command' "$CLAUDE_SETTINGS_OVERRIDE")
  if [ "$cmd" = "echo userA" ]; then
    pass "user's command untouched"
  else
    fail "remove preserve" "wrong command: $cmd"
  fi
  rm -rf "$d"
}

test_remove_empty_settings_safe() {
  echo "▸ test_remove_empty_settings_safe"
  local d; d=$(setup_env)
  source "$LIB"
  _remove_tab_state_hooks
  local rc=$?
  if [ "$rc" = "0" ]; then
    pass "remove on empty settings is no-op"
  else
    fail "remove empty" "exited nonzero: $rc"
  fi
  rm -rf "$d"
}

test_remove_clears_our_hooks
test_remove_preserves_other_user_hooks
test_remove_empty_settings_safe
```

- [ ] **Step 2: Run tests, confirm new ones fail**

```bash
bash tests/test-lib-tab-state.sh
```
Expected: 3 new tests fail (`_remove_tab_state_hooks` undefined).

- [ ] **Step 3: Append `_remove_tab_state_hooks` to `_lib_tab_state.sh`**

Append to `_lib_tab_state.sh`:

```bash

_remove_tab_state_hooks() {
  local settings; settings=$(_tab_state_settings_path)
  local scripts_dir; scripts_dir=$(_tab_state_scripts_dir)
  local jq_bin; jq_bin=$(command -v jq) || return 1

  if [ -f "$settings" ]; then
    cp "$settings" "$settings.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    local tmp; tmp=$(mktemp)
    "$jq_bin" '
      if (.hooks // null) == null then .
      else
        .hooks = (
          .hooks | to_entries | map(
            .value = (
              .value | map(
                .hooks = (.hooks | map(select((.command // "") | contains("tab-state.sh") | not)))
              ) | map(select((.hooks | length) > 0))
            )
          ) | map(select((.value | length) > 0)) | from_entries
        )
      end
    ' "$settings" > "$tmp" || { rm -f "$tmp"; return 1; }

    "$jq_bin" empty "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$settings"
  fi

  rm -f "$scripts_dir/tab-state.sh"
  rmdir "$scripts_dir" 2>/dev/null || true
  return 0
}
```

- [ ] **Step 4: Run tests, confirm all pass**

```bash
bash tests/test-lib-tab-state.sh
```
Expected: 12 pass total.

- [ ] **Step 5: Commit**

```bash
git add _lib_tab_state.sh tests/test-lib-tab-state.sh
git commit -m "feat(lib): 新增 _remove_tab_state_hooks 只移除含 tab-state.sh 的 hooks"
```

---

## Task 9: `_detect_foreign_tab_state_hooks`

**Files:**
- Modify: `_lib_tab_state.sh`
- Modify: `tests/test-lib-tab-state.sh`

- [ ] **Step 1: Add detection test**

Append to `tests/test-lib-tab-state.sh`:

```bash
test_detect_foreign_finds_claude_cli() {
  echo "▸ test_detect_foreign_finds_claude_cli"
  local d; d=$(setup_env)
  # Simulate an existing claude-cli install: a hook pointing at /some/other/tab-state.sh
  cat > "$CLAUDE_SETTINGS_OVERRIDE" <<'JSON'
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/other/path/tab-state.sh idle"}]}]}}
JSON
  source "$LIB"
  local our_path="$CLAUDE_SCRIPTS_DIR_OVERRIDE/tab-state.sh"
  local found; found=$(_detect_foreign_tab_state_hooks "$our_path")
  if [[ "$found" == *"/other/path/tab-state.sh"* ]]; then
    pass "foreign hook detected"
  else
    fail "detect foreign" "expected /other/path, got: $found"
  fi
  rm -rf "$d"
}

test_detect_foreign_ignores_own() {
  echo "▸ test_detect_foreign_ignores_own"
  local d; d=$(setup_env)
  source "$LIB"
  _install_tab_state_hooks "$PROJECT_DIR"
  local our_path="$CLAUDE_SCRIPTS_DIR_OVERRIDE/tab-state.sh"
  local found; found=$(_detect_foreign_tab_state_hooks "$our_path")
  if [ -z "$found" ]; then
    pass "own hooks not flagged as foreign"
  else
    fail "detect foreign" "falsely detected: $found"
  fi
  rm -rf "$d"
}

test_detect_foreign_finds_claude_cli
test_detect_foreign_ignores_own
```

- [ ] **Step 2: Run tests, confirm new ones fail**

```bash
bash tests/test-lib-tab-state.sh
```
Expected: 2 new tests fail.

- [ ] **Step 3: Append `_detect_foreign_tab_state_hooks` to `_lib_tab_state.sh`**

```bash

_detect_foreign_tab_state_hooks() {
  local self_path="$1"
  local settings; settings=$(_tab_state_settings_path)
  local jq_bin; jq_bin=$(command -v jq) || return 1
  [ -f "$settings" ] || return 0

  "$jq_bin" -r --arg self "$self_path" '
    [ .hooks // {} | to_entries[] | .value[]? | .hooks[]?
      | (.command // "")
      | select(contains("tab-state.sh"))
      | select(contains($self) | not)
    ] | unique | .[]
  ' "$settings" 2>/dev/null
}
```

- [ ] **Step 4: Run tests, confirm all pass**

```bash
bash tests/test-lib-tab-state.sh
```
Expected: 14 pass total.

- [ ] **Step 5: Commit**

```bash
git add _lib_tab_state.sh tests/test-lib-tab-state.sh
git commit -m "feat(lib): 新增 _detect_foreign_tab_state_hooks 偵測外部 tab-state.sh"
```

---

## Task 10: `configure.sh` — `step_tab_state` (Step 8.1 Enable/Skip + non-iTerm2 auto-skip)

**Files:**
- Modify: `configure.sh`

- [ ] **Step 1: Source the lib near the top of `configure.sh`**

Find the line that resolves `SCRIPT_DIR` near the top (around line 8–15). After `TOTAL_STEPS=7` (line 16), change it to `TOTAL_STEPS=8` and add lib source.

Use an Edit:

```
OLD:
TOTAL_STEPS=7

NEW:
TOTAL_STEPS=8

# Load tab-state helpers (install/remove hooks)
source "$SCRIPT_DIR/_lib_tab_state.sh"
```

(Exact `SCRIPT_DIR` variable name may differ — confirm with `grep -n 'SCRIPT_DIR=' configure.sh | head -3` and use the correct one.)

- [ ] **Step 2: Add `step_tab_state` function**

Insert after the last existing step function (search for the blank line before `step_done()` and add before it):

```bash
# ── Step 8: iTerm2 tab tinting ───────────────────────────────────────────
step_tab_state() {
  draw_header 8 $TOTAL_STEPS "iTerm2 tab tinting"

  # Non-iTerm2 → auto-skip
  if [ "${TERM_PROGRAM:-}" != "iTerm.app" ]; then
    printf '\n  \033[2mDetected terminal: %s. Tab tinting is iTerm2-only — skipping.\033[0m\n\n' \
      "${TERM_PROGRAM:-unknown}"
    sel_tab_state_enabled="false"
    sel_tab_state_running="accent_1"
    sel_tab_state_waiting="warning"
    sel_tab_state_idle="accent_3"
    sel_tab_state_error="alert"
    printf '  \033[2mPress any key to continue...\033[0m'
    read -rsn1
    return 0
  fi

  # Foreign hook detection warning
  local foreign
  foreign=$(_detect_foreign_tab_state_hooks "$HOME/.claude/scripts/tab-state.sh" 2>/dev/null)
  if [ -n "$foreign" ]; then
    printf '\n  \033[33m⚠ Existing tab-state hooks detected:\033[0m\n'
    printf '%s\n' "$foreign" | sed 's/^/    /'
    printf '  \033[2mEnabling will append our hooks — recommend removing the other first.\033[0m\n\n'
  fi

  ask_choice \
    "Enable|Claude Code hooks will tint your iTerm2 tab background per session state." \
    "Skip (default)|Leave ~/.claude/settings.json unchanged."

  local rc=$?
  if [ $rc -eq 1 ]; then return 2; fi

  if [ "$CHOICE_RESULT" = "2" ]; then
    sel_tab_state_enabled="false"
    sel_tab_state_running="accent_1"
    sel_tab_state_waiting="warning"
    sel_tab_state_idle="accent_3"
    sel_tab_state_error="alert"
    return 0
  fi

  sel_tab_state_enabled="true"
  # per-state palette picker filled in Task 11
  sel_tab_state_running="accent_1"
  sel_tab_state_waiting="warning"
  sel_tab_state_idle="accent_3"
  sel_tab_state_error="alert"
  return 0
}
```

- [ ] **Step 3: Update test-configure.sh assertion list**

Find the `test_step_functions` array in `tests/test-configure.sh`:

```
OLD:
  for fn in step_symbols step_theme step_blocks step_spacing step_separator step_done; do

NEW:
  for fn in step_symbols step_theme step_blocks step_spacing step_separator step_tab_state step_done; do
```

- [ ] **Step 4: Run configure test, confirm it passes**

```bash
bash tests/test-configure.sh
```
Expected: `step_tab_state exists` passes alongside others.

- [ ] **Step 5: Commit**

```bash
git add configure.sh tests/test-configure.sh
git commit -m "feat(configure): 新增 step_tab_state (Enable/Skip + non-iTerm2 auto-skip)"
```

---

## Task 11: `configure.sh` — per-state palette picker with swatches

**Files:**
- Modify: `configure.sh`

- [ ] **Step 1: Extend `step_tab_state` with 4 palette sub-selections**

Replace the `sel_tab_state_enabled="true"` block (the bottom part of `step_tab_state` that currently hard-codes palette names) with the picker loop:

```bash
  sel_tab_state_enabled="true"

  # Theme palette we allow for tab tinting (exclude bg_primary/bg_panel)
  local palettes=(accent_1 accent_2 accent_3 warning alert dim)

  # Read current theme's color hex values for swatch display
  local theme_file="$SCRIPT_DIR/themes/${sel_theme}.json"
  local -A hex_of=()
  for p in "${palettes[@]}"; do
    hex_of[$p]=$("$JQ" -r --arg k "$p" '.colors[$k] // ""' "$theme_file")
  done

  _tab_state_ask_palette() {
    local state_label="$1" default_palette="$2" out_var="$3"
    draw_header 8 $TOTAL_STEPS "Tab tinting — ${state_label}"

    local swatches=()
    local default_idx=1
    local i=0
    for p in "${palettes[@]}"; do
      i=$((i + 1))
      local hex="${hex_of[$p]}"
      # ANSI 24-bit swatch block (four ████ chars in the palette color)
      local r=$((16#${hex:1:2})) g=$((16#${hex:3:2})) b=$((16#${hex:5:2}))
      local swatch; swatch=$(printf '\033[38;2;%d;%d;%dm████\033[0m' "$r" "$g" "$b")
      local label; label=$(printf '%-10s %s  %s' "$p" "$swatch" "$hex")
      swatches+=("$label|")
      [ "$p" = "$default_palette" ] && default_idx=$i
    done

    ask_choice "${swatches[@]}"
    local rc=$?
    if [ $rc -eq 1 ]; then return 1; fi
    printf -v "$out_var" '%s' "${palettes[$((CHOICE_RESULT - 1))]}"
  }

  _tab_state_ask_palette "Running (UserPromptSubmit / PreToolUse)" accent_1 sel_tab_state_running || return 2
  _tab_state_ask_palette "Waiting (Notification)"                  warning  sel_tab_state_waiting || return 2
  _tab_state_ask_palette "Idle (Stop / SessionStart)"              accent_3 sel_tab_state_idle    || return 2
  _tab_state_ask_palette "Error"                                   alert    sel_tab_state_error   || return 2
```

- [ ] **Step 2: Smoke-test the wizard manually**

```bash
bash configure.sh
```

Walk through steps 1–7 normally, then at Step 8 choose Enable and verify 4 swatch pickers appear. Press `r` to restart or `q` to quit without saving. Do not accept changes (hit `q`).

Expected: swatches render in theme colors, pressing a number stores palette name, default highlights match spec.

- [ ] **Step 3: Commit**

```bash
git add configure.sh
git commit -m "feat(configure): step_tab_state 加入 per-state palette 選擇器與 swatch preview"
```

---

## Task 12: `step_done` writes `tab_state` section + `configure.sh` apply install/remove

**Files:**
- Modify: `configure.sh`

- [ ] **Step 1: Read previous `tab_state.enabled` so apply knows prior state**

Find the block near the top of `configure.sh` that reads current values (around lines 60–90; look for `cur_time_format=...`). Add:

```bash
# Previous tab_state.enabled — used in apply to decide install/remove
if [ -f "$CONFIG" ]; then
  cur_tab_state_enabled=$("$JQ" -r '.tab_state.enabled // false' "$CONFIG" 2>/dev/null)
else
  cur_tab_state_enabled="false"
fi
```

- [ ] **Step 2: Modify `step_done` to emit `tab_state` JSON**

Find the `config_content=$(cat <<CONF` HEREDOC in `step_done` (around line 1023). Before the closing `}` of the JSON, add the `tab_state` object.

Replace:

```
OLD (inside the HEREDOC):
  "show_icons": $sel_show_icons,
  "time_format": "$time_format"
}

NEW:
  "show_icons": $sel_show_icons,
  "time_format": "$time_format",
  "tab_state": {
    "enabled": $sel_tab_state_enabled,
    "running": "$sel_tab_state_running",
    "waiting": "$sel_tab_state_waiting",
    "idle": "$sel_tab_state_idle",
    "error": "$sel_tab_state_error"
  }
}
```

- [ ] **Step 3: Call install/remove after writing config**

Still in `step_done`, **immediately after** the `echo "$config_content" > "$CONFIG"` line, add:

```bash
  # Apply tab-state hook changes based on enable transition
  if [ "$sel_tab_state_enabled" = "true" ] && [ "$cur_tab_state_enabled" != "true" ]; then
    if _install_tab_state_hooks "$SCRIPT_DIR"; then
      printf '  \033[32m✓\033[0m tab-state hooks installed to ~/.claude/settings.json\n'
    else
      printf '  \033[31m✗\033[0m tab-state hooks install failed — check ~/.claude/settings.json\n'
    fi
  elif [ "$sel_tab_state_enabled" != "true" ] && [ "$cur_tab_state_enabled" = "true" ]; then
    if _remove_tab_state_hooks; then
      printf '  \033[32m✓\033[0m tab-state hooks removed\n'
    else
      printf '  \033[31m✗\033[0m tab-state hooks removal failed\n'
    fi
  fi
```

- [ ] **Step 4: Add `tab_state` line to summary display**

In the same `step_done` function, find the block that prints summary lines (e.g. `echo -e "\033[2mTime format:\033[0m $time_format"`). Add after it:

```bash
  echo -e "\033[2mTab tint:   \033[0m $sel_tab_state_enabled"
  if [ "$sel_tab_state_enabled" = "true" ]; then
    echo -e "\033[2m  running:  \033[0m $sel_tab_state_running"
    echo -e "\033[2m  waiting:  \033[0m $sel_tab_state_waiting"
    echo -e "\033[2m  idle:     \033[0m $sel_tab_state_idle"
    echo -e "\033[2m  error:    \033[0m $sel_tab_state_error"
  fi
```

- [ ] **Step 5: Manual verify by writing a minimal config**

Create a throwaway config to confirm JSON is valid:

```bash
bash configure.sh
# Walk through all 8 steps, choose Skip at Step 8, finish wizard.
jq '.tab_state' config.json
```

Expected: `{"enabled": false, "running": "accent_1", "waiting": "warning", "idle": "accent_3", "error": "alert"}` — valid JSON.

Then re-run and choose Enable. Afterwards:

```bash
jq '.hooks | keys' ~/.claude/settings.json
# should include SessionStart, UserPromptSubmit, PreToolUse, Notification, Stop, SessionEnd
ls -l ~/.claude/scripts/tab-state.sh
# should be a symlink pointing at this repo's tab-state.sh
```

Clean up afterwards — run `configure.sh` once more and choose Skip to remove hooks.

- [ ] **Step 6: Commit**

```bash
git add configure.sh
git commit -m "feat(configure): step_done 寫入 tab_state 並依轉態安裝/移除 hooks"
```

---

## Task 13: Wire `step_tab_state` into main dispatch

**Files:**
- Modify: `configure.sh`

- [ ] **Step 1: Update main dispatch to call `step_tab_state` between Step 6 (theme) and Step 7 (done)**

Find the main `case` dispatch (around line 1170):

```
OLD:
    6) # Theme
      step_theme
      rc=$?
      if [ $rc -eq 2 ]; then
        restart_wizard
      elif [ $rc -eq 0 ]; then
        current_step=7
      elif [ $rc -eq 1 ]; then
        ...
      fi
      ;;
    7) # Done
      step_done
      break
      ;;
```

Change `current_step=7` → `current_step=7` stays, but Step 7 becomes tab_state; rename existing `7) # Done` to `8) # Done`. Full patch:

```
OLD (after the theme block):
    7) # Done
      step_done
      break
      ;;

NEW:
    7) # Tab state (iTerm2 tinting)
      step_tab_state
      rc=$?
      if [ $rc -eq 2 ]; then
        restart_wizard
      elif [ $rc -eq 0 ]; then
        current_step=8
      fi
      ;;
    8) # Done
      step_done
      break
      ;;
```

- [ ] **Step 2: Full end-to-end smoke test**

```bash
bash configure.sh
```

Walk steps 1–7. Step 8 (tab tinting) appears after theme. Choose Skip → wizard finishes.

Re-run. Choose Enable → 4 palette pickers. Finish.

Verify:

```bash
jq '.' config.json
jq '.hooks' ~/.claude/settings.json
```

- [ ] **Step 3: Commit**

```bash
git add configure.sh
git commit -m "feat(configure): 主 dispatch 插入 step_tab_state (Step 7/8)"
```

---

## Task 14: `uninstall.sh` — source lib and tear down hooks

**Files:**
- Modify: `uninstall.sh`

- [ ] **Step 1: Inspect current `uninstall.sh`**

```bash
cat uninstall.sh
```

Identify where to insert the teardown — usually near the end, before any final "done" message.

- [ ] **Step 2: Add teardown block**

At the top of `uninstall.sh`, after `SCRIPT_DIR` is resolved, source the lib:

```bash
source "$SCRIPT_DIR/_lib_tab_state.sh"
```

Near the end (but before the final success echo), add:

```bash
# Tear down tab-state hooks if present
if [ -L "$HOME/.claude/scripts/tab-state.sh" ] || \
   ( [ -f "$HOME/.claude/settings.json" ] && \
     grep -q 'tab-state.sh' "$HOME/.claude/settings.json" 2>/dev/null ); then
  echo "→ Removing iTerm2 tab-state hooks..."
  if _remove_tab_state_hooks; then
    echo "  ✓ tab-state hooks removed"
  else
    echo "  ✗ tab-state hooks removal failed — inspect ~/.claude/settings.json"
  fi
fi
```

- [ ] **Step 3: Manual verify**

```bash
bash configure.sh   # enable tab_state
bash uninstall.sh
jq '.hooks' ~/.claude/settings.json
# should not contain tab-state.sh commands any more
ls ~/.claude/scripts/tab-state.sh 2>&1
# should report "no such file"
```

- [ ] **Step 4: Commit**

```bash
git add uninstall.sh
git commit -m "feat(uninstall): 偵測並移除 tab-state hooks 與 symlink"
```

---

## Task 15: Documentation — README (EN + zh-TW)

**Files:**
- Modify: `README.md`
- Modify: `docs/README.zh-TW.md`

- [ ] **Step 1: Add a new section to `README.md`**

Find the "Available Blocks" section. After it, insert:

```markdown
### iTerm2 Tab Tinting (optional)

cyberpunk-statusline can tint your iTerm2 tab background based on Claude Code
session state (running / waiting / idle / error). Colors are pulled from your
chosen theme's palette, so switching theme retints tabs automatically.

Enable it via the configure wizard Step 8 — only visible when `$TERM_PROGRAM`
is `iTerm.app`. Selecting Enable writes 6 hooks into `~/.claude/settings.json`
(SessionStart / UserPromptSubmit / PreToolUse / Notification / Stop / SessionEnd)
and a symlink at `~/.claude/scripts/tab-state.sh`. A timestamped backup of
settings.json is created before any modification.

| State   | Default palette | Triggers                     |
|---------|-----------------|------------------------------|
| running | accent_1        | UserPromptSubmit, PreToolUse |
| waiting | warning         | Notification (+ attention)   |
| idle    | accent_3        | SessionStart, Stop           |
| error   | alert           | (reserved, not auto-fired)   |

**Plugin users:** after upgrading to a new cyberpunk-statusline version, rerun
`/cyberpunk-statusline configure` so the symlink points at the new plugin
cache directory.

To disable, rerun configure and choose Skip at Step 8 — hooks are removed
automatically. `./uninstall.sh` also tears them down.
```

- [ ] **Step 2: Mirror the section in `docs/README.zh-TW.md`**

Find the matching "可用 blocks" section (or equivalent) and append:

```markdown
### iTerm2 Tab Tinting（選用）

cyberpunk-statusline 可依 Claude Code session 狀態（running / waiting / idle /
error）改變 iTerm2 tab 底色。顏色從當前 theme palette 取得，換 theme 自動重染。

在 configure wizard 的 Step 8 啟用 — 只有 `$TERM_PROGRAM` 是 `iTerm.app` 時才會
出現。選擇 Enable 會在 `~/.claude/settings.json` 寫入 6 個 hooks
（SessionStart / UserPromptSubmit / PreToolUse / Notification / Stop / SessionEnd）
並在 `~/.claude/scripts/tab-state.sh` 建 symlink。所有修改前會先產生
settings.json 的時間戳備份。

| State   | 預設 palette | 觸發時機                     |
|---------|--------------|------------------------------|
| running | accent_1     | UserPromptSubmit、PreToolUse |
| waiting | warning      | Notification（附 attention） |
| idle    | accent_3     | SessionStart、Stop           |
| error   | alert        | （保留欄位，目前不自動觸發） |

**Plugin 使用者：** 升級 cyberpunk-statusline 版本後請重跑
`/cyberpunk-statusline configure`，讓 symlink 指向新版 plugin cache 目錄。

要停用時重跑 configure 並在 Step 8 選 Skip — hooks 會自動移除。
`./uninstall.sh` 也會一併清除。
```

- [ ] **Step 3: Verify markdown renders correctly**

```bash
head -200 README.md | less
head -200 docs/README.zh-TW.md | less
```

Visual check: table renders, no trailing whitespace artifacts.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/README.zh-TW.md
git commit -m "docs: README 中英雙版新增 iTerm2 tab tinting 章節"
```

---

## Task 16: `LOG.md` changelog entry

**Files:**
- Modify: `LOG.md`

- [ ] **Step 1: Insert new entry at top of `LOG.md`**

Find the first `## YYYY-MM-DD` heading (currently `## 2026-04-21` from the previous time-block commit — if so, add a new sub-section; if not, add a new date heading).

Insert above existing `## 2026-04-21` heading (or append as a new sub-section):

```markdown
## 2026-04-21

### 新增：iTerm2 tab tinting 整合（Step 8）
- 需求：把 claude-cli 的 tab 底色切換搬進 cyberpunk-statusline，讓顏色跟 theme palette 綁定並可在 wizard 自訂
- 新檔：
  - `tab-state.sh` — runtime 腳本，每次 hook 觸發時讀 config.json + theme 解析 palette → hex → RGB，送 iTerm2 OSC escape sequence
  - `_lib_tab_state.sh` — `_install_tab_state_hooks` / `_remove_tab_state_hooks` / `_detect_foreign_tab_state_hooks` 三個共用 helper，供 configure.sh 與 uninstall.sh source
  - `tests/test-tab-state.sh` / `tests/test-lib-tab-state.sh` — 單元測試
- 修改：
  - `configure.sh` — TOTAL_STEPS 7 → 8；新增 `step_tab_state`（非 iTerm2 auto-skip、Enable/Skip、4 × palette 選擇 + swatch preview）；`step_done` 寫 `tab_state` 欄位並依啟用轉態呼叫 install/remove
  - `uninstall.sh` — 偵測既有 tab-state hooks 與 symlink 後呼叫 `_remove_tab_state_hooks`
- 行為：
  - 換 theme 後下次 hook 觸發 tab 底色自動更新（script 每次重讀 config + theme）
  - config.json 沒 `tab_state` 欄位 / `enabled:false` → script 直接 exit 0 靜默
  - 非 iTerm2 終端機 wizard 自動跳過、script 自己也會靜默 exit
  - 偵測到其他來源（例如 claude-cli 那份）的 tab-state hooks 時印警告
```

- [ ] **Step 2: Commit**

```bash
git add LOG.md
git commit -m "docs(log): 紀錄 iTerm2 tab tinting 整合"
```

---

## Task 17: Final end-to-end manual acceptance

**No file changes.** Verification only.

- [ ] **Step 1: Clean slate check**

```bash
# Back up any existing settings.json (optional)
cp ~/.claude/settings.json ~/.claude/settings.json.pre-qa 2>/dev/null || true
# Verify no tab-state hooks currently
grep -c tab-state.sh ~/.claude/settings.json || echo 0
```

- [ ] **Step 2: Run full test suite**

```bash
bash tests/test-tab-state.sh && bash tests/test-lib-tab-state.sh && bash tests/test-configure.sh && bash tests/test-statusline.sh
```

Expected: all tests pass.

- [ ] **Step 3: Enable tab tinting via wizard, observe iTerm2 tab**

```bash
bash configure.sh
# Walk through all 8 steps, choose Enable + accept defaults at Step 8
```

Open a new iTerm2 tab in the project dir, run `claude`:
- SessionStart fires → tab bg turns the `accent_3` color (idle)
- Type a message → UserPromptSubmit fires → tab bg turns `accent_1` (running)
- Wait for response → if any Notification fires → tab bg turns `warning` + dock icon bounces

- [ ] **Step 4: Theme switch retints**

```bash
bash configure.sh
# In Step 6 pick a different theme, finish wizard keeping tab_state enabled
```

In an iTerm2 tab that already has a Claude session, send another message — tab color should use the new theme's `accent_1`.

- [ ] **Step 5: Disable and verify clean removal**

```bash
bash configure.sh
# Step 8 → choose Skip, finish
grep -c tab-state.sh ~/.claude/settings.json
```

Expected: `0`. Also verify `~/.claude/scripts/tab-state.sh` is gone.

- [ ] **Step 6: Uninstall path**

```bash
# Re-enable for this test
bash configure.sh  # choose Enable at Step 8
bash uninstall.sh
grep -c tab-state.sh ~/.claude/settings.json
ls ~/.claude/scripts/tab-state.sh 2>&1 | grep -q "No such file" && echo "OK"
```

Expected: count 0, symlink gone.

- [ ] **Step 7: Restore pre-QA settings (if backed up)**

```bash
# If you made settings.json.pre-qa in Step 1 and want to restore
# cp ~/.claude/settings.json.pre-qa ~/.claude/settings.json
```

- [ ] **Step 8: Post-completion reminder**

Once all above pass, feature is verified end-to-end. No commit needed for this task.

---

## Self-Review Results

**Spec coverage check:**
- §2 scope "in scope" items ↔ tasks: tab-state.sh (Tasks 1–6) ✓, tab_state schema in config (Task 12) ✓, configure.sh Step 8 (Tasks 10–13) ✓, hooks merge/teardown (Tasks 7–9) ✓, uninstall.sh symmetry (Task 14) ✓, tests (Tasks 1–9) ✓, README + LOG (Tasks 15–16) ✓
- §5 tab-state.sh logic ↔ Tasks 1–6 incremental build ✓
- §6 hooks merge strategy (jq append) ↔ Task 7 ✓; teardown jq filter ↔ Task 8 ✓; foreign detection ↔ Task 9 ✓
- §7 wizard UX (Steps 8.0/8.1/8.2/8.3) ↔ Tasks 10 (8.0/8.1), 11 (8.2), 12 (8.3 summary) ✓
- §10 risks ↔ Task 10 surfaces claude-cli detection ✓; README mentions plugin upgrade reminder ✓

**Placeholder scan:** none found — all steps have concrete commands and code.

**Type/name consistency:**
- `_install_tab_state_hooks("$repo_dir")` (single arg) — used consistently in Tasks 7, 12, 14 ✓
- `_remove_tab_state_hooks` (no args) — consistent ✓
- `_detect_foreign_tab_state_hooks("$self_path")` — consistent in Tasks 9, 10 ✓
- config keys `tab_state.enabled/running/waiting/idle/error` — consistent across Tasks 3, 6, 12 ✓
- Env vars `CYBERPUNK_STATUSLINE_REPO_DIR` (script side), `CLAUDE_SETTINGS_OVERRIDE` / `CLAUDE_SCRIPTS_DIR_OVERRIDE` (lib side) — consistent ✓
