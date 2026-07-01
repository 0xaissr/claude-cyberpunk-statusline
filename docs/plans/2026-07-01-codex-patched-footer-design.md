# Codex Patched Footer Design

- **Date**: 2026-07-01
- **Status**: Approved
- **Scope**: Codex only. Claude behavior, Claude installer, Claude statusline renderer, and Claude tab-state files must remain untouched.

## Goal

Add a Codex integration path that can render this project's cyberpunk status line inside a patched Codex TUI footer, while keeping the stock Claude integration unchanged.

## Decision

Use a patched Codex footer path rather than limiting the integration to Codex's built-in `[tui].status_line` item list.

Stock Codex currently supports configurable built-in status-line items, but not a command-backed renderer equivalent to Claude Code's `statusLine.command`. The Codex integration therefore needs two separable parts:

1. A local command renderer that prints one compact ANSI line.
2. A patched Codex launcher/binary that calls that renderer from the TUI footer.

## Non-Goals

- Do not edit `statusline.sh`, `install.sh`, `configure.sh`, `uninstall.sh`, `tab-state.sh`, or `_lib_tab_state.sh`.
- Do not change Claude `~/.claude/settings.json`.
- Do not refactor the existing Claude renderer into a shared core in this phase.
- Do not overwrite the user's existing `codex` binary by default.
- Do not claim official Codex support for command-backed status lines.

## Architecture

### Renderer Contract

Create a Codex-specific renderer:

```bash
adapters/codex/statusline.sh --line
```

The command prints one line and exits quickly. It should be safe when Codex session metadata is missing, stale, or partially unreadable.

Data sources:

- `~/.codex/config.toml` for model, reasoning effort, sandbox, and approval defaults when easy to parse.
- `~/.codex/sessions/**/*.jsonl` for recent usage/rate-limit/session metadata when present.
- `git` and the current working directory for repository context.
- Existing `config.json` and `themes/*.json` for theme choices.

Unavailable telemetry renders as `--`, not as an error.

### Patch Surface

Create Codex-only install helpers:

```bash
adapters/codex/install-patched.sh
adapters/codex/uninstall-patched.sh
```

The installer should:

- detect the current `codex` path and version
- clone or update OpenAI Codex source into a cache/build directory
- apply a small patch that adds a `status_line_command` configuration key
- build a patched Codex binary
- install it as `~/.local/bin/codex-cyberpunk`
- avoid changing the global `codex` command unless explicitly requested later

The uninstaller should remove only Codex cyberpunk artifacts and leave Claude files alone.

### Config Integration

For patched Codex, write or document:

```toml
[tui]
status_line_command = "bash /absolute/path/to/adapters/codex/statusline.sh --line"
```

The helper must preserve existing `[tui].status_line` and unrelated Codex config. Removing the integration should remove only `status_line_command` when it points at this project.

## Testing

Use test-first implementation.

Required coverage:

- renderer prints a non-empty line with no Codex session logs
- renderer prints expected model/git/context/rate placeholders from fixtures
- config merge preserves unrelated TOML content
- install dry-run reports intended actions without writing binaries
- uninstall dry-run reports intended removals without touching Claude files

## Risks

Patched Codex is version-sensitive. Upstream source layout or TUI internals may change, so the installer must prefer explicit checks, dry-run output, and clear failure messages over best-effort mutation.
