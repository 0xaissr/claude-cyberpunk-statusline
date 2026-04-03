#!/usr/bin/env bash
# ╔══════════════════════════════════════════╗
# ║  cyberpunk-statusline theme previewer   ║
# ╚══════════════════════════════════════════╝
#
# Usage:
#   ./preview.sh              — preview all themes
#   ./preview.sh tokyo-night  — preview + edit a specific theme

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
STATUSLINE="$SCRIPT_DIR/statusline.sh"
THEMES_DIR="$SCRIPT_DIR/themes"
JQ=$(command -v jq 2>/dev/null || echo "/opt/homebrew/bin/jq")

if ! "$JQ" --version >/dev/null 2>&1; then
  echo "Error: jq is required" >&2; exit 1
fi
if [ ! -f "$CONFIG" ]; then
  echo "Error: run ./configure.sh first" >&2; exit 1
fi

# ── Sample data ──────────────────────────────────────────────────────────
_5h_reset=$(( $(date +%s) + 2*3600 + 46*60 ))
_7d_reset=$(( $(date +%s) + 4*86400 + 21*3600 ))
SAMPLE='{
  "model": { "id": "claude-opus-4-6", "display_name": "Opus 4.6 (1M)" },
  "workspace": { "current_dir": "'"$SCRIPT_DIR"'" },
  "context_window": { "used_percentage": 58 },
  "rate_limits": {
    "five_hour": { "used_percentage": 76, "resets_at": '"$_5h_reset"' },
    "seven_day": { "used_percentage": 33, "resets_at": '"$_7d_reset"' }
  }
}'

# ── Read current config (for style/spacing/etc.) ─────────────────────────
render_theme() {
  local theme="$1"
  local tmp=$(mktemp)
  "$JQ" --arg t "$theme" '.theme = $t' "$CONFIG" > "$tmp"
  echo "$SAMPLE" | CONFIG_OVERRIDE="$tmp" bash "$STATUSLINE" 2>/dev/null
  rm -f "$tmp"
}

# ── Theme list ───────────────────────────────────────────────────────────
cyberpunk=("terminal-glitch" "neon-classic" "synthwave-sunset" "blade-runner" "retrowave-chrome" "midnight-phantom")
classic=("dracula" "tokyo-night" "catppuccin-mocha" "rose-pine" "nord" "one-dark" "gruvbox-dark")

# ══════════════════════════════════════════════════════════════════════════
# Mode 1: Preview all themes
# ══════════════════════════════════════════════════════════════════════════
preview_all() {
  echo ""
  echo -e "  \033[1;36mCYBERPUNK STATUSLINE — THEME PREVIEW\033[0m"
  echo -e "  \033[2m=====================================\033[0m"
  echo ""

  # Generate all previews in parallel
  local _pd=$(mktemp -d)
  local all_themes=("${cyberpunk[@]}" "${classic[@]}")
  for i in "${!all_themes[@]}"; do
    ( render_theme "${all_themes[$i]}" > "$_pd/$i" ) &
  done
  wait

  # Current theme
  local current_theme=$("$JQ" -r '.theme // ""' "$CONFIG")

  # Build numbered list with theme IDs
  local all_ids=()
  local all_names=()
  local num=1

  _print_theme() {
    local t="$1" idx="$2"
    local name=$("$JQ" -r '.name // "'"$t"'"' "$THEMES_DIR/$t.json" 2>/dev/null)
    all_ids+=("$t")
    all_names+=("$name")

    local marker="  "
    if [ "$t" = "$current_theme" ]; then
      marker="\033[32m▸ \033[0m"
    fi

    local label="($num)"
    local display_width=$(echo -n "$name" | wc -m)
    local pad=$((22 - display_width))
    [ "$pad" -lt 0 ] && pad=0
    printf "  ${marker}\033[2m%-4s\033[0m\033[1m%s%*s\033[0m " "$label" "$name" "$pad" ""
    echo -e "$(cat "$_pd/$idx")"
    num=$((num + 1))
  }

  echo -e "  \033[2;33m── Cyberpunk ──\033[0m"
  local idx=0
  for t in "${cyberpunk[@]}"; do
    _print_theme "$t" "$idx"
    idx=$((idx + 1))
  done

  echo ""
  echo -e "  \033[2;33m── Classic ──\033[0m"
  for t in "${classic[@]}"; do
    _print_theme "$t" "$idx"
    idx=$((idx + 1))
  done

  rm -rf "$_pd"
  echo ""
  echo -e "  \033[2mCurrent: \033[1;36m${current_theme}\033[0m"
  echo ""

  # Prompt for selection
  printf "  Select theme [1-%d / e <name> to edit / q to quit]: " "${#all_ids[@]}"
  read -r choice

  case "$choice" in
    q|quit) return ;;
    e\ *)
      local edit_name="${choice#e }"
      edit_theme "$edit_name"
      ;;
    [0-9]*)
      local sel=$((choice - 1))
      if [ "$sel" -ge 0 ] && [ "$sel" -lt "${#all_ids[@]}" ]; then
        local selected="${all_ids[$sel]}"
        "$JQ" --arg t "$selected" '.theme = $t' "$CONFIG" > /tmp/_cfg_preview.json \
          && mv /tmp/_cfg_preview.json "$CONFIG"
        echo -e "  \033[32m✔ Theme set to ${all_names[$sel]} ($selected). Restart Claude Code to apply.\033[0m"
      else
        echo -e "  \033[31mInvalid selection.\033[0m"
      fi
      ;;
    "") return ;;
    *) echo -e "  \033[31mUnknown command: $choice\033[0m" ;;
  esac
}

# ══════════════════════════════════════════════════════════════════════════
# Mode 2: Preview + edit a specific theme
# ══════════════════════════════════════════════════════════════════════════
edit_theme() {
  local theme="$1"
  local theme_file="$THEMES_DIR/$theme.json"

  if [ ! -f "$theme_file" ]; then
    echo "Error: theme '$theme' not found in $THEMES_DIR/" >&2
    exit 1
  fi

  while true; do
    echo ""
    echo -e "  \033[1;36m$theme\033[0m — \033[2m$theme_file\033[0m"
    echo -e "  \033[2m=====================================\033[0m"
    echo ""

    # Show current colors
    echo -e "  \033[2mColors:\033[0m"
    local colors=("bg_primary" "bg_panel" "accent_1" "accent_2" "accent_3" "warning" "alert" "separator" "dim")
    for c in "${colors[@]}"; do
      local hex=$("$JQ" -r ".colors.$c // \"\"" "$theme_file")
      # Show a color swatch using background color
      local r=$((16#${hex:1:2})) g=$((16#${hex:3:2})) b=$((16#${hex:5:2}))
      printf "    \033[48;2;%d;%d;%dm    \033[0m  \033[1m%-14s\033[0m %s\n" "$r" "$g" "$b" "$c" "$hex"
    done
    echo ""

    # Show preview
    echo -e "  \033[2mPreview:\033[0m"
    printf "    "
    render_theme "$theme"
    echo ""

    # Menu
    echo ""
    echo -e "  \033[2mCommands:\033[0m"
    echo -e "    \033[1me <color> <hex>\033[0m  — edit color (e.g. \033[2me accent_1 #FF00FF\033[0m)"
    echo -e "    \033[1ma\033[0m               — apply as current theme"
    echo -e "    \033[1mq\033[0m               — quit"
    echo ""
    printf "  > "
    read -r cmd arg1 arg2

    case "$cmd" in
      e|edit)
        if [ -z "$arg1" ] || [ -z "$arg2" ]; then
          echo -e "  \033[31mUsage: e <color_name> <#hex>\033[0m"
          continue
        fi
        # Validate hex
        if ! echo "$arg2" | grep -qE '^#[0-9A-Fa-f]{6}$'; then
          echo -e "  \033[31mInvalid hex color: $arg2 (expected #RRGGBB)\033[0m"
          continue
        fi
        # Update color
        "$JQ" --arg k "$arg1" --arg v "$arg2" '.colors[$k] = $v' "$theme_file" > /tmp/_theme_edit.json \
          && mv /tmp/_theme_edit.json "$theme_file"
        echo -e "  \033[32m✔ $arg1 → $arg2\033[0m"
        ;;
      a|apply)
        "$JQ" --arg t "$theme" '.theme = $t' "$CONFIG" > /tmp/_cfg_edit.json \
          && mv /tmp/_cfg_edit.json "$CONFIG"
        echo -e "  \033[32m✔ Theme set to $theme. Restart Claude Code to apply.\033[0m"
        ;;
      q|quit|exit)
        break
        ;;
      "")
        continue
        ;;
      *)
        echo -e "  \033[31mUnknown command: $cmd\033[0m"
        ;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════════════
# ── Main ─────────────────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════
if [ -n "$1" ]; then
  edit_theme "$1"
else
  preview_all
fi
