#!/usr/bin/env bash
# ╔══════════════════════════════════════════╗
# ║  cyberpunk-statusline feature overview  ║
# ╚══════════════════════════════════════════╝

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
STATUSLINE="$SCRIPT_DIR/statusline.sh"
THEMES_DIR="$SCRIPT_DIR/themes"
JQ=$(command -v jq 2>/dev/null || echo "/opt/homebrew/bin/jq")

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
else
  cfg_theme="not configured"
fi

# ── Sample data for live demo ─────────────────────────────────────────────
_5h=$(( $(date +%s) + 2*3600 + 46*60 ))
_7d=$(( $(date +%s) + 4*86400 + 21*3600 ))
SAMPLE='{"model":{"display_name":"Opus 4.6 (1M)"},"workspace":{"current_dir":"'"$SCRIPT_DIR"'"},"context_window":{"used_percentage":58},"rate_limits":{"five_hour":{"used_percentage":76,"resets_at":'"$_5h"'},"seven_day":{"used_percentage":33,"resets_at":'"$_7d"'}}}'

echo ""
echo -e "  ${C}╔══════════════════════════════════════════════════╗${R}"
echo -e "  ${C}║     CYBERPUNK STATUSLINE — FEATURE OVERVIEW     ║${R}"
echo -e "  ${C}╚══════════════════════════════════════════════════╝${R}"
echo ""

# ── Live statusline ───────────────────────────────────────────────────────
echo -e "  ${Y}YOUR STATUSLINE${R}"
echo -e "  ${D}─────────────────────────────────────────────────${R}"
if [ -f "$CONFIG" ]; then
  printf "  "
  echo "$SAMPLE" | bash "$STATUSLINE" 2>/dev/null
  echo ""
else
  echo -e "  ${D}(not configured — run ./install.sh)${R}"
  echo ""
fi

# ── Current config ────────────────────────────────────────────────────────
echo -e "  ${Y}CURRENT CONFIG${R}"
echo -e "  ${D}─────────────────────────────────────────────────${R}"
if [ -f "$CONFIG" ]; then
  echo -e "  ${B}Theme:${R}     $cfg_theme"
  echo -e "  ${B}Style:${R}     $cfg_style"
  echo -e "  ${B}Symbols:${R}   $cfg_symbols"
  echo -e "  ${B}Spacing:${R}   $cfg_spacing"
  echo -e "  ${B}Icons:${R}     $cfg_icons"
  echo -e "  ${B}Bar style:${R} $cfg_bar"
  echo -e "  ${B}Time:${R}      $cfg_time"
  echo -e "  ${B}Blocks:${R}    $cfg_blocks/8 enabled"
else
  echo -e "  ${D}No config found.${R}"
fi
echo ""

# ── Features ──────────────────────────────────────────────────────────────
echo -e "  ${Y}FEATURES${R}"
echo -e "  ${D}─────────────────────────────────────────────────${R}"
echo ""
echo -e "  ${G}Blocks${R} ${D}— customizable info segments${R}"
echo -e "    ${B}model${R}      Current Claude model"
echo -e "    ${B}context${R}    Context window usage %"
echo -e "    ${B}rate_5h${R}    5-hour rate limit + reset countdown"
echo -e "    ${B}rate_7d${R}    7-day rate limit + reset countdown"
echo -e "    ${B}cost${R}       Daily cost across all sessions (via ccusage or JSONL)"
echo -e "    ${B}directory${R}  Current folder name"
echo -e "    ${B}git${R}        Git branch"
echo -e "    ${B}time${R}       Current time (24h/12h/no-sec)"
echo ""
echo -e "  ${G}Styles${R} ${D}— two rendering modes${R}"
echo -e "    ${B}Rainbow${R}    Colored backgrounds with Powerline separators"
echo -e "    ${B}Classic${R}    Dark background with separator chars (│ / · › etc.)"
echo ""
echo -e "  ${G}Spacing${R} ${D}— three density levels${R}"
echo -e "    ${B}Normal${R}     icon + label + bar + %"
echo -e "    ${B}Compact${R}    icon + bar + %"
echo -e "    ${B}Ultra${R}      icon + % only"
echo ""
echo -e "  ${G}Bar Styles${R} ${D}— progress bar shapes${R}"
echo -e "    ■□  ●○  ◆◇  ◼◻  ▮▯  ⬢⬡"
echo ""
echo -e "  ${G}Rainbow Shapes${R} ${D}— head & tail glyphs${R}"
echo -e "    ${B}Head:${R}  flat / sharp  / slanted  / rounded "
echo -e "    ${B}Tail:${R}  flat / sharp  / slanted  / rounded "
echo ""

# ── Themes ────────────────────────────────────────────────────────────────
theme_count=$(ls "$THEMES_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
echo -e "  ${G}Themes${R} ${D}— ${theme_count} built-in + custom support${R}"
echo -e "    ${M}Cyberpunk:${R} terminal-glitch, neon-classic, synthwave-sunset,"
echo -e "               blade-runner, retrowave-chrome, midnight-phantom"
echo -e "    ${M}Classic:${R}   dracula, tokyo-night, catppuccin-mocha, rose-pine,"
echo -e "               nord, one-dark, gruvbox-dark"
echo -e "    ${M}Custom:${R}    themes/custom-example/ for reference"
echo ""

# ── Scripts ───────────────────────────────────────────────────────────────
echo -e "  ${Y}SCRIPTS${R}"
echo -e "  ${D}─────────────────────────────────────────────────${R}"
echo -e "  ${B}./install.sh${R}           Install + configure Claude Code"
echo -e "  ${B}./configure.sh${R}         Full setup wizard (p10k-style)"
echo -e "  ${B}./configure-theme.sh${R}   Preview + switch/edit themes"
echo -e "  ${B}./overview.sh${R}          This overview"
echo -e "  ${B}./uninstall.sh${R}         Remove from Claude Code"
echo ""

# ── Quick actions ─────────────────────────────────────────────────────────
echo -e "  ${Y}QUICK ACTIONS${R}"
echo -e "  ${D}─────────────────────────────────────────────────${R}"
echo -e "  ${D}Switch theme:${R}     ${C}./configure-theme.sh${R}"
echo -e "  ${D}Full reconfigure:${R} ${C}./configure.sh${R}"
echo -e "  ${D}Edit theme:${R}       ${C}./configure-theme.sh tokyo-night${R}"
echo -e "  ${D}Update:${R}           ${C}git pull${R}"
echo ""
