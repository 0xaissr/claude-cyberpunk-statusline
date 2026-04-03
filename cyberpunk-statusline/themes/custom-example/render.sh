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
