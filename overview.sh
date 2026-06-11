#!/usr/bin/env bash
# cyberpunk-statusline feature overview

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
STATUSLINE="$SCRIPT_DIR/statusline.sh"
THEMES_DIR="$SCRIPT_DIR/themes"
JQ=$(command -v jq 2>/dev/null || echo "/opt/homebrew/bin/jq")
source "$SCRIPT_DIR/core/burn-rate.sh"

# ── Colors ────────────────────────────────────────────────────────────────
C='\033[1;36m'  # cyan bold
G='\033[1;32m'  # green bold
Y='\033[1;33m'  # yellow bold
M='\033[1;35m'  # magenta bold
D='\033[2m'     # dim
B='\033[1m'     # bold
R='\033[0m'     # reset

# ── Current config ────────────────────────────────────────────────────────
if [ -f "$CONFIG" ]; then
  cfg_theme=$("$JQ" -r '.theme // "?"' "$CONFIG")
  cfg_symbols=$("$JQ" -r '.symbol_set // "?"' "$CONFIG")
  cfg_spacing=$("$JQ" -r '.spacing // "?"' "$CONFIG")
  cfg_style=$("$JQ" -r '.style // "?"' "$CONFIG")
  cfg_icons=$("$JQ" -r 'if .show_icons == false then "off" else "on" end' "$CONFIG")
  cfg_blocks=$("$JQ" -r '(.blocks // []) | length' "$CONFIG")
  cfg_bar=$("$JQ" -r '(.bar_filled // "") + (.bar_empty // "")' "$CONFIG")
  cfg_time=$("$JQ" -r '.time_format // "?"' "$CONFIG")
  cfg_head=$("$JQ" -r '.head // "sharp"' "$CONFIG")
  cfg_tail=$("$JQ" -r '.tail // "sharp"' "$CONFIG")
else
  cfg_theme="not configured"
fi

# ── Sample data for live demo ─────────────────────────────────────────────
_5h=$(( $(date +%s) + 2*3600 + 46*60 ))
_7d=$(( $(date +%s) + 4*86400 + 21*3600 ))
SAMPLE='{"model":{"display_name":"Opus 4.6 (1M)"},"workspace":{"current_dir":"'"$SCRIPT_DIR"'"},"context_window":{"used_percentage":58},"rate_limits":{"five_hour":{"used_percentage":76,"resets_at":'"$_5h"'},"seven_day":{"used_percentage":33,"resets_at":'"$_7d"'}}}'

# ── Helper: render with config overrides ──────────────────────────────────
# _OVERVIEW_SCRATCH: isolated scratch file so overview previews don't pollute HISTORY_FILE
_OVERVIEW_SCRATCH=$(mktemp)
trap 'rm -f "$_OVERVIEW_SCRATCH"' EXIT
render_with() {
  local overrides="$1"
  local tmp=$(mktemp)
  echo "$overrides" | "$JQ" -s '.[0] * .[1]' "$CONFIG" - > "$tmp"
  echo "$SAMPLE" | CONFIG_OVERRIDE="$tmp" HISTORY_FILE="$_OVERVIEW_SCRATCH" bash "$STATUSLINE" 2>/dev/null
  rm -f "$tmp"
}

# ── Title ─────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${C}====================================================${R}"
echo -e "  ${C}  CYBERPUNK STATUSLINE -- FEATURE OVERVIEW${R}"
echo -e "  ${C}====================================================${R}"
echo ""

# ── Live statusline ───────────────────────────────────────────────────────
echo -e "  ${Y}YOUR STATUSLINE${R}"
echo -e "  ${D}----------------------------------------------------${R}"
if [ -f "$CONFIG" ]; then
  printf "  "
  echo "$SAMPLE" | HISTORY_FILE="$_OVERVIEW_SCRATCH" bash "$STATUSLINE" 2>/dev/null
  echo ""
else
  echo -e "  ${D}(not configured -- run ./install.sh)${R}"
  echo ""
fi

# ── Current config ────────────────────────────────────────────────────────
echo -e "  ${Y}CURRENT CONFIG${R}"
echo -e "  ${D}----------------------------------------------------${R}"
if [ -f "$CONFIG" ]; then
  printf "  ${B}%-14s${R} %s\n" "Theme:" "$cfg_theme"
  printf "  ${B}%-14s${R} %s\n" "Style:" "$cfg_style"
  printf "  ${B}%-14s${R} %s\n" "Symbols:" "$cfg_symbols"
  printf "  ${B}%-14s${R} %s\n" "Spacing:" "$cfg_spacing"
  printf "  ${B}%-14s${R} %s\n" "Icons:" "$cfg_icons"
  echo -e "  ${B}Bar style:${R}     $cfg_bar"
  printf "  ${B}%-14s${R} %s\n" "Time:" "$cfg_time"
  printf "  ${B}%-14s${R} %s\n" "Blocks:" "$cfg_blocks/8 enabled"
else
  echo -e "  ${D}No config found.${R}"
fi
echo ""

# ── Daily burn trend ──────────────────────────────────────────────────────
echo -e "  ${Y}DAILY BURN TREND${R}"
echo -e "  ${D}----------------------------------------------------${R}"
_daily=$(burn_rate_daily)
if [ -n "$_daily" ]; then
  printf "  ${B}%-12s %10s %10s${R}\n" "DATE" "CONSUMED" "REMAINING"
  while IFS=$'\t' read -r _d _c _rem; do
    printf "  %-12s %9s%% %9s%%\n" "$_d" "$_c" "$_rem"
  done <<< "$_daily"
  IFS='|' read -r _a _s _tf _ _ <<< "$(burn_rate_calc)"
  if [ "$_tf" = "yes" ]; then
    echo -e "  ${M}► 速率偏快：目前 ${_a}%/day，剛好用完應為 ${_s}%/day${R}"
  elif [ "$_tf" = "no" ]; then
    echo -e "  ${G}► 速率正常：目前 ${_a}%/day ≤ 可持續 ${_s}%/day${R}"
  fi
else
  echo -e "  ${D}尚無消耗紀錄（statusline 執行幾次後即會累積）${R}"
fi
echo ""

# ── Style comparison ──────────────────────────────────────────────────────
echo -e "  ${Y}STYLE COMPARISON${R}"
echo -e "  ${D}----------------------------------------------------${R}"

# Generate previews in parallel
_pd=$(mktemp -d)
( render_with '{"style":"rainbow","head":"sharp","tail":"sharp","spacing":"ultra-compact","blocks":["model","context","rate_5h","rate_7d","cost","directory","git","time"]}' > "$_pd/rainbow" ) &
( render_with '{"style":"classic","separator":"|","spacing":"ultra-compact","blocks":["model","context","rate_5h","rate_7d","cost","directory","git","time"]}' > "$_pd/classic" ) &
( render_with '{"style":"rainbow","head":"rounded","tail":"rounded","spacing":"ultra-compact","blocks":["model","context","rate_5h","rate_7d","cost","directory","git","time"]}' > "$_pd/rounded" ) &
( render_with '{"style":"rainbow","head":"sharp","tail":"sharp","spacing":"compact","blocks":["model","context","rate_5h","rate_7d","cost","directory","git","time"]}' > "$_pd/compact" ) &
( render_with '{"style":"rainbow","head":"sharp","tail":"sharp","spacing":"normal","blocks":["model","context","rate_5h","rate_7d","cost","directory","git","time"]}' > "$_pd/normal" ) &
wait

echo ""
echo -e "  ${G}Rainbow (sharp)${R}"
printf "  "; echo -e "$(cat "$_pd/rainbow")"
echo ""
echo -e "  ${G}Rainbow (rounded)${R}"
printf "  "; echo -e "$(cat "$_pd/rounded")"
echo ""
echo -e "  ${G}Classic${R}"
printf "  "; echo -e "$(cat "$_pd/classic")"
echo ""

echo -e "  ${Y}SPACING COMPARISON${R}"
echo -e "  ${D}----------------------------------------------------${R}"
echo ""
echo -e "  ${G}Normal${R}  ${D}icon + label + bar + %${R}"
printf "  "; echo -e "$(cat "$_pd/normal")"
echo ""
echo -e "  ${G}Compact${R} ${D}icon + bar + %${R}"
printf "  "; echo -e "$(cat "$_pd/compact")"
echo ""
echo -e "  ${G}Ultra${R}   ${D}icon + % only${R}"
printf "  "; echo -e "$(cat "$_pd/rainbow")"

rm -rf "$_pd"
echo ""

# ── Features ──────────────────────────────────────────────────────────────
echo -e "  ${Y}AVAILABLE BLOCKS${R}"
echo -e "  ${D}----------------------------------------------------${R}"
printf "  ${B}%-12s${R} %s\n" "model"     "Current Claude model"
printf "  ${B}%-12s${R} %s\n" "context"   "Context window usage %%"
printf "  ${B}%-12s${R} %s\n" "rate_5h"   "5-hour rate limit + reset countdown"
printf "  ${B}%-12s${R} %s\n" "rate_7d"   "7-day rate limit + reset countdown"
printf "  ${B}%-12s${R} %s\n" "cost"      "Daily cost (ccusage or built-in JSONL)"
printf "  ${B}%-12s${R} %s\n" "directory" "Current folder name"
printf "  ${B}%-12s${R} %s\n" "git"       "Git branch"
printf "  ${B}%-12s${R} %s\n" "time"      "Current time (24h/12h/no-sec)"
echo ""

echo -e "  ${Y}BAR STYLES${R}"
echo -e "  ${D}----------------------------------------------------${R}"
echo -e "  Square ${B}■□${R}  Circle ${B}●○${R}  Diamond ${B}◆◇${R}  Med.Square ${B}◼◻${R}  Rectangle ${B}▮▯${R}  Hexagon ${B}⬢⬡${R}"
echo ""

# ── Themes ────────────────────────────────────────────────────────────────
theme_count=$(ls "$THEMES_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
echo -e "  ${Y}THEMES${R} ${D}(${theme_count} built-in + custom)${R}"
echo -e "  ${D}----------------------------------------------------${R}"
echo -e "  ${M}Cyberpunk${R}  terminal-glitch  neon-classic  synthwave-sunset"
echo -e "             blade-runner  retrowave-chrome  midnight-phantom"
echo -e "  ${M}Classic${R}    dracula  tokyo-night  catppuccin-mocha  rose-pine"
echo -e "             nord  one-dark  gruvbox-dark"
echo ""

# ── Scripts ───────────────────────────────────────────────────────────────
echo -e "  ${Y}SCRIPTS${R}"
echo -e "  ${D}----------------------------------------------------${R}"
printf "  ${B}%-24s${R} %s\n" "./install.sh"          "Install + configure Claude Code"
printf "  ${B}%-24s${R} %s\n" "./configure.sh"        "Full setup wizard (p10k-style)"
printf "  ${B}%-24s${R} %s\n" "./configure-theme.sh"  "Preview + switch/edit themes"
printf "  ${B}%-24s${R} %s\n" "./overview.sh"         "This overview"
printf "  ${B}%-24s${R} %s\n" "./uninstall.sh"        "Remove from Claude Code"
echo ""

# ── Quick actions ─────────────────────────────────────────────────────────
echo -e "  ${Y}QUICK ACTIONS${R}"
echo -e "  ${D}----------------------------------------------------${R}"
echo -e "  Switch theme:      ${C}./configure-theme.sh${R}"
echo -e "  Full reconfigure:  ${C}./configure.sh${R}"
echo -e "  Edit theme colors: ${C}./configure-theme.sh tokyo-night${R}"
echo -e "  Update:            ${C}git pull${R}"
echo ""

rm -f "$_OVERVIEW_SCRATCH"
