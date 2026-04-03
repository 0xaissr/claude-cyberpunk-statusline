#!/usr/bin/env bash
# ╔══════════════════════════════════════════╗
# ║  cyberpunk-statusline TUI configurator  ║
# ║  v2 — inspired by Powerlevel10k         ║
# ╚══════════════════════════════════════════╝

# Note: do NOT use set -euo pipefail in interactive TUI scripts.
# set -e kills on arithmetic false, set -u kills on any empty variable.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$PLUGIN_DIR/config.json"
THEMES_DIR="$PLUGIN_DIR/themes"
STATUSLINE="$SCRIPT_DIR/statusline.sh"
JQ=$(command -v jq 2>/dev/null || echo "/opt/homebrew/bin/jq")

TOTAL_STEPS=7
DEFAULT_THEME="terminal-glitch"

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

# ── Terminal state management ────────────────────────────────────────────
cleanup() {
  tput cnorm 2>/dev/null   # show cursor
  tput rmcup 2>/dev/null   # exit alternate screen
  stty echo 2>/dev/null    # restore echo
  [ -n "${PREVIEW_TMP_CONFIG:-}" ] && rm -f "$PREVIEW_TMP_CONFIG" 2>/dev/null
}
trap cleanup EXIT INT TERM

tput smcup    # enter alternate screen
tput civis    # hide cursor
tput clear    # clear screen
stty -echo    # disable echo

# ── Preview sample data ──────────────────────────────────────────────────
_preview_reset=$(( $(date +%s) + 99*86400 + 23*3600 ))
SAMPLE_DATA='{
  "session_id": "preview",
  "model": { "id": "claude-opus-4-6", "display_name": "Opus 4.6 (1M)" },
  "workspace": { "current_dir": "'"$HOME"'/project" },
  "context_window": { "used_percentage": 58, "remaining_percentage": 42 },
  "rate_limits": {
    "five_hour": { "used_percentage": 76, "resets_at": '"$_preview_reset"' },
    "seven_day": { "used_percentage": 33, "resets_at": '"$_preview_reset"' }
  }
}'

# ── Load existing config (for preselection) ──────────────────────────────
if [ -f "$CONFIG" ]; then
  cur_theme=$("$JQ" -r '.theme // "terminal-glitch"' "$CONFIG")
  cur_symbols=$("$JQ" -r '.symbol_set // "unicode"' "$CONFIG")
  cur_spacing=$("$JQ" -r '.spacing // "normal"' "$CONFIG")
  cur_separator=$("$JQ" -r '.separator // "│"' "$CONFIG")
  cur_bar_width=$("$JQ" -r '.bar_width // 10' "$CONFIG")
  cur_time_format=$("$JQ" -r '.time_format // "24h"' "$CONFIG")
  cur_blocks=$("$JQ" -r '.blocks // ["model","context","rate_5h","rate_7d","directory","git","time"] | .[]' "$CONFIG")
else
  cur_theme="terminal-glitch"
  cur_symbols="unicode"
  cur_spacing="normal"
  cur_separator="│"
  cur_bar_width=10
  cur_time_format="24h"
  cur_blocks="model context rate_5h rate_7d directory git time"
fi

# Selections (will be filled by each step)
sel_symbols=""
sel_theme=""
sel_blocks=""
sel_spacing=""
sel_style=""        # "classic" or "rainbow"
sel_separator=""
sel_head=""         # "flat", "sharp", "slanted", "rounded"
sel_tail=""         # "flat", "sharp", "slanted", "rounded"
sel_bar_width=""
sel_time_format=""

# ── Restart helper ───────────────────────────────────────────────────────
restart_wizard() {
  sel_symbols=""
  sel_theme=""
  sel_blocks=""
  sel_spacing=""
  sel_style=""
  sel_separator=""
  sel_head=""
  sel_tail=""
  sel_bar_width=""
  sel_time_format=""
  current_step=1
}

# ══════════════════════════════════════════════════════════════════════════
# ── DRAWING HELPERS ──────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════

draw_header() {
  local step="$1" total="$2" title="$3"
  tput clear
  printf '\033[1;36m  CYBERPUNK STATUSLINE CONFIGURATOR\033[0m\n'
  printf '\033[2m  ===================================\033[0m\n'
  printf '\n'
  printf '\033[2mStep %s/%s\033[0m — \033[1m%s\033[0m\n' "$step" "$total" "$title"
  printf '\n'
}

# Read a single keypress. Sets KEY variable.
read_key() {
  KEY=""
  local c
  IFS= read -rsn1 c
  case "$c" in
    $'\x1b')
      local c2 c3
      IFS= read -rsn1 -t 1 c2 || true
      if [ "$c2" = "[" ] || [ "$c2" = "O" ]; then
        IFS= read -rsn1 -t 1 c3 || true
        case "$c3" in
          A) KEY="up" ;;
          B) KEY="down" ;;
          *) KEY="escape" ;;
        esac
      else
        KEY="escape"
      fi
      ;;
    '')    KEY="enter" ;;
    ' ')   KEY="space" ;;
    k|K)   KEY="up" ;;
    j|J)   KEY="down" ;;
    b)     KEY="b" ;;
    q)     KEY="q" ;;
    r)     KEY="r" ;;
    y|Y)   KEY="y" ;;
    n|N)   KEY="n" ;;
    [0-9]) KEY="num_$c" ;;
    *)     KEY="$c" ;;
  esac
}

# ── p10k-style y/n question ──────────────────────────────────────────────
# Usage: ask_yn "prompt_text" "visual_content"
# Returns: 0=yes, 1=no, 2=restart, 3=quit
ask_yn() {
  local prompt="$1"
  local visual="${2:-}"
  local row=5

  if [ -n "$prompt" ]; then
    tput cup $row 0
    printf '\033[K\033[1m    %s\033[0m\n' "$prompt"
    row=$((row + 1))
  fi

  if [ -n "$visual" ]; then
    printf '\033[K\n'
    tput cup $((row + 1)) 0
    printf '\033[K%b\n' "$visual"
    row=$((row + 3))
  fi

  tput cup $row 0
  printf '\033[K  \033[1m(y)\033[0m  Yes.\n'
  printf '\033[K\n'
  printf '\033[K  \033[1m(n)\033[0m  No.\n'
  printf '\033[K\n'
  printf '\033[K  \033[2m(r)  Restart from the beginning.\033[0m\n'
  printf '\033[K  \033[2m(q)  Quit and do nothing.\033[0m\n'
  printf '\033[K\n'
  printf '\033[K  \033[1mChoice [ynrq]:\033[0m '
  tput cnorm  # show cursor for input

  while true; do
    read_key
    case "$KEY" in
      y) tput civis; return 0 ;;
      n) tput civis; return 1 ;;
      r) tput civis; return 2 ;;
      q) cleanup; exit 0 ;;
    esac
  done
}

# ── p10k-style numbered choice ───────────────────────────────────────────
# Usage: ask_choice option1 option2 ...
# Each option format: "label" or "label|preview_line"
# Returns selected index (1-based) in CHOICE_RESULT
# Returns 0=selected, 1=restart, 2=quit
ask_choice() {
  local options=("$@")
  local count=${#options[@]}
  local row=5

  # Build valid keys string
  local valid_keys=""
  for ((i=1; i<=count; i++)); do valid_keys+="$i"; done

  for i in "${!options[@]}"; do
    local num=$((i + 1))
    local label="${options[$i]%%|*}"
    local preview="${options[$i]#*|}"

    tput cup $row 0
    printf '\033[K  \033[1m(%d)\033[0m  %s\n' "$num" "$label"
    row=$((row + 1))

    # If option has embedded preview (separated by |)
    if [ "$preview" != "${options[$i]}" ]; then
      printf '\033[K       '
      echo -e "$preview"
      printf '\033[0m'
      row=$((row + 1))
    fi
    printf '\033[K\n'
    row=$((row + 1))
  done

  tput cup $row 0
  printf '\033[K  \033[2m(r)  Restart from the beginning.\033[0m\n'
  printf '\033[K  \033[2m(q)  Quit and do nothing.\033[0m\n'
  printf '\033[K\n'
  printf '\033[K  \033[1mChoice [%srq]:\033[0m ' "$valid_keys"
  tput cnorm

  while true; do
    read_key
    case "$KEY" in
      num_[0-9])
        local n=${KEY#num_}
        if (( n >= 1 && n <= count )); then
          CHOICE_RESULT=$n
          tput civis
          return 0
        fi
        ;;
      r) tput civis; return 1 ;;
      q) cleanup; exit 0 ;;
    esac
  done
}

# ── Preview rendering ────────────────────────────────────────────────────
# Render statusline preview with given config overrides
# Usage: render_preview theme symbol_set spacing separator blocks_csv [bar_width] [time_format] [style] [head] [tail]
render_preview() {
  local theme="$1" symbol_set="$2" spacing="$3" separator="$4" blocks_csv="$5"
  local bar_width="${6:-10}" time_format="${7:-24h}"
  local style="${8:-classic}" head="${9:-sharp}" tail="${10:-sharp}"

  local tmp_config="${PREVIEW_TMP_CONFIG:-$(mktemp)}"
  PREVIEW_TMP_CONFIG="$tmp_config"

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
  "style": "$style",
  "head": "$head",
  "tail": "$tail",
  "blocks": [$blocks_json],
  "bar_width": $bar_width,
  "time_format": "$time_format"
}
CONF

  local output
  output=$(CONFIG_OVERRIDE="$tmp_config" bash "$STATUSLINE" <<< "$SAMPLE_DATA" 2>/dev/null) || true
  echo -e "$output"
}

# Get current style params for preview
_cur_style() { echo "${sel_style:-classic}"; }
_cur_head()  { echo "${sel_head:-sharp}"; }
_cur_tail()  { echo "${sel_tail:-sharp}"; }

# Get a one-line preview string using default theme and current selections
get_preview_line() {
  local spacing="${1:-${sel_spacing:-$cur_spacing}}"
  local separator="${2:-${sel_separator:-$cur_separator}}"
  local blocks_csv="${3:-}"
  local bar_width="${4:-${sel_bar_width:-$cur_bar_width}}"
  local time_format="${5:-${sel_time_format:-$cur_time_format}}"

  if [ -z "$blocks_csv" ]; then
    if [ -n "$sel_blocks" ]; then
      blocks_csv="$sel_blocks"
    else
      blocks_csv=$(echo "$cur_blocks" | tr ' ' '\n' | tr '\n' ',' | sed 's/,$//')
    fi
  fi

  render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" \
    "$spacing" "$separator" "$blocks_csv" "$bar_width" "$time_format" \
    "$(_cur_style)" "$(_cur_head)" "$(_cur_tail)"
}

# Draw preview at a fixed row near the bottom
draw_preview() {
  local preview_row=$((TERM_LINES - 4))
  tput cup "$preview_row" 0
  printf '\033[K\033[2mPreview:\033[0m\n'
  tput cup $((preview_row + 1)) 0
  printf '\033[K'
  render_preview "$@"
  printf '\033[K'
}

# Draw footer with navigation hints
draw_footer() {
  local hints="$1"
  local row=$((TERM_LINES - 1))
  tput cup "$row" 0
  printf '\033[K\033[2m%s\033[0m' "$hints"
}

# ══════════════════════════════════════════════════════════════════════════
# ── STEP FUNCTIONS ───────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════

# ── Step 1: Font capability detection ────────────────────────────────────
step_font_detect() {
  local nerd_ok=false
  local unicode_ok=false

  # Q1: Nerd Font test
  draw_header 1 $TOTAL_STEPS "Font detection"

  ask_yn "Does this look like a brain/circuit icon?" "              ---> \033[1;36m󰚩\033[0m <---"
  local rc=$?
  if [ $rc -eq 2 ]; then return 2; fi  # restart
  if [ $rc -eq 0 ]; then nerd_ok=true; fi

  # Q2: Nerd Font spacing test (only if Q1=yes)
  if $nerd_ok; then
    draw_header 1 $TOTAL_STEPS "Font detection — icon spacing"

    ask_yn "Do all these icons fit between the crosses?" "              ---> \033[1mX\033[36m󰚩\033[0;1mX\033[36m󰍛\033[0;1mX\033[36m󰕐\033[0;1mX\033[36m󰔟\033[0;1mX\033[36m󰉋\033[0;1mX\033[36m󰊢\033[0;1mX\033[36m󰅐\033[0;1mX\033[0m <---"
    rc=$?
    if [ $rc -eq 2 ]; then return 2; fi
    if [ $rc -eq 0 ]; then
      sel_symbols="nerd"
      return 0
    fi
    # Icons overlap — fall back to unicode test
  fi

  # Q3: Unicode test
  draw_header 1 $TOTAL_STEPS "Font detection — unicode symbols"

  ask_yn "Do these three symbols display correctly?" "              ---> \033[1;33m⬡\033[0m  \033[1;35m◈\033[0m  \033[1;31m⚡\033[0m <---"
  rc=$?
  if [ $rc -eq 2 ]; then return 2; fi
  if [ $rc -eq 0 ]; then
    sel_symbols="unicode"
  else
    sel_symbols="ascii"
  fi
  return 0
}

# ── Step 2: Block selection ──────────────────────────────────────────────
step_blocks() {
  draw_header 2 $TOTAL_STEPS "Which blocks to show? (Space to toggle)"

  local block_ids=("model" "context" "rate_5h" "rate_7d" "directory" "git" "time")
  local block_descs=(
    "model       — Model name (e.g., Opus 4.6)"
    "context     — Context window usage %"
    "rate_5h     — 5-hour rate limit %"
    "rate_7d     — 7-day rate limit %"
    "directory   — Working directory"
    "git         — Git branch"
    "time        — Current time"
  )

  # All blocks start checked — user opts out
  local states=()
  for bid in "${block_ids[@]}"; do
    states+=("1")
  done

  draw_footer "j/k move · Space toggle · Enter confirm · r restart · q quit"

  local cursor=0
  local count=${#block_descs[@]}

  while true; do
    for i in "${!block_descs[@]}"; do
      tput cup $((5 + i)) 0
      local check_mark
      if [ "${states[$i]}" = "1" ]; then
        check_mark="\033[32m✔\033[0m"
      else
        check_mark="\033[2m✗\033[0m"
      fi
      if [ "$i" -eq "$cursor" ]; then
        printf '\033[K \033[1;36m❯\033[0m'"${check_mark}"' \033[1m%s\033[0m' "${block_descs[$i]}"
      else
        printf '\033[K  '"${check_mark}"' \033[2m%s\033[0m' "${block_descs[$i]}"
      fi
    done

    # Build current blocks CSV for preview
    local blocks_csv=""
    local first=true
    for i in "${!block_ids[@]}"; do
      if [ "${states[$i]}" = "1" ]; then
        if $first; then
          blocks_csv="${block_ids[$i]}"
          first=false
        else
          blocks_csv="$blocks_csv,${block_ids[$i]}"
        fi
      fi
    done

    draw_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" \
      "${sel_spacing:-$cur_spacing}" "${sel_separator:-$cur_separator}" \
      "$blocks_csv" "${sel_bar_width:-$cur_bar_width}" "${sel_time_format:-$cur_time_format}"

    read_key
    case "$KEY" in
      up)    (( cursor > 0 )) && (( cursor-- )) ;;
      down)  (( cursor < count - 1 )) && (( cursor++ )) ;;
      space)
        if [ "${states[$cursor]}" = "1" ]; then
          states[$cursor]="0"
        else
          states[$cursor]="1"
        fi
        ;;
      enter)
        local any_checked=false
        for s in "${states[@]}"; do
          [ "$s" = "1" ] && any_checked=true
        done
        if ! $any_checked; then
          tput cup $((TERM_LINES - 1)) 0
          printf '\033[K\033[31mAt least one block must be enabled!\033[0m'
          sleep 1
          draw_footer "j/k move · Space toggle · Enter confirm · r restart · q quit"
          continue
        fi
        sel_blocks=""
        local first=true
        for i in "${!block_ids[@]}"; do
          if [ "${states[$i]}" = "1" ]; then
            if $first; then
              sel_blocks="${block_ids[$i]}"
              first=false
            else
              sel_blocks="$sel_blocks,${block_ids[$i]}"
            fi
          fi
        done
        return 0
        ;;
      r) return 2 ;;
      b) return 1 ;;
      q) cleanup; exit 0 ;;
    esac
  done
}

# ── Step 3: Spacing mode ─────────────────────────────────────────────────
step_spacing() {
  draw_header 3 $TOTAL_STEPS "Spacing mode:"

  # Generate preview lines for each option
  local blocks_csv="${sel_blocks:-$(echo "$cur_blocks" | tr ' ' '\n' | tr '\n' ',' | sed 's/,$//')}"
  local separator="${sel_separator:-$cur_separator}"
  local bw="${sel_bar_width:-6}"

  local p_normal p_compact p_ultra
  p_normal=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "normal" "$separator" "$blocks_csv" "$bw")
  p_compact=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "compact" "$separator" "$blocks_csv" "$bw")
  p_ultra=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "ultra-compact" "$separator" "$blocks_csv" "$bw")

  ask_choice \
    "Normal        — symbol + label + bar + %|$p_normal" \
    "Compact       — symbol + bar + %|$p_compact" \
    "Ultra Compact — symbol + % only|$p_ultra"

  local rc=$?
  if [ $rc -eq 1 ]; then return 2; fi  # restart

  local values=("normal" "compact" "ultra-compact")
  sel_spacing="${values[$((CHOICE_RESULT - 1))]}"
  return 0
}

# ── Step 3b: Bar width (conditional) ─────────────────────────────────────
step_bar_width() {
  # Only show if spacing uses bars
  if [ "$sel_spacing" = "ultra-compact" ]; then
    sel_bar_width="${cur_bar_width:-10}"
    return 0
  fi

  draw_header 3 $TOTAL_STEPS "Progress bar width:"

  local blocks_csv="${sel_blocks:-$(echo "$cur_blocks" | tr ' ' '\n' | tr '\n' ',' | sed 's/,$//')}"
  local separator="${sel_separator:-$cur_separator}"

  local p_short p_medium p_long
  p_short=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "$separator" "$blocks_csv" 6)
  p_medium=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "$separator" "$blocks_csv" 10)
  p_long=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "$separator" "$blocks_csv" 16)

  ask_choice \
    "Short  (6)|$p_short" \
    "Medium (10)|$p_medium" \
    "Long   (16)|$p_long"

  local rc=$?
  if [ $rc -eq 1 ]; then return 2; fi

  local values=(6 10 16)
  sel_bar_width="${values[$((CHOICE_RESULT - 1))]}"
  return 0
}

# ── Step 4: Prompt style ─────────────────────────────────────────────────
step_prompt_style() {
  draw_header 4 $TOTAL_STEPS "Prompt style:"

  local blocks_csv="${sel_blocks:-$(echo "$cur_blocks" | tr ' ' '\n' | tr '\n' ',' | sed 's/,$//')}"
  local bw="${sel_bar_width:-$cur_bar_width}"

  local p_classic p_rainbow
  p_classic=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "│" "$blocks_csv" "$bw" "24h" "classic" "" "")
  p_rainbow=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "" "$blocks_csv" "$bw" "24h" "rainbow" "sharp" "sharp")

  ask_choice \
    "Classic   — colored text on dark bg|$p_classic" \
    "Rainbow   — colored bg segments with arrows|$p_rainbow"

  local rc=$?
  if [ $rc -eq 1 ]; then return 2; fi

  if [ "$CHOICE_RESULT" -eq 1 ]; then
    sel_style="classic"
  else
    sel_style="rainbow"
  fi
  return 0
}

# ── Step 4b: Classic separator (only if classic style) ───────────────────
step_separator() {
  if [ "$sel_style" = "rainbow" ]; then
    sel_separator=""
    return 0
  fi

  draw_header 4 $TOTAL_STEPS "Block separator:"

  local blocks_csv="${sel_blocks:-$(echo "$cur_blocks" | tr ' ' '\n' | tr '\n' ',' | sed 's/,$//')}"
  local bw="${sel_bar_width:-$cur_bar_width}"

  local p1 p2 p3 p4 p5
  p1=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "│" "$blocks_csv" "$bw" "24h" "classic")
  p2=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "/" "$blocks_csv" "$bw" "24h" "classic")
  p3=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "·" "$blocks_csv" "$bw" "24h" "classic")
  p4=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" " " "$blocks_csv" "$bw" "24h" "classic")
  p5=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "›" "$blocks_csv" "$bw" "24h" "classic")

  ask_choice \
    "Pipe  │|$p1" \
    "Slash /|$p2" \
    "Dot   ·|$p3" \
    "Space|$p4" \
    "Arrow ›|$p5"

  local rc=$?
  if [ $rc -eq 1 ]; then return 2; fi

  local values=("│" "/" "·" " " "›")
  sel_separator="${values[$((CHOICE_RESULT - 1))]}"
  return 0
}

# ── Step 4c: Head style (only if rainbow) ────────────────────────────────
step_head() {
  if [ "$sel_style" != "rainbow" ]; then
    sel_head="sharp"
    return 0
  fi

  draw_header 4 $TOTAL_STEPS "Segment head (left edge):"

  local blocks_csv="${sel_blocks:-$(echo "$cur_blocks" | tr ' ' '\n' | tr '\n' ',' | sed 's/,$//')}"
  local bw="${sel_bar_width:-$cur_bar_width}"
  local tf="${sel_time_format:-24h}"

  local p1 p2 p3 p4
  p1=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "" "$blocks_csv" "$bw" "$tf" "rainbow" "flat" "${sel_tail:-sharp}")
  p2=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "" "$blocks_csv" "$bw" "$tf" "rainbow" "sharp" "${sel_tail:-sharp}")
  p3=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "" "$blocks_csv" "$bw" "$tf" "rainbow" "slanted" "${sel_tail:-sharp}")
  p4=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "" "$blocks_csv" "$bw" "$tf" "rainbow" "rounded" "${sel_tail:-sharp}")

  ask_choice \
    "Flat|$p1" \
    "Sharp|$p2" \
    "Slanted|$p3" \
    "Rounded|$p4"

  local rc=$?
  if [ $rc -eq 1 ]; then return 2; fi

  local values=("flat" "sharp" "slanted" "rounded")
  sel_head="${values[$((CHOICE_RESULT - 1))]}"
  return 0
}

# ── Step 4d: Tail style (only if rainbow) ────────────────────────────────
step_tail() {
  if [ "$sel_style" != "rainbow" ]; then
    sel_tail="sharp"
    return 0
  fi

  draw_header 4 $TOTAL_STEPS "Segment tail (separator / right edge):"

  local blocks_csv="${sel_blocks:-$(echo "$cur_blocks" | tr ' ' '\n' | tr '\n' ',' | sed 's/,$//')}"
  local bw="${sel_bar_width:-$cur_bar_width}"
  local tf="${sel_time_format:-24h}"

  local p1 p2 p3 p4
  p1=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "" "$blocks_csv" "$bw" "$tf" "rainbow" "$sel_head" "flat")
  p2=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "" "$blocks_csv" "$bw" "$tf" "rainbow" "$sel_head" "sharp")
  p3=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "" "$blocks_csv" "$bw" "$tf" "rainbow" "$sel_head" "slanted")
  p4=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "" "$blocks_csv" "$bw" "$tf" "rainbow" "$sel_head" "rounded")

  ask_choice \
    "Flat|$p1" \
    "Sharp|$p2" \
    "Slanted|$p3" \
    "Rounded|$p4"

  local rc=$?
  if [ $rc -eq 1 ]; then return 2; fi

  local values=("flat" "sharp" "slanted" "rounded")
  sel_tail="${values[$((CHOICE_RESULT - 1))]}"
  return 0
}

# ── Step 5: Time format (conditional) ────────────────────────────────────
step_time_format() {
  # Only show if time block is enabled
  if ! echo ",$sel_blocks," | grep -q ",time,"; then
    sel_time_format="${cur_time_format:-24h}"
    return 0
  fi

  draw_header 5 $TOTAL_STEPS "Time format:"

  # Generate preview lines — use time-only blocks for clarity
  local bw="${sel_bar_width:-$cur_bar_width}"
  local separator="${sel_separator:-│}"
  local blocks_csv="${sel_blocks}"

  local p1 p2 p3 p4
  p1=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "$separator" "$blocks_csv" "$bw" "24h" "$(_cur_style)" "$(_cur_head)" "$(_cur_tail)")
  p2=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "$separator" "$blocks_csv" "$bw" "12h" "$(_cur_style)" "$(_cur_head)" "$(_cur_tail)")
  p3=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "$separator" "$blocks_csv" "$bw" "24h-no-sec" "$(_cur_style)" "$(_cur_head)" "$(_cur_tail)")
  p4=$(render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "$separator" "$blocks_csv" "$bw" "12h-no-sec" "$(_cur_style)" "$(_cur_head)" "$(_cur_tail)")

  ask_choice \
    "24-hour          (16:23:42)|$p1" \
    "12-hour          (04:23:42 PM)|$p2" \
    "24-hour (short)  (16:23)|$p3" \
    "12-hour (short)  (4:23 PM)|$p4"

  local rc=$?
  if [ $rc -eq 1 ]; then return 2; fi

  local values=("24h" "12h" "24h-no-sec" "12h-no-sec")
  sel_time_format="${values[$((CHOICE_RESULT - 1))]}"
  return 0
}

# ── Step 6: Theme selection (arrow-key navigation) ───────────────────────
step_theme() {
  draw_header 6 $TOTAL_STEPS "Choose your theme:"

  # Cyberpunk themes (ordered)
  local cyberpunk_order=("terminal-glitch" "neon-classic" "synthwave-sunset" "blade-runner" "retrowave-chrome" "midnight-phantom")
  # Classic themes (ordered)
  local classic_order=("dracula" "tokyo-night" "catppuccin-mocha" "rose-pine" "nord" "one-dark" "gruvbox-dark")

  local all_labels=()
  local all_ids=()

  # Cyberpunk group
  all_labels+=("── Cyberpunk ──")
  all_ids+=("__header__")
  for tid in "${cyberpunk_order[@]}"; do
    local tf="$THEMES_DIR/${tid}.json"
    if [ -f "$tf" ]; then
      local name desc
      name=$("$JQ" -r '.name // "'"$tid"'"' "$tf")
      desc=$("$JQ" -r '.description // ""' "$tf")
      if [ -n "$desc" ]; then
        all_labels+=("$name — $desc")
      else
        all_labels+=("$name")
      fi
      all_ids+=("$tid")
    fi
  done

  # Classic group
  all_labels+=("── Classic ──")
  all_ids+=("__header__")
  for tid in "${classic_order[@]}"; do
    local tf="$THEMES_DIR/${tid}.json"
    if [ -f "$tf" ]; then
      local name
      name=$("$JQ" -r '.name // "'"$tid"'"' "$tf")
      all_labels+=("$name")
      all_ids+=("$tid")
    fi
  done

  local count=${#all_labels[@]}

  # Find initial cursor from existing config (skip headers)
  local cursor=1  # first non-header
  for i in "${!all_ids[@]}"; do
    if [ "${all_ids[$i]}" = "$cur_theme" ]; then
      cursor=$i
      break
    fi
  done

  local blocks_csv="${sel_blocks:-$(echo "$cur_blocks" | tr ' ' '\n' | tr '\n' ',' | sed 's/,$//')}"
  local bw="${sel_bar_width:-$cur_bar_width}"
  local tf="${sel_time_format:-$cur_time_format}"

  draw_footer "j/k move · Enter select · r restart · b back · q quit"

  local prev_cursor=-1
  while true; do
    if [ "$cursor" != "$prev_cursor" ]; then
      for i in "${!all_labels[@]}"; do
        tput cup $((5 + i)) 0
        if [ "${all_ids[$i]}" = "__header__" ]; then
          printf '\033[K \033[2;33m%s\033[0m' "${all_labels[$i]}"
        elif [ "$i" -eq "$cursor" ]; then
          printf '\033[K \033[1;36m❯\033[0m \033[1m%s\033[0m' "${all_labels[$i]}"
        else
          printf '\033[K   \033[2m%s\033[0m' "${all_labels[$i]}"
        fi
      done

      if [ "${all_ids[$cursor]}" != "__header__" ]; then
        draw_preview "${all_ids[$cursor]}" "${sel_symbols:-$cur_symbols}" \
          "$sel_spacing" "$sel_separator" "$blocks_csv" "$bw" "$tf" \
          "$(_cur_style)" "$(_cur_head)" "$(_cur_tail)"
      fi
      prev_cursor=$cursor
    fi

    read_key
    case "$KEY" in
      up)
        local prev=$cursor
        (( cursor > 0 )) && (( cursor-- ))
        while [ "$cursor" -ge 0 ] && [ "${all_ids[$cursor]}" = "__header__" ]; do
          (( cursor > 0 )) && (( cursor-- )) || { cursor=$prev; break; }
        done
        ;;
      down)
        local prev=$cursor
        (( cursor < count - 1 )) && (( cursor++ ))
        while [ "$cursor" -lt "$count" ] && [ "${all_ids[$cursor]}" = "__header__" ]; do
          (( cursor < count - 1 )) && (( cursor++ )) || { cursor=$prev; break; }
        done
        ;;
      enter)
        if [ "${all_ids[$cursor]}" != "__header__" ]; then
          sel_theme="${all_ids[$cursor]}"
          return 0
        fi
        ;;
      r) return 2 ;;
      b) return 1 ;;
      q) cleanup; exit 0 ;;
    esac
  done
}

# ── Step 7: Save config ──────────────────────────────────────────────────
step_done() {
  # Build blocks JSON
  local blocks_json=""
  local first=true
  IFS=',' read -ra block_arr <<< "$sel_blocks"
  for b in "${block_arr[@]}"; do
    if $first; then
      blocks_json="\"$b\""
      first=false
    else
      blocks_json="$blocks_json, \"$b\""
    fi
  done

  local block_count=${#block_arr[@]}
  local bar_width="${sel_bar_width:-10}"
  local time_format="${sel_time_format:-24h}"

  # Write config
  local config_content
  config_content=$(cat <<CONF
{
  "theme": "$sel_theme",
  "symbol_set": "$sel_symbols",
  "spacing": "$sel_spacing",
  "style": "$sel_style",
  "separator": "$sel_separator",
  "head": "$sel_head",
  "tail": "$sel_tail",
  "blocks": [$blocks_json],
  "bar_width": $bar_width,
  "time_format": "$time_format"
}
CONF
)
  echo "$config_content" > "$CONFIG"

  # Sync to plugin cache if installed via Claude Code plugin system
  local claude_settings="$HOME/.claude/settings.json"
  if [ -f "$claude_settings" ]; then
    local cache_script
    cache_script=$("$JQ" -r '.statusLine.command // empty' "$claude_settings" | grep -o '"[^"]*statusline\.sh"' | tr -d '"' || true)
    if [ -z "$cache_script" ]; then
      cache_script=$("$JQ" -r '.statusLine.command // empty' "$claude_settings" | awk '{for(i=1;i<=NF;i++) if($i ~ /statusline\.sh/) print $i}' | tr -d '"' || true)
    fi
    if [ -n "$cache_script" ] && [ -f "$cache_script" ]; then
      local cache_plugin_dir
      cache_plugin_dir="$(cd "$(dirname "$cache_script")/.." && pwd)"
      if [ "$cache_plugin_dir" != "$PLUGIN_DIR" ]; then
        echo "$config_content" > "$cache_plugin_dir/config.json"
        local theme_src="$THEMES_DIR/${sel_theme}.json"
        local theme_dst="$cache_plugin_dir/themes/${sel_theme}.json"
        if [ -f "$theme_src" ] && [ ! -f "$theme_dst" ]; then
          cp "$theme_src" "$theme_dst"
        fi
      fi
    fi
  fi

  # Show completion screen
  tput clear
  printf '\033[1;32m  ✔ Configuration saved!\033[0m\n'
  printf '\033[2m  ===================================\033[0m\n'
  echo ""
  echo -e "\033[2mTheme:      \033[0m $sel_theme"
  echo -e "\033[2mSymbols:    \033[0m $sel_symbols"
  echo -e "\033[2mBlocks:     \033[0m ${block_count}/7 enabled"
  echo -e "\033[2mSpacing:    \033[0m $sel_spacing"
  echo -e "\033[2mStyle:      \033[0m $sel_style"
  if [ "$sel_style" = "rainbow" ]; then
    echo -e "\033[2mHead:       \033[0m $sel_head"
    echo -e "\033[2mTail:       \033[0m $sel_tail"
  else
    echo -e "\033[2mSeparator:  \033[0m $sel_separator"
  fi
  echo -e "\033[2mBar width:  \033[0m $bar_width"
  echo -e "\033[2mTime format:\033[0m $time_format"
  echo ""
  render_preview "$sel_theme" "$sel_symbols" "$sel_spacing" "$sel_separator" \
    "$sel_blocks" "$bar_width" "$time_format" "$sel_style" "$sel_head" "$sel_tail"
  echo ""
  echo ""
  echo -e "\033[2mYour status line will update on the next refresh.\033[0m"
  echo -e "\033[2mRun\033[0m \033[36mcyberpunk-statusline configure\033[0m \033[2manytime to reconfigure.\033[0m"
  echo ""
  echo -e "\033[2mPress any key to exit.\033[0m"
  read -rsn1
}

# ══════════════════════════════════════════════════════════════════════════
# ── MAIN WIZARD FLOW ─────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════

current_step=1
rc=0

while true; do
  case $current_step in
    1) # Font detection
      step_font_detect
      rc=$?
      if [ $rc -eq 2 ]; then
        restart_wizard
      elif [ $rc -eq 0 ] && [ -n "$sel_symbols" ]; then
        current_step=2
      fi
      ;;
    2) # Blocks
      step_blocks
      rc=$?
      if [ $rc -eq 2 ]; then
        restart_wizard
      elif [ $rc -eq 0 ]; then
        current_step=3
      elif [ $rc -eq 1 ]; then
        current_step=1
      fi
      ;;
    3) # Spacing + bar_width
      step_spacing
      rc=$?
      if [ $rc -eq 2 ]; then
        restart_wizard
      elif [ $rc -eq 0 ]; then
        step_bar_width
        rc=$?
        if [ $rc -eq 2 ]; then
          restart_wizard
        elif [ $rc -eq 0 ]; then
          current_step=4
        fi
      fi
      ;;
    4) # Prompt style
      step_prompt_style
      rc=$?
      if [ $rc -eq 2 ]; then
        restart_wizard
      elif [ $rc -eq 0 ]; then
        # Rainbow → heads/tails; Classic → separator
        current_step="4b"
      fi
      ;;
    4b) # Separator (classic) or Head (rainbow)
      if [ "$sel_style" = "rainbow" ]; then
        step_head
      else
        step_separator
      fi
      rc=$?
      if [ $rc -eq 2 ]; then
        restart_wizard
      elif [ $rc -eq 0 ]; then
        if [ "$sel_style" = "rainbow" ]; then
          current_step="4c"
        else
          current_step=5
        fi
      fi
      ;;
    4c) # Tail (rainbow only)
      step_tail
      rc=$?
      if [ $rc -eq 2 ]; then
        restart_wizard
      elif [ $rc -eq 0 ]; then
        current_step=5
      fi
      ;;
    5) # Time format (conditional)
      step_time_format
      rc=$?
      if [ $rc -eq 2 ]; then
        restart_wizard
      elif [ $rc -eq 0 ]; then
        current_step=6
      fi
      ;;
    6) # Theme
      step_theme
      rc=$?
      if [ $rc -eq 2 ]; then
        restart_wizard
      elif [ $rc -eq 0 ]; then
        current_step=7
      elif [ $rc -eq 1 ]; then
        if echo ",$sel_blocks," | grep -q ",time,"; then
          current_step=5
        else
          current_step=4
        fi
      fi
      ;;
    7) # Done
      step_done
      break
      ;;
  esac
done
