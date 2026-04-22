#!/usr/bin/env bash
# ╔══════════════════════════════════════════╗
# ║  cyberpunk-statusline TUI configurator  ║
# ║  v2 — inspired by Powerlevel10k         ║
# ╚══════════════════════════════════════════╝

# Note: do NOT use set -euo pipefail in interactive TUI scripts.
# set -e kills on arithmetic false, set -u kills on any empty variable.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
THEMES_DIR="$SCRIPT_DIR/themes"
STATUSLINE="$SCRIPT_DIR/statusline.sh"
JQ=$(command -v jq 2>/dev/null || echo "/opt/homebrew/bin/jq")

TOTAL_STEPS=8
source "$SCRIPT_DIR/_lib_tab_state.sh"
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
_preview_5h_reset=$(( $(date +%s) + 2*3600 + 46*60 ))
_preview_7d_reset=$(( $(date +%s) + 4*86400 + 21*3600 ))
SAMPLE_DATA='{
  "session_id": "preview",
  "model": { "id": "claude-opus-4-6", "display_name": "Opus 4.6 (1M)" },
  "workspace": { "current_dir": "'"$SCRIPT_DIR"'" },
  "context_window": { "used_percentage": 58, "remaining_percentage": 42 },
  "rate_limits": {
    "five_hour": { "used_percentage": 76, "resets_at": '"$_preview_5h_reset"' },
    "seven_day": { "used_percentage": 33, "resets_at": '"$_preview_7d_reset"' }
  }
}'

# ── Load existing config (for preselection) ──────────────────────────────
if [ -f "$CONFIG" ]; then
  cur_theme=$("$JQ" -r '.theme // "terminal-glitch"' "$CONFIG")
  cur_symbols=$("$JQ" -r '.symbol_set // "unicode"' "$CONFIG")
  cur_spacing=$("$JQ" -r '.spacing // "ultra-compact"' "$CONFIG")
  cur_separator=$("$JQ" -r '.separator // ""' "$CONFIG")
  cur_style=$("$JQ" -r '.style // "rainbow"' "$CONFIG")
  cur_head=$("$JQ" -r '.head // "sharp"' "$CONFIG")
  cur_tail=$("$JQ" -r '.tail // "sharp"' "$CONFIG")
  cur_bar_width=$("$JQ" -r '.bar_width // 10' "$CONFIG")
  cur_bar_filled=$("$JQ" -r '.bar_filled // ""' "$CONFIG")
  cur_bar_empty=$("$JQ" -r '.bar_empty // ""' "$CONFIG")
  cur_show_icons=$("$JQ" -r '.show_icons // true' "$CONFIG")
  cur_time_format=$("$JQ" -r '.time_format // "24h"' "$CONFIG")
  cur_blocks=$("$JQ" -r '.blocks // ["model","context","rate_5h","rate_7d","directory","git","time"] | .[]' "$CONFIG")
else
  cur_theme="terminal-glitch"
  cur_symbols="unicode"
  cur_spacing="ultra-compact"
  cur_separator=""
  cur_style="rainbow"
  cur_head="sharp"
  cur_tail="sharp"
  cur_bar_width=10
  cur_bar_filled="■"
  cur_bar_empty="□"
  cur_show_icons="true"
  cur_time_format="24h"
  cur_blocks="model context rate_5h rate_7d directory git time"
fi

# Previous tab_state.enabled — used in apply to decide install/remove
if [ -f "$CONFIG" ]; then
  cur_tab_state_enabled=$("$JQ" -r '.tab_state.enabled // false' "$CONFIG" 2>/dev/null)
else
  cur_tab_state_enabled="false"
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
sel_bar_filled=""
sel_bar_empty=""
sel_show_icons=""
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
  sel_bar_filled=""
  sel_bar_empty=""
  sel_show_icons=""
  sel_time_format=""
  current_step=1
}

# ══════════════════════════════════════════════════════════════════════════
# ── DRAWING HELPERS ──────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════

draw_header() {
  local step="$1" total="$2" title="$3"
  tput clear
  printf '\033[2m  ===================================\033[0m\n'
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
# Usage: render_preview theme symbol_set spacing separator blocks_csv [bar_width] [time_format] [style] [head] [tail] [bar_filled] [bar_empty]
render_preview() {
  local theme="$1" symbol_set="$2" spacing="$3" separator="$4" blocks_csv="$5"
  local bar_width="${6:-10}" time_format="${7:-24h}"
  local style="${8:-classic}" head="${9:-sharp}" tail="${10:-sharp}"
  local bar_filled="${11:-${sel_bar_filled:-${cur_bar_filled:-}}}"
  local bar_empty="${12:-${sel_bar_empty:-${cur_bar_empty:-}}}"
  local show_icons="${13:-${sel_show_icons:-${cur_show_icons:-true}}}"

  local tmp_config=$(mktemp)
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

  # Build optional bar_filled/bar_empty JSON fields
  local bar_fields=""
  if [ -n "$bar_filled" ]; then
    bar_fields="$(printf '\n  "bar_filled": "%s",\n  "bar_empty": "%s",' "$bar_filled" "$bar_empty")"
  fi

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
  "bar_width": $bar_width,${bar_fields}
  "show_icons": $show_icons,
  "time_format": "$time_format"
}
CONF

  local output
  output=$(CONFIG_OVERRIDE="$tmp_config" bash "$STATUSLINE" <<< "$SAMPLE_DATA" 2>/dev/null) || true
  echo -e "$output"
}

# Get current style params for preview
_cur_style() { echo "${sel_style:-${cur_style:-rainbow}}"; }
_cur_head()  { echo "${sel_head:-${cur_head:-sharp}}"; }
_cur_tail()  { echo "${sel_tail:-${cur_tail:-sharp}}"; }

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
    "$(_cur_style)" "$(_cur_head)" "$(_cur_tail)" \
    "${sel_bar_filled:-${cur_bar_filled:-}}" "${sel_bar_empty:-${cur_bar_empty:-}}"
}

# Draw preview at a given row (default: content_row below content)
# Usage: draw_preview [--row N] theme symbols ...
draw_preview() {
  local preview_row
  if [ "$1" = "--row" ]; then
    preview_row="$2"
    shift 2
  else
    preview_row=$((TERM_LINES - 4))
  fi
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

# ── Step 1b: Show icons ──────────────────────────────────────────────────
step_show_icons() {
  draw_header 5 $TOTAL_STEPS "Show icons in blocks?"

  local blocks_csv="${sel_blocks:-$(echo "$cur_blocks" | tr ' ' '\n' | tr '\n' ',' | sed 's/,$//')}"
  local _pd=$(mktemp -d)
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" \
      "${sel_spacing:-$cur_spacing}" "${sel_separator:-$cur_separator}" \
      "$blocks_csv" "${sel_bar_width:-$cur_bar_width}" "${sel_time_format:-$cur_time_format}" \
      "$(_cur_style)" "$(_cur_head)" "$(_cur_tail)" \
      "${sel_bar_filled:-${cur_bar_filled:-}}" "${sel_bar_empty:-${cur_bar_empty:-}}" "true" > "$_pd/0" ) &
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" \
      "${sel_spacing:-$cur_spacing}" "${sel_separator:-$cur_separator}" \
      "$blocks_csv" "${sel_bar_width:-$cur_bar_width}" "${sel_time_format:-$cur_time_format}" \
      "$(_cur_style)" "$(_cur_head)" "$(_cur_tail)" \
      "${sel_bar_filled:-${cur_bar_filled:-}}" "${sel_bar_empty:-${cur_bar_empty:-}}" "false" > "$_pd/1" ) &
  wait
  local p_yes=$(cat "$_pd/0") p_no=$(cat "$_pd/1"); rm -rf "$_pd"

  ask_choice \
    "Yes — show icons|$p_yes" \
    "No  — text only|$p_no"

  local rc=$?
  if [ $rc -eq 1 ]; then return 2; fi

  if [ "$CHOICE_RESULT" -eq 1 ]; then
    sel_show_icons="true"
  else
    sel_show_icons="false"
  fi
  return 0
}

# ── Step 2: Block selection ──────────────────────────────────────────────
step_blocks() {
  draw_header 2 $TOTAL_STEPS "Which blocks to show? (Space to toggle)"

  local block_ids=("model" "context" "rate_5h" "rate_7d" "cost" "directory" "git" "time")
  local block_descs=(
    "model       — Model name (e.g., Opus 4.6)"
    "context     — Context window usage %"
    "rate_5h     — 5-hour rate limit %"
    "rate_7d     — 7-day rate limit %"
    "cost        — Daily cost (requires ccusage)"
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
  local preview_dirty=true

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

    # Only refresh preview when blocks changed
    if $preview_dirty; then
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

      draw_preview --row $((5 + count + 1)) "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" \
        "${sel_spacing:-$cur_spacing}" "${sel_separator:-$cur_separator}" \
        "$blocks_csv" "${sel_bar_width:-$cur_bar_width}" "${sel_time_format:-$cur_time_format}"
      preview_dirty=false
    fi

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
        preview_dirty=true
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
  local _pd=$(mktemp -d)
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "normal" "$separator" "$blocks_csv" "$bw" > "$_pd/0" ) &
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "compact" "$separator" "$blocks_csv" "$bw" > "$_pd/1" ) &
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "ultra-compact" "$separator" "$blocks_csv" "$bw" > "$_pd/2" ) &
  wait; p_normal=$(cat "$_pd/0"); p_compact=$(cat "$_pd/1"); p_ultra=$(cat "$_pd/2"); rm -rf "$_pd"

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
  local _pd=$(mktemp -d)
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "$separator" "$blocks_csv" 6 > "$_pd/0" ) &
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "$separator" "$blocks_csv" 10 > "$_pd/1" ) &
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "$separator" "$blocks_csv" 16 > "$_pd/2" ) &
  wait; p_short=$(cat "$_pd/0"); p_medium=$(cat "$_pd/1"); p_long=$(cat "$_pd/2"); rm -rf "$_pd"

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

# ── Step 3c: Bar style (conditional) ────────────────────────────────────
step_bar_style() {
  # Only show if spacing uses bars
  if [ "$sel_spacing" = "ultra-compact" ]; then
    sel_bar_filled="${cur_bar_filled:-}"
    sel_bar_empty="${cur_bar_empty:-}"
    return 0
  fi

  draw_header 3 $TOTAL_STEPS "Progress bar style:"

  local blocks_csv="${sel_blocks:-$(echo "$cur_blocks" | tr ' ' '\n' | tr '\n' ',' | sed 's/,$//')}"
  local separator="${sel_separator:-$cur_separator}"
  local bw="${sel_bar_width:-$cur_bar_width}"
  local tf="${sel_time_format:-$cur_time_format}"

  # Each option: "label|preview" — preview uses specific bar chars
  local styles_filled=("■" "●" "◆" "◼" "▮" "⬢")
  local styles_empty=("□" "○" "◇" "◻" "▯" "⬡")
  local styles_label=("Square ■□" "Circle ●○" "Diamond ◆◇" "Medium Square ◼◻" "Rectangle ▮▯" "Hexagon ⬢⬡")

  local _pd=$(mktemp -d)
  for i in "${!styles_filled[@]}"; do
    ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" \
        "$sel_spacing" "$separator" "$blocks_csv" "$bw" "$tf" \
        "$(_cur_style)" "$(_cur_head)" "$(_cur_tail)" \
        "${styles_filled[$i]}" "${styles_empty[$i]}" > "$_pd/$i" ) &
  done
  wait
  local args=()
  for i in "${!styles_label[@]}"; do
    args+=("${styles_label[$i]}|$(cat "$_pd/$i")")
  done
  rm -rf "$_pd"

  ask_choice "${args[@]}"

  local rc=$?
  if [ $rc -eq 1 ]; then return 2; fi

  local idx=$((CHOICE_RESULT - 1))
  sel_bar_filled="${styles_filled[$idx]}"
  sel_bar_empty="${styles_empty[$idx]}"
  return 0
}

# ── Step 4: Prompt style ─────────────────────────────────────────────────
step_prompt_style() {
  draw_header 4 $TOTAL_STEPS "Prompt style:"

  local blocks_csv="${sel_blocks:-$(echo "$cur_blocks" | tr ' ' '\n' | tr '\n' ',' | sed 's/,$//')}"
  local bw="${sel_bar_width:-$cur_bar_width}"

  local p_classic p_rainbow _pd=$(mktemp -d)
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "│" "$blocks_csv" "$bw" "24h" "classic" "" "" > "$_pd/0" ) &
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "" "$blocks_csv" "$bw" "24h" "rainbow" "sharp" "sharp" > "$_pd/1" ) &
  wait; p_classic=$(cat "$_pd/0"); p_rainbow=$(cat "$_pd/1"); rm -rf "$_pd"

  ask_choice \
    "Rainbow|$p_rainbow" \
    "Classic|$p_classic"

  local rc=$?
  if [ $rc -eq 1 ]; then return 2; fi

  if [ "$CHOICE_RESULT" -eq 1 ]; then
    sel_style="rainbow"
  else
    sel_style="classic"
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

  local p1 p2 p3 p4 p5 _pd=$(mktemp -d)
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "│" "$blocks_csv" "$bw" "24h" "classic" > "$_pd/0" ) &
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "/" "$blocks_csv" "$bw" "24h" "classic" > "$_pd/1" ) &
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "·" "$blocks_csv" "$bw" "24h" "classic" > "$_pd/2" ) &
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" " " "$blocks_csv" "$bw" "24h" "classic" > "$_pd/3" ) &
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "›" "$blocks_csv" "$bw" "24h" "classic" > "$_pd/4" ) &
  wait; p1=$(cat "$_pd/0"); p2=$(cat "$_pd/1"); p3=$(cat "$_pd/2"); p4=$(cat "$_pd/3"); p5=$(cat "$_pd/4"); rm -rf "$_pd"

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

  local p1 p2 p3 p4 _pd=$(mktemp -d)
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "" "$blocks_csv" "$bw" "$tf" "rainbow" "flat" "${sel_tail:-sharp}" > "$_pd/0" ) &
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "" "$blocks_csv" "$bw" "$tf" "rainbow" "sharp" "${sel_tail:-sharp}" > "$_pd/1" ) &
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "" "$blocks_csv" "$bw" "$tf" "rainbow" "slanted" "${sel_tail:-sharp}" > "$_pd/2" ) &
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "" "$blocks_csv" "$bw" "$tf" "rainbow" "rounded" "${sel_tail:-sharp}" > "$_pd/3" ) &
  wait; p1=$(cat "$_pd/0"); p2=$(cat "$_pd/1"); p3=$(cat "$_pd/2"); p4=$(cat "$_pd/3"); rm -rf "$_pd"

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

  local p1 p2 p3 p4 _pd=$(mktemp -d)
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "" "$blocks_csv" "$bw" "$tf" "rainbow" "$sel_head" "flat" > "$_pd/0" ) &
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "" "$blocks_csv" "$bw" "$tf" "rainbow" "$sel_head" "sharp" > "$_pd/1" ) &
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "" "$blocks_csv" "$bw" "$tf" "rainbow" "$sel_head" "slanted" > "$_pd/2" ) &
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "" "$blocks_csv" "$bw" "$tf" "rainbow" "$sel_head" "rounded" > "$_pd/3" ) &
  wait; p1=$(cat "$_pd/0"); p2=$(cat "$_pd/1"); p3=$(cat "$_pd/2"); p4=$(cat "$_pd/3"); rm -rf "$_pd"

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

  local p1 p2 p3 p4 p5 p6 _pd=$(mktemp -d)
  local _sty=$(_cur_style) _hd=$(_cur_head) _tl=$(_cur_tail)
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "$separator" "$blocks_csv" "$bw" "24h" "$_sty" "$_hd" "$_tl" > "$_pd/0" ) &
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "$separator" "$blocks_csv" "$bw" "12h" "$_sty" "$_hd" "$_tl" > "$_pd/1" ) &
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "$separator" "$blocks_csv" "$bw" "24h-no-sec" "$_sty" "$_hd" "$_tl" > "$_pd/2" ) &
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "$separator" "$blocks_csv" "$bw" "12h-no-sec" "$_sty" "$_hd" "$_tl" > "$_pd/3" ) &
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "$separator" "$blocks_csv" "$bw" "24h-date" "$_sty" "$_hd" "$_tl" > "$_pd/4" ) &
  ( render_preview "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" "$sel_spacing" "$separator" "$blocks_csv" "$bw" "12h-date" "$_sty" "$_hd" "$_tl" > "$_pd/5" ) &
  wait; p1=$(cat "$_pd/0"); p2=$(cat "$_pd/1"); p3=$(cat "$_pd/2"); p4=$(cat "$_pd/3"); p5=$(cat "$_pd/4"); p6=$(cat "$_pd/5"); rm -rf "$_pd"

  ask_choice \
    "24-hour          (16:23:42)|$p1" \
    "12-hour          (04:23:42 PM)|$p2" \
    "24-hour (short)  (16:23)|$p3" \
    "12-hour (short)  (4:23 PM)|$p4" \
    "24-hour + date   (04/20 16:23)|$p5" \
    "12-hour + date   (04/20 4:23 PM)|$p6"

  local rc=$?
  if [ $rc -eq 1 ]; then return 2; fi

  local values=("24h" "12h" "24h-no-sec" "12h-no-sec" "24h-date" "12h-date")
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

  # Pre-generate all theme previews in parallel (one-time cost)
  local preview_dir=$(mktemp -d)
  for i in "${!all_ids[@]}"; do
    if [ "${all_ids[$i]}" != "__header__" ]; then
      ( render_preview "${all_ids[$i]}" "${sel_symbols:-$cur_symbols}" \
          "$sel_spacing" "$sel_separator" "$blocks_csv" "$bw" "$tf" \
          "$(_cur_style)" "$(_cur_head)" "$(_cur_tail)" \
          > "$preview_dir/$i" ) &
    fi
  done
  wait
  local all_previews=()
  for i in "${!all_ids[@]}"; do
    if [ "${all_ids[$i]}" = "__header__" ]; then
      all_previews+=("")
    else
      all_previews+=("$(cat "$preview_dir/$i")")
    fi
  done
  rm -rf "$preview_dir"

  draw_footer "j/k move · Enter select · r restart · b back · q quit"

  # Display all themes with inline previews (static, drawn once)
  # Each theme takes 2 rows: label + preview; headers take 1 row
  local row_map=()  # maps index -> starting row
  local row=5
  for i in "${!all_labels[@]}"; do
    row_map+=("$row")
    if [ "${all_ids[$i]}" = "__header__" ]; then
      tput cup "$row" 0
      printf '\033[K \033[2;33m%s\033[0m' "${all_labels[$i]}"
      row=$((row + 1))
    else
      tput cup "$row" 0
      printf '\033[K   \033[2m%s\033[0m' "${all_labels[$i]}"
      row=$((row + 1))
      tput cup "$row" 0
      printf '\033[K   '
      echo -e "${all_previews[$i]}"
      printf '\033[0m'
      row=$((row + 1))
    fi
  done

  local prev_cursor=-1
  while true; do
    if [ "$cursor" != "$prev_cursor" ]; then
      # Un-highlight previous
      if [ "$prev_cursor" -ge 0 ] && [ "${all_ids[$prev_cursor]}" != "__header__" ]; then
        tput cup "${row_map[$prev_cursor]}" 0
        printf '\033[K   \033[2m%s\033[0m' "${all_labels[$prev_cursor]}"
      fi
      # Highlight current
      tput cup "${row_map[$cursor]}" 0
      printf '\033[K \033[1;36m❯\033[0m \033[1m%s\033[0m' "${all_labels[$cursor]}"
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

# ── Step 8: iTerm2 tab tinting ───────────────────────────────────────────
step_tab_state() {
  draw_header 8 $TOTAL_STEPS "iTerm2 tab tinting"

  # Non-iTerm2 → auto-skip
  if [ "${TERM_PROGRAM:-}" != "iTerm.app" ]; then
    printf '\n  \033[2mDetected terminal: %s. Tab tinting is iTerm2-only — skipping.\033[0m\n\n' \
      "${TERM_PROGRAM:-unknown}"
    sel_tab_state_enabled="false"
    sel_tab_state_running="accent_1"
    sel_tab_state_waiting="warning"
    sel_tab_state_idle="accent_3"
    sel_tab_state_error="alert"
    printf '  \033[2mPress any key to continue...\033[0m'
    read -rsn1
    return 0
  fi

  # Foreign hook detection warning
  local foreign
  foreign=$(_detect_foreign_tab_state_hooks "$HOME/.claude/scripts/tab-state.sh" 2>/dev/null)
  if [ -n "$foreign" ]; then
    printf '\n  \033[33m⚠ Existing tab-state hooks detected:\033[0m\n'
    printf '%s\n' "$foreign" | sed 's/^/    /'
    printf '  \033[2mEnabling will append our hooks — recommend removing the other first.\033[0m\n\n'
  fi

  ask_choice \
    "Enable|Claude Code hooks will tint your iTerm2 tab background per session state." \
    "Skip (default)|Leave ~/.claude/settings.json unchanged."

  local rc=$?
  if [ $rc -eq 1 ]; then return 2; fi

  if [ "$CHOICE_RESULT" = "2" ]; then
    sel_tab_state_enabled="false"
    sel_tab_state_running="accent_1"
    sel_tab_state_waiting="warning"
    sel_tab_state_idle="accent_3"
    sel_tab_state_error="alert"
    return 0
  fi

  sel_tab_state_enabled="true"

  # Theme palette we allow for tab tinting (exclude bg_primary/bg_panel)
  local palettes=(accent_1 accent_2 accent_3 warning alert dim)

  # Read current theme's color hex values for swatch display (parallel arrays)
  local theme_file="$SCRIPT_DIR/themes/${sel_theme}.json"
  local hex_vals=()
  for p in "${palettes[@]}"; do
    hex_vals+=("$("$JQ" -r --arg k "$p" '.colors[$k] // ""' "$theme_file")")
  done

  _tab_state_ask_palette() {
    local state_label="$1" default_palette="$2" out_var="$3"
    draw_header 8 $TOTAL_STEPS "Tab tinting — ${state_label}"

    local swatches=()
    local default_idx=1
    local i=0
    for p in "${palettes[@]}"; do
      i=$((i + 1))
      local hex="${hex_vals[$((i - 1))]}"
      # ANSI 24-bit swatch block (four ████ chars in the palette color)
      local r=$((16#${hex:1:2})) g=$((16#${hex:3:2})) b=$((16#${hex:5:2}))
      local swatch; swatch=$(printf '\033[38;2;%d;%d;%dm████\033[0m' "$r" "$g" "$b")
      local label; label=$(printf '%-10s %s  %s' "$p" "$swatch" "$hex")
      swatches+=("$label|")
      [ "$p" = "$default_palette" ] && default_idx=$i
    done

    ask_choice "${swatches[@]}"
    local rc=$?
    if [ $rc -eq 1 ]; then return 1; fi
    printf -v "$out_var" '%s' "${palettes[$((CHOICE_RESULT - 1))]}"
  }

  _tab_state_ask_palette "Running (UserPromptSubmit / PreToolUse)" accent_1 sel_tab_state_running || return 2
  _tab_state_ask_palette "Waiting (Notification)"                  warning  sel_tab_state_waiting || return 2
  _tab_state_ask_palette "Idle (Stop / SessionStart)"              accent_3 sel_tab_state_idle    || return 2
  _tab_state_ask_palette "Error"                                   alert    sel_tab_state_error   || return 2
  return 0
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
  local bar_filled_field="" bar_empty_field=""
  if [ -n "$sel_bar_filled" ]; then
    bar_filled_field="$(printf '\n  "bar_filled": "%s",' "$sel_bar_filled")"
    bar_empty_field="$(printf '\n  "bar_empty": "%s",' "$sel_bar_empty")"
  fi

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
  "bar_width": $bar_width,${bar_filled_field}${bar_empty_field}
  "show_icons": $sel_show_icons,
  "time_format": "$time_format",
  "tab_state": {
    "enabled": $sel_tab_state_enabled,
    "running": "$sel_tab_state_running",
    "waiting": "$sel_tab_state_waiting",
    "idle": "$sel_tab_state_idle",
    "error": "$sel_tab_state_error"
  }
}
CONF
)
  echo "$config_content" > "$CONFIG"

  # Apply tab-state hook changes based on enable transition
  if [ "$sel_tab_state_enabled" = "true" ] && [ "$cur_tab_state_enabled" != "true" ]; then
    if _install_tab_state_hooks "$SCRIPT_DIR"; then
      printf '  \033[32m✓\033[0m tab-state hooks installed to ~/.claude/settings.json\n'
    else
      printf '  \033[31m✗\033[0m tab-state hooks install failed — check ~/.claude/settings.json\n'
    fi
  elif [ "$sel_tab_state_enabled" != "true" ] && [ "$cur_tab_state_enabled" = "true" ]; then
    if _remove_tab_state_hooks; then
      printf '  \033[32m✓\033[0m tab-state hooks removed\n'
    else
      printf '  \033[31m✗\033[0m tab-state hooks removal failed\n'
    fi
  fi

  # Show completion screen
  tput clear
  printf '\033[1;32m  ✔ Configuration saved!\033[0m\n'
  printf '\033[2m  ===================================\033[0m\n'
  echo ""
  echo -e "\033[2mTheme:      \033[0m $sel_theme"
  echo -e "\033[2mSymbols:    \033[0m $sel_symbols"
  echo -e "\033[2mIcons:      \033[0m $sel_show_icons"
  echo -e "\033[2mBlocks:     \033[0m ${block_count}/8 enabled"
  echo -e "\033[2mSpacing:    \033[0m $sel_spacing"
  echo -e "\033[2mStyle:      \033[0m $sel_style"
  if [ "$sel_style" = "rainbow" ]; then
    echo -e "\033[2mHead:       \033[0m $sel_head"
    echo -e "\033[2mTail:       \033[0m $sel_tail"
  else
    echo -e "\033[2mSeparator:  \033[0m $sel_separator"
  fi
  if [ "$sel_spacing" != "ultra-compact" ]; then
    echo -e "\033[2mBar width:  \033[0m $bar_width"
    if [ -n "$sel_bar_filled" ]; then
      echo -e "\033[2mBar style:  \033[0m ${sel_bar_filled}${sel_bar_empty}"
    fi
  fi
  echo -e "\033[2mTime format:\033[0m $time_format"
  echo -e "\033[2mTab tint:   \033[0m $sel_tab_state_enabled"
  if [ "$sel_tab_state_enabled" = "true" ]; then
    echo -e "\033[2m  running:  \033[0m $sel_tab_state_running"
    echo -e "\033[2m  waiting:  \033[0m $sel_tab_state_waiting"
    echo -e "\033[2m  idle:     \033[0m $sel_tab_state_idle"
    echo -e "\033[2m  error:    \033[0m $sel_tab_state_error"
  fi
  echo ""
  render_preview "$sel_theme" "$sel_symbols" "$sel_spacing" "$sel_separator" \
    "$sel_blocks" "$bar_width" "$time_format" "$sel_style" "$sel_head" "$sel_tail" \
    "$sel_bar_filled" "$sel_bar_empty" "$sel_show_icons"
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
    3) # Spacing + bar_width + bar_style
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
          step_bar_style
          rc=$?
          if [ $rc -eq 2 ]; then
            restart_wizard
          elif [ $rc -eq 0 ]; then
            current_step=4
          fi
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
    5) # Time format (conditional) + show icons
      step_time_format
      rc=$?
      if [ $rc -eq 2 ]; then
        restart_wizard
      elif [ $rc -eq 0 ]; then
        step_show_icons
        rc=$?
        if [ $rc -eq 2 ]; then
          restart_wizard
        elif [ $rc -eq 0 ]; then
          current_step=6
        fi
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
    7) # Tab state (iTerm2 tinting)
      step_tab_state
      rc=$?
      if [ $rc -eq 2 ]; then
        restart_wizard
      elif [ $rc -eq 0 ]; then
        current_step=8
      fi
      ;;
    8) # Done
      step_done
      break
      ;;
  esac
done
