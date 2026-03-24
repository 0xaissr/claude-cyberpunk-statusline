#!/usr/bin/env bash
# ╔══════════════════════════════════════════╗
# ║  cyberpunk-statusline TUI configurator  ║
# ╚══════════════════════════════════════════╝

set -uo pipefail
# Note: do NOT use set -e — arithmetic expressions like (( x > 0 )) return
# exit code 1 when false, which would kill the script under errexit.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$PLUGIN_DIR/config.json"
THEMES_DIR="$PLUGIN_DIR/themes"
STATUSLINE="$SCRIPT_DIR/statusline.sh"
JQ=$(command -v jq 2>/dev/null || echo "/opt/homebrew/bin/jq")

# ── Startup checks ───────────────────────────────────────────────────────
if [ ! -t 0 ]; then
  echo "Error: configure requires an interactive terminal" >&2
  exit 1
fi

if ! "$JQ" --version >/dev/null 2>&1; then
  echo "Error: jq is required. Install with: brew install jq" >&2
  exit 1
fi

TERM_COLS=$(tput cols)
TERM_LINES=$(tput lines)
if (( TERM_COLS < 60 || TERM_LINES < 25 )); then
  echo "Error: terminal too small (need 60x25, got ${TERM_COLS}x${TERM_LINES})" >&2
  exit 1
fi

# ── Terminal state management ────────────────────────────────────────────
cleanup() {
  tput cnorm 2>/dev/null   # show cursor
  tput rmcup 2>/dev/null   # exit alternate screen
  stty echo 2>/dev/null    # restore echo
}
trap cleanup EXIT

tput smcup    # enter alternate screen
tput civis    # hide cursor
tput clear    # clear screen
stty -echo    # disable echo

# ── Preview sample data ──────────────────────────────────────────────────
SAMPLE_DATA='{
  "session_id": "preview",
  "model": { "id": "claude-opus-4-6", "display_name": "Opus 4.6 (1M context)" },
  "workspace": { "current_dir": "'"$HOME"'/project" },
  "context_window": { "used_percentage": 58, "remaining_percentage": 42 },
  "rate_limits": {
    "five_hour": { "used_percentage": 76, "resets_at": 9999999999 },
    "seven_day": { "used_percentage": 33, "resets_at": 9999999999 }
  }
}'

# ── Load existing config (for preselection) ──────────────────────────────
if [ -f "$CONFIG" ]; then
  cur_theme=$("$JQ" -r '.theme // "terminal-glitch"' "$CONFIG")
  cur_symbols=$("$JQ" -r '.symbol_set // "unicode"' "$CONFIG")
  cur_spacing=$("$JQ" -r '.spacing // "normal"' "$CONFIG")
  cur_separator=$("$JQ" -r '.separator // "│"' "$CONFIG")
  cur_blocks=$("$JQ" -r '.blocks // ["model","context","rate_5h","rate_7d","directory","git","time"] | .[]' "$CONFIG")
else
  cur_theme="terminal-glitch"
  cur_symbols="unicode"
  cur_spacing="normal"
  cur_separator="│"
  cur_blocks="model context rate_5h rate_7d directory git time"
fi

# Selections (will be filled by each step)
sel_symbols=""
sel_theme=""
sel_blocks=""
sel_spacing=""
sel_separator=""

# ── Drawing helpers ──────────────────────────────────────────────────────

# Clear screen and draw the wizard header
draw_header() {
  local step="$1" total="$2" title="$3"
  tput clear
  echo -e "\033[1;36m╔══════════════════════════════════════════════════╗\033[0m"
  echo -e "\033[1;36m║   CYBERPUNK STATUSLINE CONFIGURATOR             ║\033[0m"
  echo -e "\033[1;36m╚══════════════════════════════════════════════════╝\033[0m"
  echo ""
  echo -e "\033[2mStep ${step}/${total}\033[0m — \033[1m${title}\033[0m"
  echo ""
}

# Draw footer with navigation hints
draw_footer() {
  local hints="$1"
  local row=$((TERM_LINES - 1))
  tput cup "$row" 0
  echo -e "\033[2m${hints}\033[0m"
}

# Read a single keypress. Sets KEY to: "up", "down", "enter", "space", "b", "q", or the character
read_key() {
  KEY=""
  local c
  IFS= read -rsn1 c
  case "$c" in
    $'\x1b')
      local seq
      IFS= read -rsn2 -t 1 seq || true
      case "$seq" in
        '[A') KEY="up" ;;
        '[B') KEY="down" ;;
        *)    KEY="escape" ;;
      esac
      ;;
    '')    KEY="enter" ;;
    ' ')   KEY="space" ;;
    b|B)   KEY="b" ;;
    q|Q)   KEY="q" ;;
    *)     KEY="$c" ;;
  esac
}

# Render live preview of the statusline with given config overrides
# Usage: render_preview theme symbol_set spacing separator blocks_csv
render_preview() {
  local theme="$1" symbol_set="$2" spacing="$3" separator="$4" blocks_csv="$5"

  local tmp_config
  tmp_config=$(mktemp)

  # Build blocks JSON array from CSV
  local blocks_json=""
  local first=true
  IFS=',' read -ra block_arr <<< "$blocks_csv"
  for b in "${block_arr[@]}"; do
    if [ "$first" = true ]; then
      blocks_json="\"$b\""
      first=false
    else
      blocks_json="$blocks_json, \"$b\""
    fi
  done

  cat > "$tmp_config" <<CONF
{
  "theme": "$theme",
  "symbol_set": "$symbol_set",
  "spacing": "$spacing",
  "separator": "$separator",
  "blocks": [$blocks_json],
  "bar_width": 10
}
CONF

  local output
  output=$(CONFIG_OVERRIDE="$tmp_config" bash "$STATUSLINE" <<< "$SAMPLE_DATA" 2>/dev/null) || true
  rm -f "$tmp_config"

  echo -e "$output"
}

# Draw preview at a fixed row near the bottom
draw_preview() {
  local preview_row=$((TERM_LINES - 4))
  tput cup "$preview_row" 0
  # Clear the preview area (3 lines)
  echo -e "\033[K"
  echo -e "\033[K"
  tput cup "$preview_row" 0
  echo -e "\033[2mPreview:\033[0m"
  tput cup $((preview_row + 1)) 0
  render_preview "$@"
}

# Single-select menu with arrow key navigation
# Usage: menu_select initial_index label1 label2 ...
# Returns selected index (0-based) in MENU_RESULT
menu_select() {
  local cursor="$1"
  shift
  local options=("$@")
  local count=${#options[@]}

  while true; do
    # Draw options
    for i in "${!options[@]}"; do
      tput cup $((6 + i)) 0
      echo -e "\033[K"  # clear line
      if [ "$i" -eq "$cursor" ]; then
        echo -e " \033[1;36m❯\033[0m \033[1m${options[$i]}\033[0m"
      else
        echo -e "   \033[2m${options[$i]}\033[0m"
      fi
    done

    read_key
    case "$KEY" in
      up)    (( cursor > 0 )) && (( cursor-- )) ;;
      down)  (( cursor < count - 1 )) && (( cursor++ )) ;;
      enter) break ;;
      q)     cleanup; exit 0 ;;
      b)     MENU_RESULT=-1; return ;;
    esac
  done

  MENU_RESULT=$cursor
}

# ── Placeholder (will be replaced by step functions) ─────────────────────
echo "Scaffold ready — steps will be added in subsequent tasks."
