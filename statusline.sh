#!/usr/bin/env bash
# ╔══════════════════════════════════════════╗
# ║  cyberpunk-statusline rendering engine   ║
# ╚══════════════════════════════════════════╝

# ── Read stdin ─────────────────────────────────────────────────────────────
input=$(cat)

# ── Resolve paths ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${CONFIG_OVERRIDE:-$SCRIPT_DIR/config.json}"
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
cfg_style=$("$JQ" -r '.style // "classic"' "$CONFIG")
cfg_head=$("$JQ" -r '.head // "sharp"' "$CONFIG")
cfg_tail=$("$JQ" -r '.tail // "sharp"' "$CONFIG")
cfg_bar_width=$("$JQ" -r '.bar_width // 10' "$CONFIG")
cfg_bar_filled=$("$JQ" -r '.bar_filled // ""' "$CONFIG")
cfg_bar_empty=$("$JQ" -r '.bar_empty // ""' "$CONFIG")
cfg_show_icons=$("$JQ" -r 'if .show_icons == false then "false" else "true" end' "$CONFIG")
cfg_time_format=$("$JQ" -r '.time_format // "24h"' "$CONFIG")
cfg_blocks=$("$JQ" -r '.blocks // ["model","context","rate_5h","rate_7d","directory","git","time"] | .[]' "$CONFIG")

# ── Resolve theme ──────────────────────────────────────────────────────────
THEME_DIR="$SCRIPT_DIR/themes"

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
S_COST=$(sym cost)

# Clear icons if show_icons is disabled
if [ "$cfg_show_icons" = "false" ]; then
  S_MODEL="" S_CTX="" S_5H="" S_7D="" S_DIR="" S_GIT="" S_TIME="" S_COST=""
fi

# ── Read block color mappings ─────────────────────────────────────────────
block_color() {
  local ref=$("$JQ" -r ".blocks.$1.color // \"accent_1\"" "$THEME_FILE")
  color "$ref"
}
block_bg() {
  local ref=$("$JQ" -r ".blocks.$1.bg // \"bg_panel\"" "$THEME_FILE")
  color "$ref"
}
# Rainbow: use accent color as bg, dark text as fg
pl_block_bg() {
  local ref=$("$JQ" -r ".blocks.$1.pl_bg // .blocks.$1.color // \"accent_1\"" "$THEME_FILE")
  color "$ref"
}
pl_block_fg() {
  local ref=$("$JQ" -r ".blocks.$1.pl_fg // \"bg_primary\"" "$THEME_FILE")
  color "$ref"
}

# Detect rainbow mode (also support legacy separator-based detection)
PL_MODE=false
if [ "$cfg_style" = "rainbow" ] || [ "$cfg_separator" = "" ] || [ "$cfg_separator" = "" ]; then
  PL_MODE=true
  # Head = left opening of first segment; Tail = right separator / closing glyph
  # Nerd Font Powerline glyphs:
  #   Sharp:    (E0B0) /  (E0B2)
  #   Slanted:  (E0BC) /  (E0BA)  — Powerline Extra
  #   Rounded:  (E0B4) /  (E0B6)  — Powerline Extra
  #   Flat:     no glyph, just rectangular block edges
  case "$cfg_head" in
    sharp)    PL_HEAD_OPEN="" ;;
    slanted)  PL_HEAD_OPEN="" ;;
    rounded)  PL_HEAD_OPEN="" ;;
    *)        PL_HEAD_OPEN="" ;;
  esac
  case "$cfg_tail" in
    sharp)    PL_TAIL_SEP="" ;;
    slanted)  PL_TAIL_SEP="" ;;
    rounded)  PL_TAIL_SEP="" ;;
    *)        PL_TAIL_SEP="" ;;
  esac
fi

# ── Parse stdin JSON ──────────────────────────────────────────────────────
model=$(echo "$input" | "$JQ" -r '.model.display_name // "UNKNOWN"')
# Read effort level from ~/.claude/settings.json (low/medium/high) and capitalize
effort_level=""
if [ -f "$HOME/.claude/settings.json" ]; then
  effort_level=$("$JQ" -r '.effortLevel // empty' "$HOME/.claude/settings.json" 2>/dev/null)
fi
effort_cap=""
if [ -n "$effort_level" ]; then
  effort_cap="$(tr '[:lower:]' '[:upper:]' <<< "${effort_level:0:1}")${effort_level:1}"
fi
# Merge effort into the "(1M context)" marker → "(1M.High)"; otherwise append as "(High)"
if [[ "$model" == *"(1M context)"* ]]; then
  if [ -n "$effort_cap" ]; then
    model="${model//(1M context)/(1M.${effort_cap})}"
  else
    model="${model//(1M context)/(1M)}"
  fi
elif [ -n "$effort_cap" ]; then
  model="${model} (${effort_cap})"
fi
used_pct=$(echo "$input" | "$JQ" -r '.context_window.used_percentage // empty')
five_pct=$(echo "$input" | "$JQ" -r 'if (.rate_limits.five_hour.used_percentage | type) == "number" then .rate_limits.five_hour.used_percentage else empty end')
five_reset=$(echo "$input" | "$JQ" -r '.rate_limits.five_hour.resets_at // empty')
week_pct=$(echo "$input" | "$JQ" -r 'if (.rate_limits.seven_day.used_percentage | type) == "number" then .rate_limits.seven_day.used_percentage else empty end')
week_reset=$(echo "$input" | "$JQ" -r '.rate_limits.seven_day.resets_at // empty')
cwd=$(echo "$input" | "$JQ" -r '.workspace.current_dir // .cwd // "?"')
case "$cfg_time_format" in
  12h)        now=$(date +"%I:%M:%S %p") ;;
  24h-no-sec) now=$(date +"%H:%M") ;;
  12h-no-sec) now=$(date +"%-I:%M %p") ;;
  24h-date)   now=$(date +"%m/%d %H:%M") ;;
  12h-date)   now=$(date +"%m/%d %-I:%M %p") ;;
  *)          now=$(date +"%H:%M:%S") ;;
esac
git_branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || true)
# Fallback: use the repo where statusline.sh lives (useful for preview)
if [ -z "$git_branch" ]; then
  git_branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$SCRIPT_DIR" symbolic-ref --short HEAD 2>/dev/null || true)
fi

# ── Daily cost (cached, foreground refresh) ───────────────────────────────
COST_CACHE_DIR="$HOME/.cache/cyberpunk-statusline"
COST_CACHE="$COST_CACHE_DIR/daily-cost"
COST_CACHE_MAX_AGE=30  # 30 seconds — short enough to refresh after each chat
daily_cost=""

# Read cached value
if [ -f "$COST_CACHE" ]; then
  daily_cost=$(cat "$COST_CACHE" 2>/dev/null)
fi

_refresh_cost() {
  mkdir -p "$COST_CACHE_DIR"
  local val=""

  # Primary: ccusage (online pricing). Don't pass --offline because the
  # bundled pricing table lags behind new model IDs like claude-opus-4-7
  # (prices them as $0). Online mode fetches from LiteLLM's pricing repo
  # which is updated more quickly.
  if command -v ccusage >/dev/null 2>&1; then
    val=$(ccusage daily --jq '.totals.totalCost' --since "$(date +%Y%m%d)" 2>/dev/null)
  elif command -v npx >/dev/null 2>&1; then
    val=$(npx ccusage@latest daily --jq '.totals.totalCost' --since "$(date +%Y%m%d)" 2>/dev/null)
  fi

  # Fallback: local JSONL calc when ccusage unavailable or fails.
  # Uses startswith() so new model IDs inherit their family's pricing.
  if [ -z "$val" ] || [ "$val" = "null" ]; then
    local today=$(date +%Y-%m-%d)
    val=$(find "$HOME/.claude/projects" -name "*.jsonl" -maxdepth 2 2>/dev/null \
      | xargs grep -h '"type":"assistant"' 2>/dev/null \
      | "$JQ" -s --arg today "$today" '
        def price($m):
          if ($m | startswith("claude-opus")) then {i: 15, o: 75, cw: 18.75, cr: 1.50}
          elif ($m | startswith("claude-sonnet")) then {i: 3, o: 15, cw: 3.75, cr: 0.30}
          elif ($m | startswith("claude-haiku")) then {i: 1, o: 5, cw: 1.25, cr: 0.10}
          else {i: 15, o: 75, cw: 18.75, cr: 1.50} end;
        [ .[] | select(.timestamp | startswith($today)) |
          select(.message.id != null) |
          {k: (.message.id + "|" + (.requestId // "")), e: .}
        ] | group_by(.k) | map(.[0].e) |
        [ .[] | .message as $msg | $msg.usage as $u | price($msg.model) as $p |
          (($u.input_tokens // 0) * $p.i
           + ($u.output_tokens // 0) * $p.o
           + ($u.cache_creation_input_tokens // 0) * $p.cw
           + ($u.cache_read_input_tokens // 0) * $p.cr) / 1000000
        ] | add // 0
      ' 2>/dev/null)
  fi

  if [ -n "$val" ] && [ "$val" != "null" ]; then
    printf '%.2f' "$val" > "$COST_CACHE" 2>/dev/null
  fi
}

# Foreground refresh when stale — ensures current prompt shows latest cost
if [ ! -f "$COST_CACHE" ] || [ $(($(date +%s) - $(stat -f%m "$COST_CACHE" 2>/dev/null || echo 0))) -gt "$COST_CACHE_MAX_AGE" ]; then
  _refresh_cost
  daily_cost=$(cat "$COST_CACHE" 2>/dev/null)
fi

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
  if [ "$days" -gt 99 ]; then
    printf '↻>99d'
  elif [ "$days" -gt 0 ]; then
    printf '↻%dd%dh' "$days" "$hours"
  elif [ "$hours" -gt 0 ]; then
    printf '↻%dh%02dm' "$hours" "$mins"
  else
    printf '↻%dm' "$mins"
  fi
}

# ── Build separator ────────────────────────────────────────────────────────
if ! $PL_MODE; then
  SEP_FG=$(hex_to_fg "$C_SEP")
  SEP=" ${SEP_FG}${cfg_separator}${RESET} "
fi

# ── Block content helpers (text only, no bg/fg wrapper) ───────────────────
block_text_model() { echo -n " ${S_MODEL} ${model} "; }

block_text_pct() {
  local block_name="$1" symbol="$2" label="$3" pct="$4" resets_at="${5:-}"
  local fg_hex=$(block_color "$block_name")
  local dim_fg=$(hex_to_fg "$C_DIM")

  if [ -z "$pct" ]; then
    echo -n " ${symbol} ${label} -- "
    return
  fi

  local pct_int=$(printf "%.0f" "$pct")
  local countdown=$(format_countdown "$resets_at")
  local reset_str=""
  if [ -n "$countdown" ]; then reset_str=" ${countdown}"; fi

  # Determine bar chars: config overrides > theme defaults
  local bar_f="${cfg_bar_filled:-$S_BAR_FILLED}"
  local bar_e="${cfg_bar_empty:-$S_BAR_EMPTY}"
  local bw="$cfg_bar_width"

  case "$cfg_spacing" in
    ultra-compact) echo -n " ${symbol} ${pct_int}%${reset_str} " ;;
    compact)
      local bar=$(make_bar "$pct_int" "$bw" "$bar_f" "$bar_e")
      echo -n " ${symbol} ${bar} ${pct_int}%${reset_str} "
      ;;
    *)
      local bar=$(make_bar "$pct_int" "$bw" "$bar_f" "$bar_e")
      echo -n " ${symbol} ${label} ${bar} ${pct_int}%${reset_str} "
      ;;
  esac
}

block_text_directory() {
  local short_dir=$(basename "$cwd")
  echo -n " ${S_DIR} ${short_dir} "
}

block_text_git() {
  if [ -n "$git_branch" ]; then
    echo -n " ${S_GIT} ${git_branch} "
  else
    echo -n " ${S_GIT} no-git "
  fi
}

block_text_time() { echo -n " ${S_TIME} ${now} "; }

block_text_cost() {
  if [ -n "$daily_cost" ]; then
    echo -n " \$${daily_cost} "
  else
    echo -n " \$-- "
  fi
}

block_text_turn_usage() {
  local cache="/tmp/claude-turn-usage.txt"
  if [ -f "$cache" ]; then
    local data
    data=$(cat "$cache" 2>/dev/null)
    if [ -n "$data" ]; then
      IFS='|' read -r t_in t_cache t_out t_cost <<< "$data"
      echo -n " 󰊖 cache:${t_cache} in:${t_in} out:${t_out} \$${t_cost} "
      return
    fi
  fi
  echo -n " 󰊖 -- "
}

# ── Classic block renderers ───────────────────────────────────────────────
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
      local c_bar_f="${cfg_bar_filled:-$S_BAR_FILLED}" c_bar_e="${cfg_bar_empty:-$S_BAR_EMPTY}"
      local c_bw="$cfg_bar_width"
      local bar=$(make_bar "$pct_int" "$c_bw" "$c_bar_f" "$c_bar_e")
      echo -n "${bg}${fg}${BOLD} ${symbol} ${RESET}${bar_bg}${col} ${bar} ${BOLD}${pct_int}%${reset_str} ${RESET}"
      ;;
    *)
      local c_bar_f="${cfg_bar_filled:-$S_BAR_FILLED}" c_bar_e="${cfg_bar_empty:-$S_BAR_EMPTY}"
      local c_bw="$cfg_bar_width"
      local bar=$(make_bar "$pct_int" "$c_bw" "$c_bar_f" "$c_bar_e")
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
  local short_dir=$(basename "$cwd")
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

render_block_cost() {
  local fg=$(hex_to_fg "$(block_color cost)")
  local bg=$(hex_to_bg "$(block_bg cost)")
  if [ -n "$daily_cost" ]; then
    echo -n "${bg}${fg}${BOLD} \$${daily_cost} ${RESET}"
  else
    local dim_fg=$(hex_to_fg "$C_DIM")
    echo -n "${bg}${dim_fg} \$-- ${RESET}"
  fi
}

render_block_turn_usage() {
  local fg=$(hex_to_fg "$(block_color turn_usage)")
  local bg=$(hex_to_bg "$(block_bg turn_usage)")
  local cache="/tmp/claude-turn-usage.txt"
  if [ -f "$cache" ]; then
    local data
    data=$(cat "$cache" 2>/dev/null)
    if [ -n "$data" ]; then
      IFS='|' read -r t_in t_cache t_out t_cost <<< "$data"
      echo -n "${bg}${fg}${BOLD} 󰊖 cache:${t_cache} in:${t_in} out:${t_out} \$${t_cost} ${RESET}"
      return
    fi
  fi
  local dim_fg=$(hex_to_fg "$C_DIM")
  echo -n "${bg}${dim_fg} 󰊖 -- ${RESET}"
}

# ── Get block's rainbow bg hex ────────────────────────────────────────────
get_block_bg_hex() {
  local block="$1"
  if $PL_MODE; then
    pl_block_bg "$block"
  else
    block_bg "$block"
  fi
}

# ── Assemble ───────────────────────────────────────────────────────────────
output=""

if $PL_MODE; then
  # ── Rainbow assembly ───────────────────────────────────────────────────
  block_list=()
  for b in $cfg_blocks; do block_list+=("$b"); done

  prev_bg_hex=""
  for idx in "${!block_list[@]}"; do
    block="${block_list[$idx]}"
    cur_bg_hex=$(pl_block_bg "$block")
    cur_fg_hex=$(pl_block_fg "$block")
    cur_bg=$(hex_to_bg "$cur_bg_hex")
    cur_fg=$(hex_to_fg "$cur_fg_hex")

    if [ "$idx" -eq 0 ]; then
      # Head glyph: opens the first segment
      if [ -n "$PL_HEAD_OPEN" ]; then
        head_fg=$(hex_to_fg "$cur_bg_hex")
        output+="${RESET}${head_fg}${PL_HEAD_OPEN}${RESET}"
      fi
    else
      # Tail glyph between segments: prev bg → cur bg transition
      if [ -n "$PL_TAIL_SEP" ]; then
        arrow_fg=$(hex_to_fg "$prev_bg_hex")
        output+="${RESET}${arrow_fg}${cur_bg}${PL_TAIL_SEP}${RESET}"
      fi
    fi

    # Block content
    text=""
    case "$block" in
      model)     text=$(block_text_model) ;;
      context)   text=$(block_text_pct "context" "$S_CTX" "CTX" "$used_pct") ;;
      rate_5h)   text=$(block_text_pct "rate_5h" "$S_5H" "5H" "$five_pct" "$five_reset") ;;
      rate_7d)   text=$(block_text_pct "rate_7d" "$S_7D" "7D" "$week_pct" "$week_reset") ;;
      directory) text=$(block_text_directory) ;;
      git)       text=$(block_text_git) ;;
      time)      text=$(block_text_time) ;;
      cost)      text=$(block_text_cost) ;;
    esac
    output+="${cur_bg}${cur_fg}${BOLD}${text}${RESET}"

    prev_bg_hex="$cur_bg_hex"
  done

  # Closing tail glyph after last segment
  if [ -n "$prev_bg_hex" ] && [ -n "$PL_TAIL_SEP" ]; then
    arrow_fg=$(hex_to_fg "$prev_bg_hex")
    output+="${RESET}${arrow_fg}${PL_TAIL_SEP}${RESET}"
  fi
else
  # ── Classic assembly ───────────────────────────────────────────────────
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
      cost)      output+=$(render_block_cost) ;;
    esac
  done
fi

# ── Turn usage (second line) ──────────────────────────────────────────────
turn_line=""
TERM_KEY="${TERM_SESSION_ID:-${cwd}}"
TURN_CACHE="$COST_CACHE_DIR/turn-usage-$(echo -n "$TERM_KEY" | md5).txt"
if [ -f "$TURN_CACHE" ]; then
  turn_data=$(cat "$TURN_CACHE" 2>/dev/null)
  if [ -n "$turn_data" ]; then
    IFS='|' read -r t_in t_cache t_out t_cost <<< "$turn_data"
    turn_text=" 󰊖 Last Chat cache:${t_cache} in:${t_in} out:${t_out} \$${t_cost} "
    local_bg_hex=$(block_color turn_usage)
    local_fg_hex="$C_BG_PRIMARY"
    local_bg=$(hex_to_bg "$local_bg_hex")
    local_fg=$(hex_to_fg "$local_fg_hex")
    if $PL_MODE; then
      head_fg=$(hex_to_fg "$local_bg_hex")
      tail_fg=$(hex_to_fg "$local_bg_hex")
      turn_line="${RESET}${head_fg}${PL_HEAD_OPEN}${RESET}${local_bg}${local_fg}${BOLD}${turn_text}${RESET}${tail_fg}${PL_TAIL_SEP}${RESET}"
    else
      turn_line="${local_bg}${local_fg}${BOLD}${turn_text}${RESET}"
    fi
  fi
fi

# Ensure output ends with newline so subsequent prompts start on a new line
echo -e "$output"
if [ -n "$turn_line" ]; then
  echo -e "$turn_line"
fi
echo ""
