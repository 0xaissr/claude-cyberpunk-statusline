# Codex Patched Footer

This is an experimental Codex-only path. It does not change the Claude Code
statusline, Claude installer, Claude settings, or Claude tab-state hooks.

## Current State

Implemented:

- `adapters/codex/statusline.sh --line` renders a one-line Codex status preview.
- `adapters/codex/lib-config.sh` can add or remove a patched
  `tui.status_line_command` key in Codex config.
- `adapters/codex/install-patched.sh --dry-run` reports the planned patched
  Codex install flow.
- `adapters/codex/uninstall-patched.sh --dry-run` reports the planned cleanup.
- `adapters/codex/patches/status-line-command.patch` documents the intended
  patch point.

Not implemented yet:

- Building a patched Codex binary.
- Replacing or shimming the user's `codex` command.
- Applying the patch to an upstream Codex source revision.

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

## Dry Run Installer

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

## Dry Run Uninstaller

```bash
bash adapters/codex/uninstall-patched.sh --dry-run
```

This prints the Codex-only artifacts that would be removed. Dry run does not
edit `~/.codex/config.toml`.

## Testing

Run the Codex-only test set:

```bash
for t in tests/adapters/codex/test-*.sh; do
  bash "$t" || exit 1
done
```

To confirm Claude-facing files are untouched:

```bash
git diff -- statusline.sh install.sh configure.sh uninstall.sh tab-state.sh _lib_tab_state.sh
```

Expected output: nothing.

## Recovery

Because this phase does not install a patched binary, recovery is currently just
removing generated Codex-only files from any future manual experiment:

```bash
rm -f ~/.local/bin/codex-cyberpunk
```

Do not remove or edit Claude settings for this Codex workflow.
