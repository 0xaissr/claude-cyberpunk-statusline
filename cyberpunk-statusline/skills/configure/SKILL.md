---
name: cyberpunk-statusline:configure
description: Configure cyberpunk-statusline theme, symbols, spacing, and layout. Use when user runs /cyberpunk-statusline configure or asks to change their status line theme.
---

# cyberpunk-statusline Configuration Wizard

You are guiding the user through configuring their Claude Code status line theme. Walk through each step one at a time, wait for the user's response before moving to the next step.

## Setup

Read the current config if it exists:
- Config path: `${CLAUDE_PLUGIN_ROOT}/config.json`
- Themes directory: `${CLAUDE_PLUGIN_ROOT}/themes/`

List available themes by reading the themes directory.

## Step 1: Symbol Test

Show these symbols and ask if they display correctly:

**Test A (Nerd Font):** 󰚩 󰍛  󰔟    
**Test B (Unicode):** ⬡ ◈ ⚡ ⟳ ⌁ ⎇ ◷ █ ░
**Test C (ASCII):** [M] [C] [!] [~] [D] [G] [T] # .

Ask: "Which set displays correctly? (A/B/C)"
- If A works → recommend `nerd`, but still let them choose later
- If B works → recommend `unicode`
- If neither → default to `ascii`

Save the result for Step 5.

## Step 2: Theme Selection

List all available themes with their descriptions. Read each theme JSON to get `name` and `description`. Group them:

**Cyberpunk Series:**
1. Terminal Glitch — 駭客終端
2. Neon Classic — Night City 霓虹
3. Synthwave Sunset — 復古合成波
4. Blade Runner Signal — 銀翼殺手控制室
5. Retrowave Chrome — Tron 街機風

**Classic Terminal Series:**
6. Dracula
7. Tokyo Night
8. Catppuccin Mocha
9. Rosé Pine
10. Nord
11. One Dark
12. Gruvbox Dark

Ask the user to pick one by number or name.

## Step 3: Block Selection

Show the available blocks:
- `model` — Model name (e.g., Opus 4.6)
- `context` — Context window usage %
- `rate_5h` — 5-hour rate limit % + reset countdown
- `rate_7d` — 7-day rate limit % + reset countdown
- `directory` — Current working directory
- `git` — Git branch name
- `time` — Current time

Default: all 7 enabled in this order.

Ask: "Which blocks do you want? List the ones to keep (or say 'all')."
Also ask if they want to reorder.

## Step 4: Symbol Style

Based on Step 1 result, confirm the recommended symbol set:
- **Nerd Font** — full icons (requires Nerd Font installed)
- **Unicode** — standard symbols (works in most terminals)
- **ASCII** — plain text (works everywhere)

Ask: "Use [recommended] symbols, or choose differently?"

## Step 5: Spacing Mode

Show examples for each mode (use the selected theme's colors):
- **Normal** — `◈ CTX ██░░░░░░░░ 3%` (symbol + label + bar + %)
- **Compact** — `◈ ██░░░░░░░░ 3%` (symbol + bar + %)
- **Ultra Compact** — `◈ 3%` (symbol + % only)

Ask: "Which spacing mode? (normal/compact/ultra-compact)"

## Step 6: Prompt Style

Ask: "Choose your prompt style:"

- **Classic** — each block has its own background, separated by `│` or other character
- **Rainbow** — Powerline 風格，每個 block 有獨立底色 + 箭頭 separator（需要 Nerd Font）

If they choose **Rainbow**, ask for head/tail shape:
- **Sharp:** `` / `` — 標準 Powerline 箭頭
- **Rounded:** `` / `` — 圓角
- **Slanted:** `` / `` — 斜切

If they choose **Classic**, ask for separator style:
- **Pipe:** `segment │ segment`
- **Slash:** `segment / segment`
- **Dot:** `segment · segment`
- **Space:** `segment  segment`
- **Arrow:** `segment › segment`

## Step 7: Time Format

Ask: "Choose time format:"
- **24h** — `14:30:05`
- **24h-no-sec** — `14:30`
- **12h** — `02:30:05 PM`
- **12h-no-sec** — `2:30 PM`

Default: `24h`

## Finalize

After all steps, build the config object and write it using the Write tool.

For **Classic** style:
```json
{
  "theme": "<selected>",
  "symbol_set": "<selected>",
  "spacing": "<selected>",
  "style": "classic",
  "separator": "<selected>",
  "blocks": ["model", "context", "rate_5h", "rate_7d", "directory", "git", "time"],
  "bar_width": 10,
  "time_format": "<selected>"
}
```

For **Rainbow** style:
```json
{
  "theme": "<selected>",
  "symbol_set": "<selected>",
  "spacing": "<selected>",
  "style": "rainbow",
  "separator": "",
  "head": "<sharp|rounded|slanted>",
  "tail": "<sharp|rounded|slanted>",
  "blocks": ["model", "context", "rate_5h", "rate_7d", "directory", "git", "time"],
  "bar_width": 10,
  "time_format": "<selected>"
}
```

Write to: `${CLAUDE_PLUGIN_ROOT}/config.json`

Then configure the statusLine setting so Claude Code uses this plugin's script. You MUST resolve `${CLAUDE_PLUGIN_ROOT}` to its actual absolute path before running the command — do NOT pass the variable literal. Run:

```bash
claude config set -g statusLine "{\"type\":\"command\",\"command\":\"bash \\\"${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh\\\"\"}"
```

Tell the user: "Done! Your status line is now configured. Restart the session to see the new theme. Run `/cyberpunk-statusline configure` anytime to change settings."
