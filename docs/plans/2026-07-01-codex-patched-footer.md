# Codex Patched Footer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Codex-only patched footer integration that can render a cyberpunk status line through a command-backed patched Codex binary without touching any Claude behavior.

**Architecture:** Add an isolated `adapters/codex/` runtime with a fast `--line` renderer, TOML-safe config helpers, and dry-run-first patched install/uninstall scripts. The existing Claude root scripts and renderer stay unchanged; the Codex patch path installs a separate `codex-cyberpunk` command by default.

**Tech Stack:** Bash, jq, git, Codex CLI, shell test scripts, TOML text patching with guarded markers.

---

## Guardrails

- Do not modify `statusline.sh`, `install.sh`, `configure.sh`, `uninstall.sh`, `tab-state.sh`, `_lib_tab_state.sh`, or any Claude adapter/config path.
- Do not write `~/.claude/*`.
- Do not overwrite the user's `codex` command.
- All installer behavior that could mutate user state must support `--dry-run`.
- Use TDD for production shell behavior.

### Task 1: Add Codex renderer baseline tests

**Files:**
- Create: `tests/adapters/codex/test-statusline.sh`
- Create: `tests/adapters/codex/fixtures/minimal-session.jsonl`
- Create: `tests/adapters/codex/fixtures/rate-session.jsonl`
- Create: `adapters/codex/.gitkeep`

**Step 1: Write the failing test**

Create `tests/adapters/codex/test-statusline.sh`:

```bash
#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RENDERER="$PROJECT_DIR/adapters/codex/statusline.sh"

PASS=0
FAIL=0

check_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -Fq "$needle"; then
    echo "✓ $label"; ((PASS++))
  else
    echo "✗ $label — missing: $needle — got: $haystack"; ((FAIL++))
  fi
}

test_no_sessions_outputs_placeholders() {
  local home_tmp; home_tmp=$(mktemp -d)
  mkdir -p "$home_tmp/.codex"
  printf 'model = "gpt-5.5"\nmodel_reasoning_effort = "medium"\n' > "$home_tmp/.codex/config.toml"

  local out
  out=$(HOME="$home_tmp" CYBERPUNK_STATUSLINE_ROOT="$PROJECT_DIR" bash "$RENDERER" --line 2>/dev/null || true)
  rm -rf "$home_tmp"

  check_contains "no sessions includes model" "gpt-5.5" "$out"
  check_contains "no sessions includes context placeholder" "Ctx:--" "$out"
  check_contains "no sessions includes rate placeholder" "5h:--" "$out"
}

test_fixture_session_outputs_usage() {
  local home_tmp; home_tmp=$(mktemp -d)
  mkdir -p "$home_tmp/.codex/sessions/2026/07/01"
  cp "$SCRIPT_DIR/fixtures/rate-session.jsonl" "$home_tmp/.codex/sessions/2026/07/01/rollout-test.jsonl"
  printf 'model = "gpt-5.5"\nmodel_reasoning_effort = "xhigh"\n' > "$home_tmp/.codex/config.toml"

  local out
  out=$(HOME="$home_tmp" CYBERPUNK_STATUSLINE_ROOT="$PROJECT_DIR" bash "$RENDERER" --line 2>/dev/null || true)
  rm -rf "$home_tmp"

  check_contains "fixture includes effort" "xhigh" "$out"
  check_contains "fixture includes context" "Ctx:42%" "$out"
  check_contains "fixture includes 5h" "5h:68%" "$out"
  check_contains "fixture includes 7d" "7d:86%" "$out"
}

test_no_claude_files_referenced() {
  if grep -R "\.claude" "$PROJECT_DIR/adapters/codex" "$PROJECT_DIR/tests/adapters/codex" >/dev/null 2>&1; then
    echo "✗ codex adapter references .claude"; ((FAIL++))
  else
    echo "✓ codex adapter does not reference .claude"; ((PASS++))
  fi
}

test_no_sessions_outputs_placeholders
test_fixture_session_outputs_usage
test_no_claude_files_referenced

echo "PASS=$PASS FAIL=$FAIL"
exit "$FAIL"
```

Create fixture files as JSONL lines that future parser can read:

`tests/adapters/codex/fixtures/minimal-session.jsonl`

```jsonl
{"type":"session","model":"gpt-5.5","cwd":"/tmp/project"}
```

`tests/adapters/codex/fixtures/rate-session.jsonl`

```jsonl
{"type":"session","model":"gpt-5.5","cwd":"/tmp/project"}
{"type":"usage","context_used_percent":42,"five_hour_percent":68,"weekly_percent":86}
```

**Step 2: Run test to verify it fails**

Run: `bash tests/adapters/codex/test-statusline.sh`

Expected: FAIL because `adapters/codex/statusline.sh` does not exist.

**Step 3: Commit**

```bash
git add adapters/codex/.gitkeep tests/adapters/codex/test-statusline.sh tests/adapters/codex/fixtures/minimal-session.jsonl tests/adapters/codex/fixtures/rate-session.jsonl
git commit -m "test(codex): add statusline renderer contract"
```

### Task 2: Implement the Codex line renderer

**Files:**
- Create: `adapters/codex/statusline.sh`
- Test: `tests/adapters/codex/test-statusline.sh`

**Step 1: Run the failing renderer test**

Run: `bash tests/adapters/codex/test-statusline.sh`

Expected: FAIL because renderer is absent.

**Step 2: Write minimal implementation**

Create `adapters/codex/statusline.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" != "--line" ]; then
  echo "usage: statusline.sh --line" >&2
  exit 2
fi

ROOT="${CYBERPUNK_STATUSLINE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
CONFIG_TOML="${CODEX_CONFIG_TOML:-$HOME/.codex/config.toml}"
SESSIONS_DIR="${CODEX_SESSIONS_DIR:-$HOME/.codex/sessions}"

read_config_value() {
  local key="$1" default="$2"
  if [ -f "$CONFIG_TOML" ]; then
    awk -F= -v key="$key" '
      $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
        gsub(/^"|"$/, "", $2)
        print $2
        found=1
        exit
      }
      END { if (!found) exit 1 }
    ' "$CONFIG_TOML" 2>/dev/null || printf '%s' "$default"
  else
    printf '%s' "$default"
  fi
}

latest_session_file() {
  [ -d "$SESSIONS_DIR" ] || return 1
  find "$SESSIONS_DIR" -type f -name '*.jsonl' -print 2>/dev/null | sort | tail -1
}

read_latest_usage_field() {
  local field="$1" file="$2"
  [ -n "$file" ] && [ -f "$file" ] || { printf -- '--'; return; }
  jq -r --arg field "$field" '
    select(type == "object" and has($field)) | .[$field]
  ' "$file" 2>/dev/null | tail -1 | awk 'NF { print; found=1 } END { if (!found) print "--" }'
}

git_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null || printf -- '--'
}

model="$(read_config_value model "codex")"
effort="$(read_config_value model_reasoning_effort "")"
session_file="$(latest_session_file || true)"
ctx="$(read_latest_usage_field context_used_percent "$session_file")"
five="$(read_latest_usage_field five_hour_percent "$session_file")"
weekly="$(read_latest_usage_field weekly_percent "$session_file")"
branch="$(git_branch)"
project="$(basename "$(pwd)")"

model_part="$model"
[ -n "$effort" ] && model_part="$model_part $effort"

printf '%s|%s|git(%s)|Ctx:%s|5h:%s|7d:%s\n' "$model_part" "$project" "$branch" "${ctx}${ctx:+%}" "${five}${five:+%}" "${weekly}${weekly:+%}" |
  sed 's/--%/--/g'
```

**Step 3: Make executable**

Run: `chmod +x adapters/codex/statusline.sh`

**Step 4: Run test to verify it passes**

Run: `bash tests/adapters/codex/test-statusline.sh`

Expected: PASS.

**Step 5: Commit**

```bash
git add adapters/codex/statusline.sh tests/adapters/codex/test-statusline.sh
git commit -m "feat(codex): add standalone statusline renderer"
```

### Task 3: Add Codex config merge helpers

**Files:**
- Create: `adapters/codex/lib-config.sh`
- Create: `tests/adapters/codex/test-lib-config.sh`

**Step 1: Write the failing test**

Create `tests/adapters/codex/test-lib-config.sh` with tests that source `adapters/codex/lib-config.sh` and assert:

- `_codex_set_status_line_command <config> <command>` adds `[tui].status_line_command`
- existing `status_line = [...]` remains unchanged
- unrelated tables remain unchanged
- `_codex_remove_status_line_command <config> <project_root>` removes only a command containing this project path

**Step 2: Run test to verify it fails**

Run: `bash tests/adapters/codex/test-lib-config.sh`

Expected: FAIL because helper file does not exist.

**Step 3: Implement minimal config helpers**

Implement functions using guarded `awk`/temporary files. Keep parsing conservative:

- If `[tui]` exists, insert or replace only `status_line_command = "..."`
- If `[tui]` is absent, append it at EOF
- Never edit `[hooks.state]`, `[projects.*]`, or Claude files
- Create `*.bak.YYYYMMDD-HHMMSS` before writing

**Step 4: Run config tests**

Run: `bash tests/adapters/codex/test-lib-config.sh`

Expected: PASS.

**Step 5: Commit**

```bash
git add adapters/codex/lib-config.sh tests/adapters/codex/test-lib-config.sh
git commit -m "feat(codex): add config merge helpers"
```

### Task 4: Add patched install dry-run script

**Files:**
- Create: `adapters/codex/install-patched.sh`
- Create: `tests/adapters/codex/test-install-patched.sh`
- Modify: `adapters/codex/lib-config.sh`

**Step 1: Write the failing test**

Create `tests/adapters/codex/test-install-patched.sh` that runs:

```bash
HOME="$tmp_home" CODEX_BIN_OVERRIDE=/bin/echo bash adapters/codex/install-patched.sh --dry-run
```

Assert output includes:

- current Codex binary path
- renderer command path
- `codex-cyberpunk`
- `dry-run`

Assert no files are created under `$tmp_home/.local/bin`.

**Step 2: Run test to verify it fails**

Run: `bash tests/adapters/codex/test-install-patched.sh`

Expected: FAIL because installer does not exist.

**Step 3: Implement dry-run installer**

Create `adapters/codex/install-patched.sh` with:

- `--dry-run` required for initial implementation
- detection of `codex` via `CODEX_BIN_OVERRIDE` or `command -v codex`
- renderer command: `bash "$PROJECT_DIR/adapters/codex/statusline.sh" --line`
- planned output path: `$HOME/.local/bin/codex-cyberpunk`
- clear message that real patch/build is not executed until later task

**Step 4: Run installer test**

Run: `bash tests/adapters/codex/test-install-patched.sh`

Expected: PASS.

**Step 5: Commit**

```bash
git add adapters/codex/install-patched.sh tests/adapters/codex/test-install-patched.sh
git commit -m "feat(codex): add patched installer dry run"
```

### Task 5: Add uninstall dry-run script

**Files:**
- Create: `adapters/codex/uninstall-patched.sh`
- Create: `tests/adapters/codex/test-uninstall-patched.sh`

**Step 1: Write the failing test**

Create `tests/adapters/codex/test-uninstall-patched.sh` that:

- creates a temp `~/.codex/config.toml` with `[tui].status_line_command`
- runs `adapters/codex/uninstall-patched.sh --dry-run`
- asserts output mentions removal of `status_line_command`
- asserts temp config content is unchanged
- asserts no `.claude` path is created

**Step 2: Run test to verify it fails**

Run: `bash tests/adapters/codex/test-uninstall-patched.sh`

Expected: FAIL because uninstaller does not exist.

**Step 3: Implement dry-run uninstaller**

Create `adapters/codex/uninstall-patched.sh` with:

- `--dry-run`
- planned removal of `$HOME/.local/bin/codex-cyberpunk`
- planned removal of project-owned `status_line_command`
- no Claude references

**Step 4: Run uninstaller test**

Run: `bash tests/adapters/codex/test-uninstall-patched.sh`

Expected: PASS.

**Step 5: Commit**

```bash
git add adapters/codex/uninstall-patched.sh tests/adapters/codex/test-uninstall-patched.sh
git commit -m "feat(codex): add patched uninstaller dry run"
```

### Task 6: Add patch source scaffold

**Files:**
- Create: `adapters/codex/patches/status-line-command.patch`
- Create: `tests/adapters/codex/test-patch-scaffold.sh`
- Modify: `adapters/codex/install-patched.sh`

**Step 1: Write the failing test**

Create `tests/adapters/codex/test-patch-scaffold.sh` that asserts:

- patch file exists
- patch contains `status_line_command`
- installer dry-run output references the patch file

**Step 2: Run test to verify it fails**

Run: `bash tests/adapters/codex/test-patch-scaffold.sh`

Expected: FAIL because patch file is absent.

**Step 3: Add patch scaffold**

Add `adapters/codex/patches/status-line-command.patch` as a documented patch scaffold. If exact upstream file paths are not stable, make this file contain a clear placeholder and require install script to fail before applying it unless the target version is supported.

**Step 4: Update installer dry-run**

Update dry-run output to show:

- source cache path
- patch path
- build output path
- unsupported-version safety note

**Step 5: Run test**

Run: `bash tests/adapters/codex/test-patch-scaffold.sh`

Expected: PASS.

**Step 6: Commit**

```bash
git add adapters/codex/patches/status-line-command.patch adapters/codex/install-patched.sh tests/adapters/codex/test-patch-scaffold.sh
git commit -m "feat(codex): scaffold status line command patch"
```

### Task 7: Document Codex patched footer usage

**Files:**
- Create: `docs/codex-patched-footer.md`
- Modify: `README.md` only if adding a short Codex docs link is approved separately

**Step 1: Write docs**

Create `docs/codex-patched-footer.md` with:

- warning that this is Codex-only and patched/experimental
- dry-run command
- renderer preview command
- install/uninstall commands
- recovery instructions
- explicit statement that Claude integration is unchanged

**Step 2: Run docs and shell verification**

Run:

```bash
bash tests/adapters/codex/test-statusline.sh
bash tests/adapters/codex/test-lib-config.sh
bash tests/adapters/codex/test-install-patched.sh
bash tests/adapters/codex/test-uninstall-patched.sh
bash tests/adapters/codex/test-patch-scaffold.sh
```

Expected: all PASS.

**Step 3: Confirm Claude files unchanged**

Run:

```bash
git diff -- statusline.sh install.sh configure.sh uninstall.sh tab-state.sh _lib_tab_state.sh
```

Expected: no output.

**Step 4: Commit**

```bash
git add docs/codex-patched-footer.md
git commit -m "docs(codex): document patched footer workflow"
```
