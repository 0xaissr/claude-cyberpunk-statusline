# Codex Patched Footer

This is an experimental Codex-only path. It does not change the Claude Code
statusline, Claude installer, Claude settings, or Claude tab-state hooks.

## Current State

Implemented:

- `adapters/codex/statusline.sh --line` renders a one-line Codex status preview.
- `adapters/codex/lib-config.sh` can add or remove a patched
  `tui.status_line_command` key in Codex config.
- `install-codex.sh` guides Codex setup, writes a Codex-specific theme config,
  and configures Codex's official built-in `tui.status_line` items by default.
- `adapters/codex/install-patched.sh` can clone Codex `rust-v0.142.5`, apply
  the local `status_line_command` patch, build a release binary, install it as
  `~/.local/bin/codex-cyberpunk`, and write Codex config.
- `adapters/codex/uninstall-patched.sh` removes `codex-cyberpunk` and removes
  only this project's `status_line_command` config.
- `adapters/codex/patches/status-line-command.patch` is an applyable patch for
  OpenAI Codex `rust-v0.142.5`.

Not implemented yet:

- A timeout around `status_line_command`; keep the renderer command fast.

## Preview the Renderer

From this repository:

```bash
bash adapters/codex/statusline.sh --line
```

The renderer reads Codex-local state from:

- `~/.codex/config.toml`
- `~/.codex/sessions/**/*.jsonl`
- the current git repository

Unavailable telemetry is rendered as `--`.

## Guided Installer

From this repository:

```bash
./install-codex.sh
```

This guides theme selection, writes `adapters/codex/config.json`, and writes
official `tui.status_line` items into `~/.codex/config.toml`. It does not clone
Codex, run Cargo, or install `codex-cyberpunk` by default.

For non-interactive setup:

```bash
./install-codex.sh --theme tokyo-night
```

This official path uses Codex's built-in status line item list. It does not
render the cyberpunk command output because official Codex does not currently
support `tui.status_line_command`.

To opt into the full cyberpunk patched-binary flow:

```bash
./install-codex.sh --patched --theme tokyo-night --alias
```

## Dry Run Low-Level Installer

```bash
bash adapters/codex/install-patched.sh --dry-run
```

This prints:

- current Codex binary path
- renderer command
- Codex source cache path
- patch file path
- planned `codex-cyberpunk` output path

Dry run does not write files.

## Install Patched Codex

```bash
bash adapters/codex/install-patched.sh
```

This writes:

- `~/.cache/cyberpunk-statusline/codex-source`
- `~/.local/bin/codex-cyberpunk`
- `~/.codex/config.toml` backup plus `tui.status_line_command`

The first build downloads Rust crates and can take several minutes. The
installer does not replace your existing `codex` command.

## Dry Run Uninstaller

```bash
bash adapters/codex/uninstall-patched.sh --dry-run
```

This prints the Codex-only artifacts that would be removed. Dry run does not
edit `~/.codex/config.toml`.

## Uninstall Patched Codex

```bash
bash adapters/codex/uninstall-patched.sh
```

This removes `~/.local/bin/codex-cyberpunk` and removes
`tui.status_line_command` only when it points at this project. Other Codex config
is preserved.

## Testing

Run the Codex-only test set:

```bash
for t in tests/adapters/codex/test-*.sh; do
  bash "$t" || exit 1
done
```

To confirm Claude-facing files are untouched:

```bash
git diff -- statusline.sh install-claude.sh configure.sh uninstall.sh tab-state.sh _lib_tab_state.sh
```

Expected output: nothing.

## Recovery

Recovery removes only generated Codex-only files:

```bash
rm -f ~/.local/bin/codex-cyberpunk
bash adapters/codex/uninstall-patched.sh
```

Do not remove or edit Claude settings for this Codex workflow.
