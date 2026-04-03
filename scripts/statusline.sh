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
  local days=$(( diff / 86400 ))
  local hours=$(( (diff % 86400) / 3600 ))
  local mins=$(( (diff % 3600) / 60 ))
  if [ "$days" -gt 0 ]; then
    printf '↻%dd%dh' "$days" "$hours"
  elif [ "$hours" -gt 0 ]; then
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

# Ensure output ends with newline so subsequent prompts start on a new line
echo -e "$output"
echo ""
