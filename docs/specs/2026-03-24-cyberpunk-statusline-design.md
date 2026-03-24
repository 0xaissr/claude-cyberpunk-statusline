# cyberpunk-statusline Plugin Design Spec

## Overview

A Claude Code plugin that provides a themeable, cyberpunk-styled status line with a powerlevel10k-inspired interactive setup wizard. Users install the plugin, run `/cyberpunk-statusline configure`, and walk through a guided skill-driven flow to choose their theme, symbols, spacing, and layout.

## Goals

- **Extensible theme system** — community can contribute themes by submitting a single JSON file
- **Beginner-friendly wizard** — guided step-by-step configuration via Claude skill
- **Works everywhere** — symbol fallbacks from Nerd Font → Unicode → ASCII

## Architecture

### Hybrid Theme System (JSON-first + optional script override)

```
cyberpunk-statusline/
├── .claude-plugin/
│   └── plugin.json                  # plugin metadata
├── hooks/
│   ├── hooks.json                   # SessionStart hook
│   └── session-start.sh             # auto-configure statusLine setting
├── skills/
│   └── configure/
│       └── SKILL.md                 # wizard skill definition
├── scripts/
│   └── statusline.sh                # default rendering engine
├── themes/
│   ├── terminal-glitch.json         # Cyberpunk: 駭客終端
│   ├── neon-classic.json            # Cyberpunk: Night City 霓虹
│   ├── synthwave-sunset.json        # Cyberpunk: 復古合成波
│   ├── blade-runner.json            # Cyberpunk: 銀翼殺手控制室
│   ├── retrowave-chrome.json        # Cyberpunk: Tron 街機風
│   ├── dracula.json                 # Classic: Dracula
│   ├── tokyo-night.json             # Classic: Tokyo Night
│   ├── catppuccin-mocha.json        # Classic: Catppuccin Mocha
│   ├── rose-pine.json               # Classic: Rosé Pine
│   ├── nord.json                    # Classic: Nord
│   ├── one-dark.json                # Classic: One Dark
│   ├── gruvbox-dark.json            # Classic: Gruvbox Dark
│   └── custom-example/              # Example: custom theme with script override
│       ├── theme.json
│       └── render.sh
└── config.json                      # wizard output (user's choices)
```

**Theme resolution:**
1. Read `config.json` → get selected theme name
2. Check if `themes/{name}/` directory exists with `render.sh` → use custom renderer
3. Otherwise load `themes/{name}.json` → use default rendering engine

### Plugin Metadata

```json
{
  "name": "cyberpunk-statusline",
  "description": "Themeable cyberpunk status line with p10k-style setup wizard",
  "version": "1.0.0",
  "author": { "name": "0xaissr", "email": "0xaissr@gmail.com" }
}
```

### SessionStart Hook

`hooks/session-start.sh` runs on session start to:
- If `config.json` doesn't exist yet, output a reminder to run `/cyberpunk-statusline configure`
- Output current theme name and version info as session context

**Note:** The `statusLine.command` setting is configured **once during installation**, not on every session start. The wizard's final step writes the setting via `claude config set`. The SessionStart hook only provides informational context.

### Config File Location

`config.json` is stored in the plugin directory. The `statusline.sh` script resolves the plugin root from its own path:

```bash
PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$PLUGIN_DIR/config.json"
```

### stdin JSON Fields (verified)

Claude Code pipes the following JSON to the statusLine command's stdin:

```json
{
  "model": { "id": "...", "display_name": "Opus 4.6 (1M context)" },
  "context_window": { "used_percentage": 3, "remaining_percentage": 97, ... },
  "rate_limits": {
    "five_hour": { "used_percentage": 16, "resets_at": 1774335600 },
    "seven_day": { "used_percentage": 33, "resets_at": 1774580400 }
  },
  "workspace": { "current_dir": "/path/to/project", ... },
  "cost": { "total_cost_usd": 0.29, ... },
  ...
}
```

All 7 default blocks (`model`, `context`, `rate_5h`, `rate_7d`, `directory`, `git`, `time`) are populated from verified stdin fields.

## Theme JSON Schema

```json
{
  "schema_version": 1,
  "name": "Terminal Glitch",
  "description": "駭客終端 — 極暗底色配高對比霓虹",
  "author": "cyberpunk-statusline",
  "colors": {
    "bg_primary": "#020312",
    "bg_panel": "#252A3F",
    "accent_1": "#24F0FF",
    "accent_2": "#FF5C8A",
    "accent_3": "#FFE45E",
    "warning": "#FFA03C",
    "alert": "#FF3232",
    "separator": "#444444",
    "dim": "#666666"
  },
  "symbols": {
    "nerd": {
      "model": "󰚩", "context": "󰍛", "rate_5h": "", "rate_7d": "󰔟",
      "directory": "", "git": "", "time": "",
      "bar_filled": "█", "bar_empty": "░", "separator": "│"
    },
    "unicode": {
      "model": "⬡", "context": "◈", "rate_5h": "⚡", "rate_7d": "⟳",
      "directory": "⌁", "git": "⎇", "time": "◷",
      "bar_filled": "█", "bar_empty": "░", "separator": "│"
    },
    "ascii": {
      "model": "[M]", "context": "[C]", "rate_5h": "[!]", "rate_7d": "[~]",
      "directory": "[D]", "git": "[G]", "time": "[T]",
      "bar_filled": "#", "bar_empty": ".", "separator": "|"
    }
  },
  "blocks": {
    "model":     { "color": "accent_1", "bg": "bg_panel" },
    "context":   { "color": "accent_2", "bg": "bg_panel" },
    "rate_5h":   { "color": "accent_3", "bg": "bg_panel" },
    "rate_7d":   { "color": "accent_1", "bg": "bg_panel" },
    "directory": { "color": "accent_2", "bg": "bg_panel" },
    "git":       { "color": "accent_1", "bg": "bg_panel" },
    "time":      { "color": "accent_1", "bg": "bg_primary" }
  }
}
```

## User Config Schema (config.json)

Wizard output — saved to the plugin directory:

```json
{
  "theme": "terminal-glitch",
  "symbol_set": "unicode",
  "spacing": "normal",
  "separator": "│",
  "blocks": ["model", "context", "rate_5h", "rate_7d", "directory", "git", "time"],
  "bar_width": 10
}
```

### Config Fields

| Field | Values | Default | Description |
|-------|--------|---------|-------------|
| `theme` | theme name string | `"terminal-glitch"` | Selected theme |
| `symbol_set` | `"nerd"` / `"unicode"` / `"ascii"` | `"unicode"` | Symbol style |
| `spacing` | `"normal"` / `"compact"` / `"ultra-compact"` | `"normal"` | Display density |
| `separator` | `"│"` / `"/"` / `"·"` / `""` / `"›"` | `"│"` | Block separator |
| `blocks` | array of block names | all 7 blocks | Which blocks to show, in order |
| `bar_width` | integer 5-20 | `10` | Progress bar character width |

### Spacing Modes

- **normal** — symbol + label text + progress bar + percentage (e.g., `◈ CTX ██░░░░░░░░ 3%`)
- **compact** — symbol only + progress bar + percentage (e.g., `◈ ██░░░░░░░░ 3%`)
- **ultra-compact** — symbol + percentage only, no progress bar (e.g., `◈ 3%`)

### Rate Limit Reset Time

The `rate_5h` and `rate_7d` blocks additionally display the reset countdown. The `resets_at` field from stdin is a Unix timestamp. The rendering engine calculates time remaining and appends it:

- **normal** — `⚡ 5H ██░░░░░░░░ 16% ↻2h30m`
- **compact** — `⚡ ██░░░░░░░░ 16% ↻2h30m`
- **ultra-compact** — `⚡ 16% ↻2h30m`

If `resets_at` is in the past or missing, the reset countdown is omitted.

## Rendering Engine (statusline.sh)

### Input/Output

- **stdin**: JSON from Claude Code (model, context_window, rate_limits, workspace, etc.)
- **stdout**: Single line of ANSI-colored text

### Flow

```
stdin → jq parse → read config.json → resolve theme
  → has render.sh? → yes: source it
                   → no:  read theme.json → hex_to_ansi → assemble blocks
→ stdout
```

### Key Functions

```bash
# Hex color to ANSI true color (foreground)
hex_to_fg() {
  local hex="${1#\#}"
  printf '\033[38;2;%d;%d;%dm' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

# Hex color to ANSI true color (background)
hex_to_bg() {
  local hex="${1#\#}"
  printf '\033[48;2;%d;%d;%dm' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

# Build progress bar
make_bar() {
  local pct="$1" width="$2" filled_char="$3" empty_char="$4"
  local filled=$(awk "BEGIN{v=int($pct*$width/100+0.5); if(v>$width) v=$width; if(v<0) v=0; print v}")
  local empty=$(($width - $filled))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="$filled_char"; done
  for ((i=0; i<empty; i++)); do bar+="$empty_char"; done
  printf "%s" "$bar"
}

# Neon color with warning/alert thresholds
neon_colour() {
  local pct="$1" neon_hex="$2" warn_hex="$3" alert_hex="$4"
  local v=$(printf "%.0f" "$pct")
  if   [ "$v" -ge 80 ]; then hex_to_fg "$alert_hex"
  elif [ "$v" -ge 50 ]; then hex_to_fg "$warn_hex"
  else                       hex_to_fg "$neon_hex"
  fi
}
```

### Custom Renderer Interface

When a theme directory provides `render.sh`, it is sourced after the JSON input is parsed. The following variables are available:

- `$input` — raw JSON from Claude Code
- `$model`, `$used_pct`, `$five_pct`, `$week_pct`, `$cwd`, `$git_branch`, `$now` — parsed fields
- All functions from the default engine (`hex_to_fg`, `hex_to_bg`, `make_bar`, `neon_colour`)

The custom script must `echo -e` the final ANSI string to stdout.

## Wizard Skill (SKILL.md)

### Trigger

User runs `/cyberpunk-statusline configure`

### Flow (7 Steps)

```
Step 1: Symbol Test
  → Show test symbols, ask which display correctly
  → Auto-determine: nerd / unicode / ascii

Step 2: Theme Selection
  → Show all 12 built-in themes with descriptions
  → User picks one

Step 3: Color Adjustment (optional)
  → "Keep theme defaults?" or fine-tune accent colors
  → Most users skip this

Step 4: Block Selection
  → Which blocks to show? (model/ctx/5h/7d/dir/git/time)
  → Toggle on/off, reorder

Step 5: Symbol Style
  → Confirm symbol set from Step 1, or override
  → Nerd Font / Unicode / ASCII

Step 6: Spacing Mode
  → Normal / Compact / Ultra Compact

Step 7: Separator Style
  → Pipe │ / Slash / / Dot · / Space / Arrow ›
```

### Wizard Behavior

- Each step: Claude presents options, user picks, Claude updates config
- After final step: write `config.json`, confirm applied
- Can re-run anytime to change settings
- Skill instructs Claude to explain each option briefly

## Installation Flow

```
1. User: /plugin install cyberpunk-statusline
2. Plugin downloaded to ~/.claude/plugins/cache/
3. SessionStart hook fires → sets statusLine.command
4. Claude: "cyberpunk-statusline installed! Run /cyberpunk-statusline configure to set up."
5. User: /cyberpunk-statusline configure
6. Wizard walks through 7 steps
7. config.json written → statusline immediately reflects new settings
```

## Community Contribution

### Adding a New Theme

1. Create `{theme-name}.json` following the Theme JSON Schema
2. Submit PR to the plugin repository
3. Theme is automatically available in the wizard after next plugin update

### Adding a Custom Renderer Theme

1. Create `themes/{theme-name}/` directory
2. Add `theme.json` (colors/symbols) + `render.sh` (custom rendering logic)
3. `render.sh` must output a single ANSI-formatted line to stdout

## Built-in Themes (12)

### Cyberpunk Series

| Theme | bg_primary / bg_panel | Accent 1 | Accent 2 | Accent 3 | Vibe |
|-------|-----------|-----------|-----------|-----------|------|
| Terminal Glitch | `#020312` / `#252A3F` | `#24F0FF` | `#FF5C8A` | `#FFE45E` | 駭客終端 |
| Neon Classic | `#091833` / `#133E7C` | `#0ABDC6` | `#EA00D9` | `#711C91` | Night City 霓虹 |
| Synthwave Sunset | `#1a1225` / `#241B30` | `#FFD319` | `#FF2975` | `#8C1EFF` | 復古合成波 |
| Blade Runner Signal | `#0B0C10` / `#141726` | `#18E0FF` | `#FF3CF2` | `#F7FF4A` | 銀翼殺手控制室 |
| Retrowave Chrome | `#3C345C` / `#5C2C6D` | `#6DF1D8` | `#D30CB8` | `#B8AEC8` | Tron 街機風 |

### Classic Terminal Series

| Theme | bg_primary / bg_panel | Accent 1 | Accent 2 | Accent 3 | Source |
|-------|-----------|-----------|-----------|-----------|--------|
| Dracula | `#282A36` / `#44475A` | `#8BE9FD` | `#FF79C6` | `#BD93F9` | draculatheme.com |
| Tokyo Night | `#1A1B26` / `#24283B` | `#7AA2F7` | `#F7768E` | `#7DCFFF` | folke/tokyonight |
| Catppuccin Mocha | `#1E1E2E` / `#313244` | `#89B4FA` | `#F38BA8` | `#CBA6F7` | catppuccin.com |
| Rosé Pine | `#191724` / `#26233A` | `#9CCFD8` | `#EB6F92` | `#C4A7E7` | rosepinetheme.com |
| Nord | `#2E3440` / `#3B4252` | `#88C0D0` | `#BF616A` | `#EBCB8B` | nordtheme.com |
| One Dark | `#282C34` / `#3E4451` | `#61AFEF` | `#E06C75` | `#C678DD` | Atom |
| Gruvbox Dark | `#282828` / `#3C3836` | `#8EC07C` | `#FB4934` | `#FABD2F` | morhetz/gruvbox |

## Dependencies

- `jq` — JSON parsing (with fallback path detection for Homebrew)
- `awk` — floating point math
- Bash 4+ — for `$((  ))` and arrays
- True color terminal support (24-bit ANSI) — graceful degradation to 256-color not in scope for v1

## Out of Scope (v1)

- 256-color fallback (require true color terminal)
- Animated/blinking effects
- Multi-line status bar
- Auto-detect terminal color scheme to suggest matching theme
- Plugin marketplace listing (manual install first)
