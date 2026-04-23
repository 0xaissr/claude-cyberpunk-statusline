# Codex Multi-Backend Statusline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor `cyberpunk-statusline` into a shared framework with Claude and Codex adapters while preserving current Claude behavior and adding a first working Codex integration.

**Architecture:** Extract a backend-agnostic renderer and normalized schema first, migrate Claude onto that runtime without regressions, then add a thin Codex adapter and backend-aware installer/configure flows. Keep themes shared, preserve legacy config compatibility, and treat unavailable Codex telemetry as an explicit state instead of a failure.

**Tech Stack:** Bash, jq, git, shell test scripts, Claude settings integration, Codex config/hooks integration

---

### Task 1: Add normalized schema fixtures for shared renderer tests

**Files:**
- Create: `tests/core/fixtures/normalized-claude.json`
- Create: `tests/core/fixtures/normalized-codex-minimal.json`
- Create: `tests/core/test-renderer.sh`
- Reference: `tests/sample-input.json`

**Step 1: Write the failing test**

Create `tests/core/test-renderer.sh` with checks that expect a future shared renderer entrypoint to:

- render non-empty output for a fully populated normalized payload
- render non-empty output for a Codex-minimal payload
- render unavailable blocks without crashing

Use an expected command shape like:

```bash
output=$(CONFIG_OVERRIDE="$config_tmp" bash "$PROJECT_DIR/core/render.sh" < "$fixture" 2>/dev/null || true)
[[ -n "$output" ]]
```

**Step 2: Run test to verify it fails**

Run: `bash tests/core/test-renderer.sh`

Expected: FAIL because `core/render.sh` does not exist yet.

**Step 3: Add minimal fixtures**

Create:

- `tests/core/fixtures/normalized-claude.json`
- `tests/core/fixtures/normalized-codex-minimal.json`

Populate them with the normalized schema approved in `docs/plans/2026-04-23-codex-multi-backend-statusline-design.md`.

**Step 4: Run test again**

Run: `bash tests/core/test-renderer.sh`

Expected: still FAIL because the renderer is not implemented yet, but fixture parsing should be valid.

**Step 5: Commit**

```bash
git add tests/core/fixtures/normalized-claude.json tests/core/fixtures/normalized-codex-minimal.json tests/core/test-renderer.sh
git commit -m "test(core): add normalized renderer fixtures"
```

### Task 2: Extract shared theme/config/color helpers into `core/`

**Files:**
- Create: `core/theme.sh`
- Create: `core/config.sh`
- Create: `core/colors.sh`
- Modify: `statusline.sh`
- Test: `tests/test-statusline.sh`

**Step 1: Write the failing test**

Extend `tests/test-statusline.sh` with a focused assertion that the current legacy entrypoint still renders after sourcing shared helpers.

Example check:

```bash
output=$(cat "$SAMPLE" | bash "$STATUSLINE" 2>/dev/null || true)
[[ -n "$output" ]]
```

**Step 2: Run test to verify it passes before refactor**

Run: `bash tests/test-statusline.sh`

Expected: PASS on the existing implementation so the baseline is captured.

**Step 3: Move helper logic**

Extract these groups from `statusline.sh` into shared files:

- config loading and defaults
- theme lookup helpers
- `hex_to_fg`, `hex_to_bg`, `make_bar`, `neon_colour`

Keep `statusline.sh` behavior unchanged by sourcing the new files.

**Step 4: Run test suite**

Run: `bash tests/test-statusline.sh`

Expected: PASS with no visible behavior regression.

**Step 5: Commit**

```bash
git add core/theme.sh core/config.sh core/colors.sh statusline.sh tests/test-statusline.sh
git commit -m "refactor(core): extract shared theme and color helpers"
```

### Task 3: Introduce a backend-agnostic renderer entrypoint

**Files:**
- Create: `core/render.sh`
- Create: `core/blocks.sh`
- Modify: `statusline.sh`
- Test: `tests/core/test-renderer.sh`
- Test: `tests/test-statusline.sh`

**Step 1: Write the failing test**

Update `tests/core/test-renderer.sh` to call `core/render.sh` directly and assert:

- classic output renders
- rainbow output renders
- unavailable fields show placeholders such as `--`

**Step 2: Run test to verify it fails**

Run: `bash tests/core/test-renderer.sh`

Expected: FAIL because `core/render.sh` is missing or incomplete.

**Step 3: Implement the shared renderer**

Move layout assembly and block rendering logic from `statusline.sh` into:

- `core/blocks.sh`
- `core/render.sh`

`core/render.sh` must accept normalized JSON on stdin and render without referencing Claude-specific paths.

**Step 4: Keep `statusline.sh` as a compatibility wrapper**

Temporarily let `statusline.sh` normalize legacy Claude input enough to call `core/render.sh`, or source the same shared rendering path while preserving its CLI contract.

**Step 5: Run tests**

Run:

- `bash tests/core/test-renderer.sh`
- `bash tests/test-statusline.sh`

Expected: both PASS.

**Step 6: Commit**

```bash
git add core/render.sh core/blocks.sh statusline.sh tests/core/test-renderer.sh tests/test-statusline.sh
git commit -m "refactor(core): add backend-agnostic renderer"
```

### Task 4: Create a dedicated Claude adapter

**Files:**
- Create: `adapters/claude/render.sh`
- Create: `tests/adapters/claude/test-render.sh`
- Modify: `statusline.sh`
- Reference: `tests/sample-input.json`

**Step 1: Write the failing test**

Create `tests/adapters/claude/test-render.sh` that feeds `tests/sample-input.json` into `adapters/claude/render.sh` and expects normalized rendering output.

**Step 2: Run test to verify it fails**

Run: `bash tests/adapters/claude/test-render.sh`

Expected: FAIL because the adapter does not exist yet.

**Step 3: Implement Claude normalization**

Create `adapters/claude/render.sh` that:

- reads current Claude stdin JSON
- maps it to the normalized schema
- keeps current effort fallback behavior
- keeps current cost behavior for Claude sessions
- calls `core/render.sh`

Make `statusline.sh` a thin wrapper around `adapters/claude/render.sh`.

**Step 4: Run adapter and legacy tests**

Run:

- `bash tests/adapters/claude/test-render.sh`
- `bash tests/test-statusline.sh`

Expected: PASS.

**Step 5: Commit**

```bash
git add adapters/claude/render.sh statusline.sh tests/adapters/claude/test-render.sh
git commit -m "refactor(claude): move legacy runtime into adapter"
```

### Task 5: Move Claude tab-state helpers under the Claude adapter

**Files:**
- Create: `adapters/claude/tab-state.sh`
- Create: `adapters/claude/lib-tab-state.sh`
- Modify: `tab-state.sh`
- Modify: `_lib_tab_state.sh`
- Test: `tests/test-tab-state.sh`
- Test: `tests/test-lib-tab-state.sh`

**Step 1: Write the failing test**

Add assertions to existing tab-state tests that the repo-root files remain functional wrappers after the move.

**Step 2: Run tests to capture baseline**

Run:

- `bash tests/test-tab-state.sh`
- `bash tests/test-lib-tab-state.sh`

Expected: PASS before refactor.

**Step 3: Move implementation**

Move the real Claude tab-state implementation under `adapters/claude/` and keep repo-root files as wrappers or compatibility shims.

**Step 4: Run tests**

Run:

- `bash tests/test-tab-state.sh`
- `bash tests/test-lib-tab-state.sh`

Expected: PASS.

**Step 5: Commit**

```bash
git add adapters/claude/tab-state.sh adapters/claude/lib-tab-state.sh tab-state.sh _lib_tab_state.sh tests/test-tab-state.sh tests/test-lib-tab-state.sh
git commit -m "refactor(claude): move tab-state logic into adapter"
```

### Task 6: Add legacy-config compatibility helpers

**Files:**
- Modify: `core/config.sh`
- Create: `tests/core/test-config-compat.sh`
- Reference: `config.json`

**Step 1: Write the failing test**

Create `tests/core/test-config-compat.sh` covering:

- flat legacy config without `integrations`
- new config with `integrations.claude.enabled`
- new config with `integrations.codex.enabled`

Assert that legacy config resolves to Claude-enabled and Codex-disabled defaults.

**Step 2: Run test to verify it fails**

Run: `bash tests/core/test-config-compat.sh`

Expected: FAIL because compatibility logic is not implemented yet.

**Step 3: Implement compatibility logic**

Teach shared config loading to synthesize:

- `integrations.claude.enabled = true`
- `integrations.codex.enabled = false`

when the new structure is absent.

**Step 4: Run tests**

Run: `bash tests/core/test-config-compat.sh`

Expected: PASS.

**Step 5: Commit**

```bash
git add core/config.sh tests/core/test-config-compat.sh
git commit -m "feat(config): add legacy compatibility for integrations"
```

### Task 7: Add a Codex adapter render path

**Files:**
- Create: `adapters/codex/render.sh`
- Create: `tests/adapters/codex/sample-hook-input.json`
- Create: `tests/adapters/codex/test-render.sh`
- Reference: `docs/plans/2026-04-23-codex-multi-backend-statusline-design.md`

**Step 1: Write the failing test**

Create `tests/adapters/codex/test-render.sh` that feeds a representative Codex hook payload into `adapters/codex/render.sh` and asserts:

- output is non-empty
- model renders
- directory renders
- unavailable blocks do not crash rendering

**Step 2: Run test to verify it fails**

Run: `bash tests/adapters/codex/test-render.sh`

Expected: FAIL because the adapter does not exist yet.

**Step 3: Implement the minimal Codex adapter**

Map available Codex fields into the normalized schema:

- agent kind
- session id
- model
- cwd to workspace current dir

Leave unsupported telemetry unavailable.

**Step 4: Run tests**

Run: `bash tests/adapters/codex/test-render.sh`

Expected: PASS.

**Step 5: Commit**

```bash
git add adapters/codex/render.sh tests/adapters/codex/sample-hook-input.json tests/adapters/codex/test-render.sh
git commit -m "feat(codex): add minimal render adapter"
```

### Task 8: Add Codex hook installer helpers

**Files:**
- Create: `adapters/codex/lib-hooks.sh`
- Create: `tests/installers/test-codex-hooks.sh`
- Reference: `~/.codex/hooks.json`
- Reference: `~/.codex/config.toml`

**Step 1: Write the failing test**

Create `tests/installers/test-codex-hooks.sh` that uses temporary override paths and verifies:

- install writes this repo's hook entries
- uninstall removes only this repo's entries
- unrelated hooks remain intact

**Step 2: Run test to verify it fails**

Run: `bash tests/installers/test-codex-hooks.sh`

Expected: FAIL because the helper does not exist yet.

**Step 3: Implement Codex hook helpers**

Create helper functions to:

- locate hooks/config override paths
- merge hook entries without removing unrelated data
- remove only this repo's entries
- detect whether Codex hooks support is disabled in config

Use temp files plus `jq empty` validation before replacing files.

**Step 4: Run tests**

Run: `bash tests/installers/test-codex-hooks.sh`

Expected: PASS.

**Step 5: Commit**

```bash
git add adapters/codex/lib-hooks.sh tests/installers/test-codex-hooks.sh
git commit -m "feat(codex): add hook install helpers"
```

### Task 9: Add backend-specific install and uninstall scripts

**Files:**
- Create: `adapters/claude/install.sh`
- Create: `adapters/claude/uninstall.sh`
- Create: `adapters/codex/install.sh`
- Create: `adapters/codex/uninstall.sh`
- Create: `tests/installers/test-backend-installers.sh`
- Modify: `install.sh`
- Modify: `uninstall.sh`

**Step 1: Write the failing test**

Create `tests/installers/test-backend-installers.sh` that verifies root installers delegate correctly using temp override paths.

**Step 2: Run test to verify it fails**

Run: `bash tests/installers/test-backend-installers.sh`

Expected: FAIL because the backend installers do not exist yet.

**Step 3: Implement backend installers**

Split host-specific install logic into adapter scripts and make root scripts delegate based on selected backend targets.

Preserve current Claude-only success path.

**Step 4: Run tests**

Run: `bash tests/installers/test-backend-installers.sh`

Expected: PASS.

**Step 5: Commit**

```bash
git add adapters/claude/install.sh adapters/claude/uninstall.sh adapters/codex/install.sh adapters/codex/uninstall.sh install.sh uninstall.sh tests/installers/test-backend-installers.sh
git commit -m "refactor(install): split host integration by adapter"
```

### Task 10: Update the configure wizard for backend-aware integration

**Files:**
- Modify: `configure.sh`
- Modify: `tests/test-configure.sh`
- Reference: `config.json`

**Step 1: Write the failing test**

Add test cases that assert generated config includes:

- shared visual settings
- `integrations.claude.enabled`
- `integrations.codex.enabled`

Use a non-interactive helper path if one already exists; otherwise add a focused unit-style shell function test around config emission.

**Step 2: Run test to verify it fails**

Run: `bash tests/test-configure.sh`

Expected: FAIL because the emitted config does not include the new integration structure.

**Step 3: Implement the wizard changes**

Update `configure.sh` to:

- add backend selection
- emit the new config shape
- preserve Claude tab-state steps only when Claude integration is enabled
- preserve current behavior for legacy Claude-only users when Codex is not selected

**Step 4: Run tests**

Run: `bash tests/test-configure.sh`

Expected: PASS.

**Step 5: Commit**

```bash
git add configure.sh tests/test-configure.sh
git commit -m "feat(configure): add backend-aware integration settings"
```

### Task 11: Extend top-level statusline and theme tests for Codex paths

**Files:**
- Modify: `tests/test-statusline.sh`
- Modify: `tests/core/test-renderer.sh`
- Modify: `tests/adapters/codex/test-render.sh`

**Step 1: Write the failing test**

Add assertions for:

- legacy Claude wrapper path
- shared core renderer path
- Codex adapter path
- unavailable block rendering under Codex fixtures

**Step 2: Run test to verify at least one case fails**

Run:

- `bash tests/test-statusline.sh`
- `bash tests/core/test-renderer.sh`
- `bash tests/adapters/codex/test-render.sh`

Expected: one or more failures until all assertions are satisfied.

**Step 3: Fix gaps**

Adjust rendering placeholders, config defaults, or adapter outputs until all three suites pass consistently.

**Step 4: Run tests**

Run the same three commands again.

Expected: all PASS.

**Step 5: Commit**

```bash
git add tests/test-statusline.sh tests/core/test-renderer.sh tests/adapters/codex/test-render.sh
git commit -m "test: cover shared and codex render paths"
```

### Task 12: Update documentation for multi-backend support

**Files:**
- Modify: `README.md`
- Modify: `docs/README.zh-TW.md`
- Modify: `LOG.md`
- Reference: `docs/plans/2026-04-23-codex-multi-backend-statusline-design.md`

**Step 1: Write the failing documentation checklist**

Create a short checklist in your working notes covering:

- install flow for Claude, Codex, Both
- unsupported Codex telemetry behavior
- shared config explanation
- legacy compatibility note

**Step 2: Update docs**

Document:

- supported backends
- installation choices
- Codex limitations for v1
- config structure changes

Keep `README.md` and `docs/README.zh-TW.md` in sync per project rules.

**Step 3: Verify docs**

Run:

- `rg -n "Codex|Claude|Both|integrations|hide_unavailable_blocks" README.md docs/README.zh-TW.md LOG.md`

Expected: relevant sections exist in all required docs.

**Step 4: Commit**

```bash
git add README.md docs/README.zh-TW.md LOG.md
git commit -m "docs: describe multi-backend statusline support"
```

### Task 13: Run full verification before merge

**Files:**
- No code changes required
- Test: `tests/test-statusline.sh`
- Test: `tests/test-configure.sh`
- Test: `tests/test-tab-state.sh`
- Test: `tests/test-lib-tab-state.sh`
- Test: `tests/core/test-renderer.sh`
- Test: `tests/core/test-config-compat.sh`
- Test: `tests/adapters/claude/test-render.sh`
- Test: `tests/adapters/codex/test-render.sh`
- Test: `tests/installers/test-codex-hooks.sh`
- Test: `tests/installers/test-backend-installers.sh`

**Step 1: Run the full suite**

Run:

```bash
bash tests/test-statusline.sh
bash tests/test-configure.sh
bash tests/test-tab-state.sh
bash tests/test-lib-tab-state.sh
bash tests/core/test-renderer.sh
bash tests/core/test-config-compat.sh
bash tests/adapters/claude/test-render.sh
bash tests/adapters/codex/test-render.sh
bash tests/installers/test-codex-hooks.sh
bash tests/installers/test-backend-installers.sh
```

Expected: all PASS.

**Step 2: Smoke-check host integrations**

Manual checks:

- Claude install path still configures status line correctly.
- Codex install path writes only expected hook entries.
- Legacy config still loads.
- Codex unavailable blocks render placeholders, not empty crashes.

**Step 3: Final commit**

```bash
git add .
git commit -m "feat: add codex multi-backend statusline support"
```
