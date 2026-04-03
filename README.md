# cyberpunk-statusline

[English](README.md) | [繁體中文](docs/README.zh-TW.md)

Themeable cyberpunk status line for Claude Code, with a p10k-style setup wizard.

Displays model, context usage, rate limits, directory, git branch, and time — all rendered in your terminal with true-color themes.

## Prerequisites

- **Claude Code** CLI or Desktop
- **jq** — `brew install jq` (macOS) / `apt install jq` (Linux)
- **Nerd Font** (optional, recommended) — for icons. [Download here](https://www.nerdfonts.com/)

## Installation

### 1. Clone

```bash
git clone https://github.com/0xaissr/claude-cyberpunk-statusline.git ~/claude-cyberpunk-statusline
```

### 2. Install

```bash
cd ~/claude-cyberpunk-statusline && ./install.sh
```

This will:
- Check prerequisites (jq)
- Configure Claude Code's statusLine setting
- Launch the setup wizard (if first time)

### 3. Restart

Restart your Claude Code session to see the status line.

### Reconfigure

```bash
cd ~/claude-cyberpunk-statusline && ./configure.sh
```

The setup wizard will guide you through:

1. **Font detection** — Nerd Font / Unicode / ASCII
2. **Blocks** — choose which info blocks to display
3. **Spacing** — ultra-compact, compact, or normal
4. **Prompt style** — Classic (separators) or Rainbow (colored backgrounds)
5. **Separator / Head & Tail shapes** — customize segment appearance
6. **Bar width** — progress bar size for context/rate blocks
7. **Theme** — pick from 13 built-in themes with live preview

### Update

```bash
cd ~/claude-cyberpunk-statusline && git pull
```

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

```bash
cd ~/claude-cyberpunk-statusline && ./uninstall.sh
```

## License

MIT
