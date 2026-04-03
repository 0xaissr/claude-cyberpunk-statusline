# cyberpunk-statusline

Themeable cyberpunk status line for Claude Code, with a p10k-style setup wizard.

Displays model, context usage, rate limits, directory, git branch, and time — all rendered in your terminal with true-color themes.

## Prerequisites

- **Claude Code** CLI or Desktop
- **jq** — `brew install jq` (macOS) / `apt install jq` (Linux)
- **Nerd Font** (optional, recommended) — for icons. [Download here](https://www.nerdfonts.com/)

## Installation

### 1. Add the marketplace

In Claude Code, run:

```
/plugin marketplace add 0xaissr/cyberpunk-statusline-marketplace
```

### 2. Install the plugin

```
/plugin install cyberpunk-statusline@cyberpunk-statusline-marketplace
```

Or use the interactive plugin manager (`/plugin` → **Discover** tab).

### 3. Activate

```
/reload-plugins
```

Or restart your Claude Code session.

### 4. Configure

```
/cyberpunk-statusline configure
```

The setup wizard will guide you through:

1. **Font detection** — Nerd Font / Unicode / ASCII
2. **Blocks** — choose which info blocks to display
3. **Spacing** — ultra-compact, compact, or normal
4. **Prompt style** — Classic (separators) or Rainbow (colored backgrounds)
5. **Separator / Head & Tail shapes** — customize segment appearance
6. **Bar width** — progress bar size for context/rate blocks
7. **Theme** — pick from 13 built-in themes with live preview

## Themes

| Theme | |
|---|---|
| blade-runner | catppuccin-mocha |
| dracula | gruvbox-dark |
| midnight-phantom | neon-classic |
| nord | one-dark |
| retrowave-chrome | rose-pine |
| synthwave-sunset | terminal-glitch |
| tokyo-night | |

You can also create custom themes — see `themes/custom-example/` for reference.

## Uninstall

Use the plugin manager:

```
/plugin
```

Navigate to the **Installed** tab, select cyberpunk-statusline, and remove it.

## Reinstall / Update

```
/cyberpunk-statusline reinstall
```

This clears the local cache. Restart Claude Code to re-fetch the latest version from GitHub.

## License

MIT
