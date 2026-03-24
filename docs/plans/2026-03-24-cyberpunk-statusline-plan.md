# cyberpunk-statusline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Claude Code plugin with 12 themed status lines, a hybrid theme engine, and a p10k-style wizard skill.

**Architecture:** Single bash rendering engine reads user config + theme JSON to produce ANSI output. Themes are JSON files (with optional script override). Configuration wizard is a Claude skill that guides users through 7 steps.

**Tech Stack:** Bash, jq, ANSI true color, Claude Code plugin system (hooks + skills)

**Spec:** `docs/specs/2026-03-24-cyberpunk-statusline-design.md`

**Project root:** `/Users/scissor.lee/Documents/VibeCoding/cyberpunk-statusline/`

**Test data:** Use `/tmp/statusline-debug.json` as sample Claude Code stdin JSON (already exists from earlier debugging).

---

## File Structure

```
cyberpunk-statusline/
├── .claude-plugin/
│   └── plugin.json
├── hooks/
│   ├── hooks.json
│   └── session-start
├── skills/
│   └── configure/
│       └── SKILL.md
├── scripts/
│   └── statusline.sh
├── themes/
│   ├── terminal-glitch.json
│   ├── neon-classic.json
│   ├── synthwave-sunset.json
│   ├── blade-runner.json
│   ├── retrowave-chrome.json
│   ├── dracula.json
│   ├── tokyo-night.json
│   ├── catppuccin-mocha.json
│   ├── rose-pine.json
│   ├── nord.json
│   ├── one-dark.json
│   ├── gruvbox-dark.json
│   └── custom-example/
│       ├── theme.json
│       └── render.sh
├── tests/
│   ├── test-statusline.sh
│   └── sample-input.json
├── config.json
├── README.md
└── docs/  (already exists)
```

---

### Task 1: Plugin Scaffolding

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `hooks/hooks.json`
- Create: `hooks/session-start`

- [ ] **Step 1: Create plugin.json**

```json
{
  "name": "cyberpunk-statusline",
  "description": "Themeable cyberpunk status line with p10k-style setup wizard",
  "version": "1.0.0",
  "author": { "name": "0xaissr", "email": "0xaissr@gmail.com" },
  "license": "MIT",
  "keywords": ["statusline", "cyberpunk", "themes", "terminal"]
}
```

- [ ] **Step 2: Create hooks.json**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/session-start\"",
            "async": false
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 3: Create session-start hook script**

```bash
#!/usr/bin/env bash
# SessionStart hook — outputs config status as context for Claude
set -euo pipefail

PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CONFIG="$PLUGIN_DIR/config.json"
JQ=$(command -v jq 2>/dev/null || echo "/opt/homebrew/bin/jq")

if [ ! -f "$CONFIG" ]; then
  msg="cyberpunk-statusline is installed but not configured. Run /cyberpunk-statusline configure to set up your theme."
else
  theme=$("$JQ" -r '.theme // "unknown"' "$CONFIG" 2>/dev/null || echo "unknown")
  msg="cyberpunk-statusline active (theme: $theme). Run /cyberpunk-statusline configure to change."
fi

# Escape for JSON
msg_escaped=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\n/\\n/g')

cat <<EOJSON
{"hookSpecificOutput":{"additionalContext":"$msg_escaped"}}
EOJSON
```

- [ ] **Step 4: Make session-start executable**

Run: `chmod +x hooks/session-start`

- [ ] **Step 5: Verify plugin structure**

Run: `ls -la .claude-plugin/ hooks/`
Expected: `plugin.json`, `hooks.json`, `session-start` (executable)

- [ ] **Step 6: Commit**

```bash
git add .claude-plugin/ hooks/
git commit -m "feat: plugin 基本架構 — plugin.json, hooks, session-start"
```

---

### Task 2: Test Infrastructure + Sample Data

**Files:**
- Create: `tests/sample-input.json`
- Create: `tests/test-statusline.sh`

- [ ] **Step 1: Create sample stdin JSON for testing**

Copy from verified data, create `tests/sample-input.json`:

```json
{
  "session_id": "test-session",
  "model": { "id": "claude-opus-4-6", "display_name": "Opus 4.6 (1M context)" },
  "workspace": { "current_dir": "/Users/test/project" },
  "context_window": { "used_percentage": 3, "remaining_percentage": 97 },
  "rate_limits": {
    "five_hour": { "used_percentage": 16, "resets_at": 1774335600 },
    "seven_day": { "used_percentage": 33, "resets_at": 1774580400 }
  }
}
```

- [ ] **Step 2: Create test runner script**

`tests/test-statusline.sh` — validates that `statusline.sh` produces output for every theme:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUSLINE="$PROJECT_DIR/scripts/statusline.sh"
SAMPLE="$SCRIPT_DIR/sample-input.json"
PASS=0
FAIL=0

echo "=== cyberpunk-statusline test suite ==="

# Test 1: statusline.sh exists and is executable
test_exists() {
  if [ -x "$STATUSLINE" ]; then
    echo "PASS: statusline.sh is executable"
    ((PASS++))
  else
    echo "FAIL: statusline.sh not found or not executable"
    ((FAIL++))
  fi
}

# Test 2: produces non-empty output with default config
test_default_output() {
  local output
  output=$(cat "$SAMPLE" | bash "$STATUSLINE" 2>/dev/null)
  if [ -n "$output" ]; then
    echo "PASS: produces output with default config"
    ((PASS++))
  else
    echo "FAIL: empty output with default config"
    ((FAIL++))
  fi
}

# Test 3: every built-in theme JSON is valid
test_theme_json() {
  local jq_cmd
  jq_cmd=$(command -v jq 2>/dev/null || echo "/opt/homebrew/bin/jq")
  for theme_file in "$PROJECT_DIR"/themes/*.json; do
    local name
    name=$(basename "$theme_file" .json)
    if "$jq_cmd" . "$theme_file" > /dev/null 2>&1; then
      echo "PASS: $name.json is valid JSON"
      ((PASS++))
    else
      echo "FAIL: $name.json is invalid JSON"
      ((FAIL++))
    fi
  done
}

# Test 4: each theme produces output
test_each_theme() {
  local jq_cmd config_tmp
  jq_cmd=$(command -v jq 2>/dev/null || echo "/opt/homebrew/bin/jq")
  config_tmp=$(mktemp)
  for theme_file in "$PROJECT_DIR"/themes/*.json; do
    local name
    name=$(basename "$theme_file" .json)
    # Write temp config
    cat > "$config_tmp" <<EOF
{"theme":"$name","symbol_set":"unicode","spacing":"normal","separator":"│","blocks":["model","context","rate_5h","rate_7d","directory","git","time"],"bar_width":10}
EOF
    # Run with temp config
    local output
    output=$(cat "$SAMPLE" | CONFIG_OVERRIDE="$config_tmp" bash "$STATUSLINE" 2>/dev/null)
    if [ -n "$output" ]; then
      echo "PASS: theme '$name' produces output"
      ((PASS++))
    else
      echo "FAIL: theme '$name' produces empty output"
      ((FAIL++))
    fi
  done
  rm -f "$config_tmp"
}

# Test 5: compact and ultra-compact spacing
test_spacing_modes() {
  local config_tmp
  config_tmp=$(mktemp)
  for mode in "compact" "ultra-compact"; do
    cat > "$config_tmp" <<EOF
{"theme":"terminal-glitch","symbol_set":"unicode","spacing":"$mode","separator":"│","blocks":["model","context","rate_5h","rate_7d"],"bar_width":10}
EOF
    local output
    output=$(cat "$SAMPLE" | CONFIG_OVERRIDE="$config_tmp" bash "$STATUSLINE" 2>/dev/null)
    if [ -n "$output" ]; then
      echo "PASS: spacing '$mode' produces output"
      ((PASS++))
    else
      echo "FAIL: spacing '$mode' produces empty output"
      ((FAIL++))
    fi
  done
  rm -f "$config_tmp"
}

# Run all tests
test_exists
test_default_output
test_theme_json
test_each_theme
test_spacing_modes

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

- [ ] **Step 3: Make test script executable**

Run: `chmod +x tests/test-statusline.sh`

- [ ] **Step 4: Commit**

```bash
git add tests/
git commit -m "test: 測試架構 — sample input + test runner"
```

---

### Task 3: Default Config + First Theme JSON (Terminal Glitch)

**Files:**
- Create: `config.json`
- Create: `themes/terminal-glitch.json`

- [ ] **Step 1: Create default config.json**

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

- [ ] **Step 2: Create terminal-glitch.json theme**

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
      "bar_filled": "█", "bar_empty": "░"
    },
    "unicode": {
      "model": "⬡", "context": "◈", "rate_5h": "⚡", "rate_7d": "⟳",
      "directory": "⌁", "git": "⎇", "time": "◷",
      "bar_filled": "█", "bar_empty": "░"
    },
    "ascii": {
      "model": "[M]", "context": "[C]", "rate_5h": "[!]", "rate_7d": "[~]",
      "directory": "[D]", "git": "[G]", "time": "[T]",
      "bar_filled": "#", "bar_empty": "."
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

- [ ] **Step 3: Verify theme JSON is valid**

Run: `jq . themes/terminal-glitch.json > /dev/null && echo "valid"`
Expected: `valid`

- [ ] **Step 4: Commit**

```bash
git add config.json themes/terminal-glitch.json
git commit -m "feat: 預設設定 + Terminal Glitch 主題"
```

---

### Task 4: Rendering Engine (statusline.sh)

**Files:**
- Create: `scripts/statusline.sh`

This is the core of the plugin. It reads stdin JSON from Claude Code, loads config + theme, and outputs a single ANSI-colored line.

- [ ] **Step 1: Create statusline.sh**

```bash
#!/usr/bin/env bash
# ╔══════════════════════════════════════════╗
# ║  cyberpunk-statusline rendering engine   ║
# ╚══════════════════════════════════════════╝

# ── Read stdin ─────────────────────────────────────────────────────────────
input=$(cat)

# ── Resolve paths ──────────────────────────────────────────────────────────
PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG_OVERRIDE:-$PLUGIN_DIR/config.json}"
JQ=$(command -v jq 2>/dev/null || echo "/opt/homebrew/bin/jq")
if ! "$JQ" --version >/dev/null 2>&1; then
  echo "cyberpunk-statusline: jq is required but not found"
  exit 0
fi
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# ── Helpers ────────────────────────────────────────────────────────────────
hex_to_fg() {
  local hex="${1#\#}"
  printf '\033[38;2;%d;%d;%dm' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

hex_to_bg() {
  local hex="${1#\#}"
  printf '\033[48;2;%d;%d;%dm' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

make_bar() {
  local pct="${1:-0}" width="${2:-10}" filled_char="${3:-█}" empty_char="${4:-░}"
  local filled=$(awk "BEGIN{v=int($pct*$width/100+0.5); if(v>$width) v=$width; if(v<0) v=0; print v}")
  local empty=$(($width - $filled))
  local bar=""
  local i
  for ((i=0; i<filled; i++)); do bar+="$filled_char"; done
  for ((i=0; i<empty; i++)); do bar+="$empty_char"; done
  printf "%s" "$bar"
}

neon_colour() {
  local pct="${1:-0}" neon_hex="$2" warn_hex="$3" alert_hex="$4"
  local v=$(printf "%.0f" "$pct" 2>/dev/null || echo 0)
  if   [ "$v" -ge 80 ]; then hex_to_fg "$alert_hex"
  elif [ "$v" -ge 50 ]; then hex_to_fg "$warn_hex"
  else                       hex_to_fg "$neon_hex"
  fi
}

# ── Load config ────────────────────────────────────────────────────────────
if [ ! -f "$CONFIG" ]; then
  echo "cyberpunk-statusline: run /cyberpunk-statusline configure"
  exit 0
fi

cfg_theme=$("$JQ" -r '.theme // "terminal-glitch"' "$CONFIG")
cfg_symbols=$("$JQ" -r '.symbol_set // "unicode"' "$CONFIG")
cfg_spacing=$("$JQ" -r '.spacing // "normal"' "$CONFIG")
cfg_separator=$("$JQ" -r '.separator // "│"' "$CONFIG")
cfg_bar_width=$("$JQ" -r '.bar_width // 10' "$CONFIG")
cfg_blocks=$("$JQ" -r '.blocks // ["model","context","rate_5h","rate_7d","directory","git","time"] | .[]' "$CONFIG")

# ── Resolve theme ──────────────────────────────────────────────────────────
THEME_DIR="$PLUGIN_DIR/themes"

# Check for custom renderer (directory with render.sh)
if [ -d "$THEME_DIR/$cfg_theme" ] && [ -f "$THEME_DIR/$cfg_theme/render.sh" ]; then
  THEME_FILE="$THEME_DIR/$cfg_theme/theme.json"
else
  THEME_FILE="$THEME_DIR/$cfg_theme.json"
fi

if [ ! -f "$THEME_FILE" ]; then
  echo "cyberpunk-statusline: theme '$cfg_theme' not found"
  exit 0
fi

# ── Read theme colors ─────────────────────────────────────────────────────
color() { "$JQ" -r ".colors.$1 // \"#888888\"" "$THEME_FILE"; }

C_BG_PRIMARY=$(color bg_primary)
C_BG_PANEL=$(color bg_panel)
C_ACCENT_1=$(color accent_1)
C_ACCENT_2=$(color accent_2)
C_ACCENT_3=$(color accent_3)
C_WARNING=$(color warning)
C_ALERT=$(color alert)
C_SEP=$(color separator)
C_DIM=$(color dim)

# ── Read theme symbols ────────────────────────────────────────────────────
sym() { "$JQ" -r ".symbols.$cfg_symbols.$1 // \"?\"" "$THEME_FILE"; }

S_MODEL=$(sym model)
S_CTX=$(sym context)
S_5H=$(sym rate_5h)
S_7D=$(sym rate_7d)
S_DIR=$(sym directory)
S_GIT=$(sym git)
S_TIME=$(sym time)
S_BAR_FILLED=$(sym bar_filled)
S_BAR_EMPTY=$(sym bar_empty)

# ── Read block color mappings ─────────────────────────────────────────────
block_color() {
  local ref=$("$JQ" -r ".blocks.$1.color // \"accent_1\"" "$THEME_FILE")
  color "$ref"
}
block_bg() {
  local ref=$("$JQ" -r ".blocks.$1.bg // \"bg_panel\"" "$THEME_FILE")
  color "$ref"
}

# ── Parse stdin JSON ──────────────────────────────────────────────────────
model=$(echo "$input" | "$JQ" -r '.model.display_name // "UNKNOWN"')
used_pct=$(echo "$input" | "$JQ" -r '.context_window.used_percentage // empty')
five_pct=$(echo "$input" | "$JQ" -r 'if (.rate_limits.five_hour.used_percentage | type) == "number" then .rate_limits.five_hour.used_percentage else empty end')
five_reset=$(echo "$input" | "$JQ" -r '.rate_limits.five_hour.resets_at // empty')
week_pct=$(echo "$input" | "$JQ" -r 'if (.rate_limits.seven_day.used_percentage | type) == "number" then .rate_limits.seven_day.used_percentage else empty end')
week_reset=$(echo "$input" | "$JQ" -r '.rate_limits.seven_day.resets_at // empty')
cwd=$(echo "$input" | "$JQ" -r '.workspace.current_dir // .cwd // "?"')
now=$(date +"%H:%M:%S")
git_branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || true)

# ── Custom renderer check ─────────────────────────────────────────────────
if [ -d "$THEME_DIR/$cfg_theme" ] && [ -f "$THEME_DIR/$cfg_theme/render.sh" ]; then
  source "$THEME_DIR/$cfg_theme/render.sh"
  exit 0
fi

# ── Reset countdown helper ─────────────────────────────────────────────────
format_countdown() {
  local resets_at="$1"
  if [ -z "$resets_at" ]; then return; fi
  local now_ts=$(date +%s)
  local diff=$(( resets_at - now_ts ))
  if [ "$diff" -le 0 ]; then return; fi
  local hours=$(( diff / 3600 ))
  local mins=$(( (diff % 3600) / 60 ))
  if [ "$hours" -gt 0 ]; then
    printf '↻%dh%02dm' "$hours" "$mins"
  else
    printf '↻%dm' "$mins"
  fi
}

# ── Build separator ────────────────────────────────────────────────────────
SEP_FG=$(hex_to_fg "$C_SEP")
SEP=" ${SEP_FG}${cfg_separator}${RESET} "

# ── Block renderers ────────────────────────────────────────────────────────
render_block_model() {
  local fg=$(hex_to_fg "$(block_color model)")
  local bg=$(hex_to_bg "$(block_bg model)")
  echo -n "${bg}${fg}${BOLD} ${S_MODEL} ${model} ${RESET}"
}

render_pct_block() {
  local block_name="$1" symbol="$2" label="$3" pct="$4" resets_at="${5:-}"
  local fg_hex=$(block_color "$block_name")
  local bg_hex=$(block_bg "$block_name")
  local fg=$(hex_to_fg "$fg_hex")
  local bg=$(hex_to_bg "$bg_hex")
  local bar_bg=$(hex_to_bg "$C_BG_PRIMARY")
  local dim_fg=$(hex_to_fg "$C_DIM")

  if [ -z "$pct" ]; then
    echo -n "${bg}${fg}${BOLD} ${symbol} ${label} ${RESET} ${DIM}--${RESET}"
    return
  fi

  local pct_int=$(printf "%.0f" "$pct")
  local col=$(neon_colour "$pct_int" "$fg_hex" "$C_WARNING" "$C_ALERT")
  local countdown=$(format_countdown "$resets_at")
  local reset_str=""
  if [ -n "$countdown" ]; then
    reset_str=" ${dim_fg}${countdown}${RESET}"
  fi

  case "$cfg_spacing" in
    ultra-compact)
      echo -n "${bar_bg}${col} ${symbol} ${BOLD}${pct_int}%${reset_str} ${RESET}"
      ;;
    compact)
      local bar=$(make_bar "$pct_int" "$cfg_bar_width" "$S_BAR_FILLED" "$S_BAR_EMPTY")
      echo -n "${bg}${fg}${BOLD} ${symbol} ${RESET}${bar_bg}${col} ${bar} ${BOLD}${pct_int}%${reset_str} ${RESET}"
      ;;
    *)
      local bar=$(make_bar "$pct_int" "$cfg_bar_width" "$S_BAR_FILLED" "$S_BAR_EMPTY")
      echo -n "${bg}${fg}${BOLD} ${symbol} ${label} ${RESET}${bar_bg}${col} ${bar} ${BOLD}${pct_int}%${reset_str} ${RESET}"
      ;;
  esac
}

render_block_context()  { render_pct_block "context" "$S_CTX" "CTX" "$used_pct"; }
render_block_rate_5h()  { render_pct_block "rate_5h" "$S_5H"  "5H"  "$five_pct" "$five_reset"; }
render_block_rate_7d()  { render_pct_block "rate_7d" "$S_7D"  "7D"  "$week_pct" "$week_reset"; }

render_block_directory() {
  local fg=$(hex_to_fg "$(block_color directory)")
  local bg=$(hex_to_bg "$(block_bg directory)")
  local short_dir=$(echo "$cwd" | sed "s|$HOME|~|")
  echo -n "${bg}${fg}${BOLD} ${S_DIR} ${short_dir} ${RESET}"
}

render_block_git() {
  local fg=$(hex_to_fg "$(block_color git)")
  local bg=$(hex_to_bg "$(block_bg git)")
  if [ -n "$git_branch" ]; then
    echo -n "${bg}${fg}${BOLD} ${S_GIT} ${git_branch} ${RESET}"
  else
    local dim_fg=$(hex_to_fg "$C_DIM")
    local dim_bg=$(hex_to_bg "$C_BG_PRIMARY")
    echo -n "${dim_bg}${dim_fg} ${S_GIT} no-git ${RESET}"
  fi
}

render_block_time() {
  local fg=$(hex_to_fg "$(block_color time)")
  local bg=$(hex_to_bg "$(block_bg time)")
  echo -n "${bg}${fg} ${S_TIME} ${now} ${RESET}"
}

# ── Assemble ───────────────────────────────────────────────────────────────
output=""
first=true
for block in $cfg_blocks; do
  if [ "$first" = true ]; then
    first=false
  else
    output+="$SEP"
  fi
  case "$block" in
    model)     output+=$(render_block_model) ;;
    context)   output+=$(render_block_context) ;;
    rate_5h)   output+=$(render_block_rate_5h) ;;
    rate_7d)   output+=$(render_block_rate_7d) ;;
    directory) output+=$(render_block_directory) ;;
    git)       output+=$(render_block_git) ;;
    time)      output+=$(render_block_time) ;;
  esac
done

echo -e "$output"
```

- [ ] **Step 2: Make executable**

Run: `chmod +x scripts/statusline.sh`

- [ ] **Step 3: Test with sample input**

Run: `cat tests/sample-input.json | bash scripts/statusline.sh`
Expected: Non-empty ANSI output with Terminal Glitch colors

- [ ] **Step 4: Test with empty stdin (graceful failure)**

Run: `echo '{}' | bash scripts/statusline.sh`
Expected: Output with "UNKNOWN" model and "--" for missing percentages, no crash

- [ ] **Step 5: Commit**

```bash
git add scripts/
git commit -m "feat: 渲染引擎 statusline.sh — 支援主題、間距、符號"
```

---

### Task 5: Remaining 11 Theme JSON Files

**Files:**
- Create: `themes/neon-classic.json`
- Create: `themes/synthwave-sunset.json`
- Create: `themes/blade-runner.json`
- Create: `themes/retrowave-chrome.json`
- Create: `themes/dracula.json`
- Create: `themes/tokyo-night.json`
- Create: `themes/catppuccin-mocha.json`
- Create: `themes/rose-pine.json`
- Create: `themes/nord.json`
- Create: `themes/one-dark.json`
- Create: `themes/gruvbox-dark.json`

All theme files follow the exact same schema as `terminal-glitch.json`. The only differences are `name`, `description`, `author`, and `colors`. The `symbols` and `blocks` sections are identical across all themes (same structure, colors reference theme-specific color keys).

Color values for each theme are documented in the spec at lines 317-335.

Each theme needs these color keys:
- `bg_primary` — darkest background (bar area)
- `bg_panel` — panel/label background
- `accent_1` — primary neon (model, 7d, git, time)
- `accent_2` — secondary neon (ctx, directory)
- `accent_3` — tertiary neon (5h)
- `warning` — 50%+ threshold color
- `alert` — 80%+ threshold color
- `separator` — separator character color
- `dim` — muted text color

- [ ] **Step 1: Create all 11 theme JSON files**

Create each file following the template. Use the color values from the spec. Set `warning` and `alert` per-theme as follows:
- Cyberpunk themes: `warning: "#FFA03C"`, `alert: "#FF3232"`
- Dracula: `warning: "#FFB86C"`, `alert: "#FF5555"`
- Tokyo Night: `warning: "#E0AF68"`, `alert: "#F7768E"`
- Catppuccin: `warning: "#FAB387"`, `alert: "#F38BA8"`
- Rosé Pine: `warning: "#F6C177"`, `alert: "#EB6F92"`
- Nord: `warning: "#D08770"`, `alert: "#BF616A"`
- One Dark: `warning: "#D19A66"`, `alert: "#E06C75"`
- Gruvbox: `warning: "#FE8019"`, `alert: "#FB4934"`

Set `separator` and `dim` per-theme to match the theme's muted tones (use the bg colors for reference, slightly lighter).

- [ ] **Step 2: Validate all theme JSON files**

Run: `for f in themes/*.json; do jq . "$f" > /dev/null && echo "OK: $f" || echo "FAIL: $f"; done`
Expected: All OK

- [ ] **Step 3: Run test suite**

Run: `bash tests/test-statusline.sh`
Expected: All tests pass, each theme produces output

- [ ] **Step 4: Commit**

```bash
git add themes/
git commit -m "feat: 新增 11 個主題 — Cyberpunk + 經典終端系列"
```

---

### Task 6: Custom Theme Example

**Files:**
- Create: `themes/custom-example/theme.json`
- Create: `themes/custom-example/render.sh`

- [ ] **Step 1: Create custom-example theme.json**

A minimal theme JSON — same schema, just with unique colors to demonstrate:

```json
{
  "schema_version": 1,
  "name": "Custom Example",
  "description": "Example custom theme with script override — use as template",
  "author": "community",
  "colors": {
    "bg_primary": "#0D1117",
    "bg_panel": "#161B22",
    "accent_1": "#58A6FF",
    "accent_2": "#F78166",
    "accent_3": "#3FB950",
    "warning": "#D29922",
    "alert": "#F85149",
    "separator": "#30363D",
    "dim": "#484F58"
  },
  "symbols": {
    "nerd": {
      "model": "󰚩", "context": "󰍛", "rate_5h": "", "rate_7d": "󰔟",
      "directory": "", "git": "", "time": "",
      "bar_filled": "█", "bar_empty": "░"
    },
    "unicode": {
      "model": "⬡", "context": "◈", "rate_5h": "⚡", "rate_7d": "⟳",
      "directory": "⌁", "git": "⎇", "time": "◷",
      "bar_filled": "█", "bar_empty": "░"
    },
    "ascii": {
      "model": "[M]", "context": "[C]", "rate_5h": "[!]", "rate_7d": "[~]",
      "directory": "[D]", "git": "[G]", "time": "[T]",
      "bar_filled": "#", "bar_empty": "."
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

- [ ] **Step 2: Create custom render.sh**

A simple custom renderer that adds a GitHub-style look:

```bash
#!/usr/bin/env bash
# Custom renderer example — GitHub Dark theme
# Available variables: $input, $model, $used_pct, $five_pct, $week_pct, $cwd, $git_branch, $now
# Available functions: hex_to_fg, hex_to_bg, make_bar, neon_colour

BG=$(hex_to_bg "#0D1117")
BLUE=$(hex_to_fg "#58A6FF")
ORANGE=$(hex_to_fg "#F78166")
GREEN=$(hex_to_fg "#3FB950")
DIM_FG=$(hex_to_fg "#484F58")

short_dir=$(echo "$cwd" | sed "s|$HOME|~|")
ctx="${used_pct:-0}%"
r5h="${five_pct:---}"
r7d="${week_pct:---}"
[ -n "$five_pct" ] && r5h="${five_pct}%"
[ -n "$week_pct" ] && r7d="${week_pct}%"

echo -e "${BG}${BLUE}${BOLD} ${model} ${RESET}${BG}${DIM_FG} | ${ORANGE}ctx:${ctx} ${GREEN}5h:${r5h} ${BLUE}7d:${r7d} ${DIM_FG}| ${ORANGE}${short_dir} ${BLUE}${git_branch:-no-git} ${DIM_FG}${now} ${RESET}"
```

- [ ] **Step 3: Make render.sh executable**

Run: `chmod +x themes/custom-example/render.sh`

- [ ] **Step 4: Test custom theme**

Create temp config pointing to `custom-example`, run statusline, verify output.

Run: `echo '{"theme":"custom-example","symbol_set":"unicode","spacing":"normal","separator":"│","blocks":["model","context","rate_5h","rate_7d","directory","git","time"],"bar_width":10}' > /tmp/test-custom-config.json && cat tests/sample-input.json | CONFIG_OVERRIDE=/tmp/test-custom-config.json bash scripts/statusline.sh`
Expected: Non-empty output in GitHub Dark style

- [ ] **Step 5: Commit**

```bash
git add themes/custom-example/
git commit -m "feat: 自訂主題範例 — custom-example 含 render.sh override"
```

---

### Task 7: Wizard Skill (SKILL.md)

**Files:**
- Create: `skills/configure/SKILL.md`

- [ ] **Step 1: Create the wizard skill**

```markdown
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

## Step 3: Color Adjustment (Optional)

Ask: "Keep the theme's default colors, or customize?"

Most users will keep defaults — just move on. Color customization is an advanced feature for v2. If they want to customize now, suggest they edit the theme JSON file directly after the wizard completes.

## Step 4: Block Selection

Show the available blocks:
- `model` — Model name (e.g., Opus 4.6)
- `context` — Context window usage %
- `rate_5h` — 5-hour rate limit %
- `rate_7d` — 7-day rate limit %
- `directory` — Current working directory
- `git` — Git branch name
- `time` — Current time

Default: all 7 enabled in this order.

Ask: "Which blocks do you want? List the ones to keep (or say 'all')."
Also ask if they want to reorder.

## Step 5: Symbol Style

Based on Step 1 result, confirm the recommended symbol set:
- **Nerd Font** — full icons (requires Nerd Font installed)
- **Unicode** — standard symbols (works in most terminals)
- **ASCII** — plain text (works everywhere)

Ask: "Use [recommended] symbols, or choose differently?"

## Step 6: Spacing Mode

Show examples for each mode (use the selected theme's colors):
- **Normal** — `◈ CTX ██░░░░░░░░ 3%` (symbol + label + bar + %)
- **Compact** — `◈ ██░░░░░░░░ 3%` (symbol + bar + %)
- **Ultra Compact** — `◈ 3%` (symbol + % only)

Ask: "Which spacing mode? (normal/compact/ultra-compact)"

## Step 7: Separator Style

Show examples:
- **Pipe:** `segment │ segment`
- **Slash:** `segment / segment`
- **Dot:** `segment · segment`
- **Space:** `segment  segment`
- **Arrow:** `segment › segment`

Ask: "Which separator style?"

## Finalize

After all 7 steps, write the config.json using the Write tool:

```json
{
  "theme": "<selected>",
  "symbol_set": "<selected>",
  "spacing": "<selected>",
  "separator": "<selected>",
  "blocks": [<selected blocks in order>],
  "bar_width": 10
}
```

Write to: `${CLAUDE_PLUGIN_ROOT}/config.json`

Then configure the statusLine setting so Claude Code uses this plugin's script. Run this Bash command:

```bash
claude config set -g statusLine '{"type":"command","command":"bash \"${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh\""}'
```

Tell the user: "Done! Your status line is now configured. The new theme will appear on the next status line refresh. Run `/cyberpunk-statusline configure` anytime to change settings."
```

- [ ] **Step 2: Verify SKILL.md frontmatter is valid YAML**

Check that the file starts with `---`, has `name` and `description`, and ends with `---`.

- [ ] **Step 3: Commit**

```bash
git add skills/
git commit -m "feat: wizard skill — 7 步驟互動設定精靈"
```

---

### Task 8: Full Integration Test

**Files:**
- Modify: `tests/test-statusline.sh` (already created, just run it)

- [ ] **Step 1: Run full test suite**

Run: `cd /Users/scissor.lee/Documents/VibeCoding/cyberpunk-statusline && bash tests/test-statusline.sh`
Expected: All tests pass — every theme produces output, every spacing mode works

- [ ] **Step 2: Manual visual test with real Claude Code data**

Run: `cat /tmp/statusline-debug.json | bash scripts/statusline.sh`
Expected: Rendered statusline with Terminal Glitch colors, showing real model/ctx/5h/7d data

- [ ] **Step 3: Test theme switching**

```bash
# Test with Dracula theme
echo '{"theme":"dracula","symbol_set":"unicode","spacing":"normal","separator":"│","blocks":["model","context","rate_5h","rate_7d","directory","git","time"],"bar_width":10}' > /tmp/test-cfg.json
cat /tmp/statusline-debug.json | CONFIG_OVERRIDE=/tmp/test-cfg.json bash scripts/statusline.sh
```

Expected: Different colors from default Terminal Glitch

- [ ] **Step 4: Test compact modes**

```bash
echo '{"theme":"terminal-glitch","symbol_set":"unicode","spacing":"compact","separator":"·","blocks":["model","context","rate_5h","rate_7d"],"bar_width":8}' > /tmp/test-cfg.json
cat /tmp/statusline-debug.json | CONFIG_OVERRIDE=/tmp/test-cfg.json bash scripts/statusline.sh
```

Expected: Shorter output, no label text, dot separators

- [ ] **Step 5: Commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: 整合測試修正"
```

---

### Task 9: Init Git + README

**Files:**
- Create: `README.md`
- Init: git repository

- [ ] **Step 1: Initialize git repo**

Run: `cd /Users/scissor.lee/Documents/VibeCoding/cyberpunk-statusline && git init`

Configure git author per CLAUDE.md rules:
Run: `git -C /Users/scissor.lee/Documents/VibeCoding/cyberpunk-statusline config user.name "0xaissr" && git -C /Users/scissor.lee/Documents/VibeCoding/cyberpunk-statusline config user.email "0xaissr@gmail.com"`

- [ ] **Step 2: Create README.md**

Brief README with:
- What the plugin does
- Installation command
- Configuration command
- How to contribute themes
- Built-in themes list
- License

- [ ] **Step 3: Create .gitignore**

```
.DS_Store
/tmp/
```

- [ ] **Step 4: Initial commit with all files**

```bash
git add -A
git commit -m "feat: cyberpunk-statusline v1.0.0 — 12 主題、p10k 風格設定精靈"
```

---

## Task Dependency Order

```
Task 9 (git init) → should run FIRST so all other tasks can commit
Task 1 (scaffolding) → no dependencies
Task 2 (tests) → no dependencies
Task 3 (default config + first theme) → no dependencies
Task 4 (rendering engine) → depends on Task 3 (needs config + theme)
Task 5 (remaining themes) → depends on Task 4 (needs engine to test)
Task 6 (custom example) → depends on Task 4
Task 7 (wizard skill) → depends on Task 4 (references theme files)
Task 8 (integration test) → depends on all above
```

**Recommended execution order:** 9 → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8
