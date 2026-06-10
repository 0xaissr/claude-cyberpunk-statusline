# cyberpunk-statusline

[English](README.md) | [繁體中文](docs/README.zh-TW.md)

Themeable cyberpunk status line for Claude Code, with a p10k-style setup wizard.

Displays model, context usage, rate limits, daily cost, directory, git branch, and time — all rendered in your terminal with true-color themes.

![overview](docs/overview.png)

## Prerequisites

- **Claude Code** CLI or Desktop
- **jq** — `brew install jq` (macOS) / `apt install jq` (Linux)
- **Nerd Font** (optional, recommended) — for icons. [Download here](https://www.nerdfonts.com/)
- **ccusage** (optional) — for accurate daily cost tracking. `npm i -g ccusage`

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
3. **Spacing & bar style** — ultra-compact, compact, or normal + progress bar shape (■□, ●○, ◆◇, etc.)
4. **Prompt style** — Rainbow (colored backgrounds) or Classic (separators)
5. **Separator / Head & Tail shapes** — customize segment appearance
6. **Time format** — 24h / 12h / no seconds
7. **Theme** — pick from 13 built-in themes with live preview

### Available Blocks

| Block | Description |
|---|---|
| model | Model name (e.g., Opus 4.6) |
| context | Context window usage % |
| rate_5h | 5-hour rate limit % |
| rate_7d | 7-day rate limit % |
| spend | Monthly spend for Enterprise/quota accounts (replaces rate blocks) |
| cost | Daily cost across all sessions |
| directory | Working directory |
| git | Git branch |
| time | Current time |

The **cost** block shows today's total spending across all Claude models and sessions. It uses [ccusage](https://github.com/ryoppippi/ccusage) for accurate tracking if installed, otherwise falls back to built-in JSONL calculation. Data is cached and refreshed every 5 minutes in the background.

#### Enterprise / Quota Account: Spend Block

When the statusline detects an **Enterprise or quota-based Claude account** (i.e. no personal rate limits exist), the `rate_5h` and `rate_7d` blocks are automatically replaced with a **spend block** showing monthly usage:

```
$122/$500 24% ↻21d
```

- **`$used/$limit`** — amount spent this month vs. your quota limit
- **`pct%`** — percentage of quota consumed
- **`↻Xd`** — days until the quota resets (1st of next month)

If the usage data cannot be fetched, the block displays `$--` and the statusline never blocks.

Data is fetched via the same usage endpoint that Claude Code itself uses. The script reads only your **local OAuth credentials** to query your own usage — no data is sent to any third party. Results are cached for 60 seconds and refreshed in the background.

#### `account_type` Setting

You can override the automatic detection with the `account_type` option in `config.json`:

| Value | Behavior |
|---|---|
| `auto` (default) | Detect account type automatically; show spend block for Enterprise/quota accounts, rate blocks otherwise |
| `subscription` | Force-show `rate_5h` / `rate_7d` blocks (personal Pro/Max plan) |
| `quota` | Force-show spend block (Enterprise/quota plan) |

### Preview & Edit Themes

```bash
# Preview all themes
cd ~/claude-cyberpunk-statusline && ./configure-theme.sh

# Edit a specific theme (interactive color editor with live preview)
cd ~/claude-cyberpunk-statusline && ./configure-theme.sh tokyo-night
```

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
