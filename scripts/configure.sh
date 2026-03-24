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
  [ -n "${PREVIEW_TMP_CONFIG:-}" ] && rm -f "$PREVIEW_TMP_CONFIG" 2>/dev/null
}
trap cleanup EXIT INT TERM

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
  "blocks": [$blocks_json],
  "bar_width": 10
}
CONF

  local output
  output=$(CONFIG_OVERRIDE="$tmp_config" bash "$STATUSLINE" <<< "$SAMPLE_DATA" 2>/dev/null) || true
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

# ══════════════════════════════════════════════════════════════════════════
# ── STEP FUNCTIONS ───────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════

step_symbols() {
  draw_header 1 5 "Which symbols display correctly?"

  local options=(
    "Nerd Font:  󰚩 󰍛  󰔟"
    "Unicode:   ⬡ ◈ ⚡ ⟳ ⌁ ⎇ ◷ █ ░"
    "ASCII:     [M] [C] [!] [~] [D] [G] [T] # ."
  )
  local values=("nerd" "unicode" "ascii")

  # Find initial cursor from existing config
  local init=1  # default to unicode
  for i in "${!values[@]}"; do
    if [ "${values[$i]}" = "$cur_symbols" ]; then
      init=$i
      break
    fi
  done

  draw_footer "↑↓ move · Enter select · q quit"
  menu_select "$init" "${options[@]}"

  if [ "$MENU_RESULT" -eq -1 ]; then
    return 1  # can't go back from step 1
  fi

  sel_symbols="${values[$MENU_RESULT]}"
}

step_theme() {
  draw_header 2 5 "Choose your theme:"

  # Build theme list from JSON files (exclude directories like custom-example)
  local theme_files=()
  local theme_ids=()
  local theme_labels=()

  # Cyberpunk themes (ordered)
  local cyberpunk_order=("terminal-glitch" "neon-classic" "synthwave-sunset" "blade-runner" "retrowave-chrome")
  # Classic themes (ordered)
  local classic_order=("dracula" "tokyo-night" "catppuccin-mocha" "rose-pine" "nord" "one-dark" "gruvbox-dark")

  local all_labels=()
  local all_ids=()
  local group_indices=()  # indices where group headers should appear

  # Cyberpunk group
  group_indices+=(0)
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
  group_indices+=("${#all_labels[@]}")
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

  # Determine blocks CSV for preview
  local blocks_csv
  if [ -n "$sel_blocks" ]; then
    blocks_csv="$sel_blocks"
  else
    blocks_csv=$(echo "$cur_blocks" | tr ' ' '\n' | tr '\n' ',' | sed 's/,$//')
  fi
  local spacing="${sel_spacing:-$cur_spacing}"
  local separator="${sel_separator:-$cur_separator}"

  draw_footer "↑↓ move · Enter select · b back · q quit"

  local prev_cursor=-1
  while true; do
    # Draw options (only redraw if cursor moved)
    if [ "$cursor" != "$prev_cursor" ]; then
      for i in "${!all_labels[@]}"; do
        tput cup $((6 + i)) 0
        echo -e "\033[K"
        if [ "${all_ids[$i]}" = "__header__" ]; then
          echo -e " \033[2;33m${all_labels[$i]}\033[0m"
        elif [ "$i" -eq "$cursor" ]; then
          echo -e " \033[1;36m❯\033[0m \033[1m${all_labels[$i]}\033[0m"
        else
          echo -e "   \033[2m${all_labels[$i]}\033[0m"
        fi
      done

      # Live preview
      if [ "${all_ids[$cursor]}" != "__header__" ]; then
        draw_preview "${all_ids[$cursor]}" "${sel_symbols:-$cur_symbols}" "$spacing" "$separator" "$blocks_csv"
      fi
      prev_cursor=$cursor
    fi

    read_key
    case "$KEY" in
      up)
        local prev=$cursor
        (( cursor > 0 )) && (( cursor-- ))
        # Skip headers — restore if stuck
        while [ "$cursor" -ge 0 ] && [ "${all_ids[$cursor]}" = "__header__" ]; do
          (( cursor > 0 )) && (( cursor-- )) || { cursor=$prev; break; }
        done
        ;;
      down)
        local prev=$cursor
        (( cursor < count - 1 )) && (( cursor++ ))
        # Skip headers — restore if stuck
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
      b) return 1 ;;
      q) cleanup; exit 0 ;;
    esac
  done
}

step_blocks() {
  draw_header 3 5 "Which blocks to show? (Space to toggle)"

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

  # Build initial states from existing config
  local states=()
  for bid in "${block_ids[@]}"; do
    if echo " $cur_blocks " | grep -q " $bid "; then
      states+=("1")
    else
      states+=("0")
    fi
  done

  draw_footer "↑↓ move · Space toggle · Enter confirm · b back · q quit"

  local cursor=0
  local count=${#block_descs[@]}

  while true; do
    for i in "${!block_descs[@]}"; do
      tput cup $((6 + i)) 0
      echo -e "\033[K"
      local check_mark
      if [ "${states[$i]}" = "1" ]; then
        check_mark="\033[32m✔\033[0m"
      else
        check_mark="\033[2m✗\033[0m"
      fi
      if [ "$i" -eq "$cursor" ]; then
        echo -e " \033[1;36m❯\033[0m${check_mark} \033[1m${block_descs[$i]}\033[0m"
      else
        echo -e "  ${check_mark} \033[2m${block_descs[$i]}\033[0m"
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

    draw_preview "${sel_theme:-$cur_theme}" "${sel_symbols:-$cur_symbols}" "${sel_spacing:-$cur_spacing}" "${sel_separator:-$cur_separator}" "$blocks_csv"

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
        # Require at least 1 block
        local any_checked=false
        for s in "${states[@]}"; do
          [ "$s" = "1" ] && any_checked=true
        done
        if ! $any_checked; then
          tput cup $((TERM_LINES - 1)) 0
          echo -e "\033[K\033[31mAt least one block must be enabled!\033[0m"
          sleep 1
          draw_footer "↑↓ move · Space toggle · Enter confirm · b back · q quit"
          continue
        fi
        # Build result
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
      b) return 1 ;;
      q) cleanup; exit 0 ;;
    esac
  done
}

step_spacing() {
  draw_header 4 5 "Spacing mode:"

  local options=(
    "Normal        — symbol + label + bar + %"
    "Compact       — symbol + bar + %"
    "Ultra Compact — symbol + % only"
  )
  local values=("normal" "compact" "ultra-compact")

  local init=0
  for i in "${!values[@]}"; do
    if [ "${values[$i]}" = "$cur_spacing" ]; then
      init=$i
      break
    fi
  done

  local blocks_csv="${sel_blocks:-$(echo "$cur_blocks" | tr ' ' '\n' | tr '\n' ',' | sed 's/,$//')}"
  local theme="${sel_theme:-$cur_theme}"
  local symbols="${sel_symbols:-$cur_symbols}"
  local separator="${sel_separator:-$cur_separator}"

  draw_footer "↑↓ move · Enter select · b back · q quit"

  local cursor=$init
  local count=${#options[@]}
  local prev_cursor=-1

  while true; do
    if [ "$cursor" != "$prev_cursor" ]; then
      for i in "${!options[@]}"; do
        tput cup $((6 + i)) 0
        echo -e "\033[K"
        if [ "$i" -eq "$cursor" ]; then
          echo -e " \033[1;36m❯\033[0m \033[1m${options[$i]}\033[0m"
        else
          echo -e "   \033[2m${options[$i]}\033[0m"
        fi
      done
      draw_preview "$theme" "$symbols" "${values[$cursor]}" "$separator" "$blocks_csv"
      prev_cursor=$cursor
    fi

    read_key
    case "$KEY" in
      up)    (( cursor > 0 )) && (( cursor-- )) ;;
      down)  (( cursor < count - 1 )) && (( cursor++ )) ;;
      enter) sel_spacing="${values[$cursor]}"; return 0 ;;
      b)     return 1 ;;
      q)     cleanup; exit 0 ;;
    esac
  done
}

step_separator() {
  draw_header 5 5 "Separator style:"

  local options=(
    "Pipe  │"
    "Slash /"
    "Dot   ·"
    "Space  "
    "Arrow ›"
  )
  local values=("│" "/" "·" " " "›")

  local init=0
  for i in "${!values[@]}"; do
    if [ "${values[$i]}" = "$cur_separator" ]; then
      init=$i
      break
    fi
  done

  local blocks_csv="${sel_blocks:-$(echo "$cur_blocks" | tr ' ' '\n' | tr '\n' ',' | sed 's/,$//')}"
  local theme="${sel_theme:-$cur_theme}"
  local symbols="${sel_symbols:-$cur_symbols}"
  local spacing="${sel_spacing:-$cur_spacing}"

  draw_footer "↑↓ move · Enter select · b back · q quit"

  local cursor=$init
  local count=${#options[@]}
  local prev_cursor=-1

  while true; do
    if [ "$cursor" != "$prev_cursor" ]; then
      for i in "${!options[@]}"; do
        tput cup $((6 + i)) 0
        echo -e "\033[K"
        if [ "$i" -eq "$cursor" ]; then
          echo -e " \033[1;36m❯\033[0m \033[1m${options[$i]}\033[0m"
        else
          echo -e "   \033[2m${options[$i]}\033[0m"
        fi
      done
      draw_preview "$theme" "$symbols" "$spacing" "${values[$cursor]}" "$blocks_csv"
      prev_cursor=$cursor
    fi

    read_key
    case "$KEY" in
      up)    (( cursor > 0 )) && (( cursor-- )) ;;
      down)  (( cursor < count - 1 )) && (( cursor++ )) ;;
      enter) sel_separator="${values[$cursor]}"; return 0 ;;
      b)     return 1 ;;
      q)     cleanup; exit 0 ;;
    esac
  done
}

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

  # Write config
  cat > "$CONFIG" <<CONF
{
  "theme": "$sel_theme",
  "symbol_set": "$sel_symbols",
  "spacing": "$sel_spacing",
  "separator": "$sel_separator",
  "blocks": [$blocks_json],
  "bar_width": 10
}
CONF

  # Show completion screen
  tput clear
  echo -e "\033[1;32m╔══════════════════════════════════════════════════╗\033[0m"
  echo -e "\033[1;32m║   ✔ Configuration saved!                        ║\033[0m"
  echo -e "\033[1;32m╚══════════════════════════════════════════════════╝\033[0m"
  echo ""
  echo -e "\033[2mTheme:    \033[0m $sel_theme"
  echo -e "\033[2mSymbols:  \033[0m $sel_symbols"
  echo -e "\033[2mBlocks:   \033[0m ${block_count}/7 enabled"
  echo -e "\033[2mSpacing:  \033[0m $sel_spacing"
  echo -e "\033[2mSeparator:\033[0m $sel_separator"
  echo ""
  render_preview "$sel_theme" "$sel_symbols" "$sel_spacing" "$sel_separator" "$sel_blocks"
  echo ""
  echo ""
  echo -e "\033[2mYour status line will update on the next refresh.\033[0m"
  echo -e "\033[2mRun\033[0m \033[36mcyberpunk-statusline configure\033[0m \033[2manytime to reconfigure.\033[0m"
  echo ""
  echo -e "\033[2mPress any key to exit.\033[0m"
  read -rsn1
}

# ── Main wizard flow ─────────────────────────────────────────────────────
current_step=1

while true; do
  case $current_step in
    1)
      step_symbols
      if [ -n "$sel_symbols" ]; then
        current_step=2
      fi
      ;;
    2)
      if step_theme; then
        current_step=3
      else
        current_step=1
      fi
      ;;
    3)
      if step_blocks; then
        current_step=4
      else
        current_step=2
      fi
      ;;
    4)
      if step_spacing; then
        current_step=5
      else
        current_step=3
      fi
      ;;
    5)
      if step_separator; then
        current_step=6
      else
        current_step=4
      fi
      ;;
    6)
      step_done
      break
      ;;
  esac
done
