#!/usr/bin/env bash
# Claude Code session state → iTerm2 tab background + title
# Usage: tab-state.sh {running|waiting|idle|error|clear}

[[ "$TERM_PROGRAM" != "iTerm.app" ]] && exit 0

SCRIPT_SRC="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SRC" ]; do
  _DIR="$(cd -P "$(dirname "$SCRIPT_SRC")" && pwd)"
  SCRIPT_SRC="$(readlink "$SCRIPT_SRC")"
  [[ "$SCRIPT_SRC" != /* ]] && SCRIPT_SRC="$_DIR/$SCRIPT_SRC"
done
REPO_DIR="${CYBERPUNK_STATUSLINE_REPO_DIR:-$(cd -P "$(dirname "$SCRIPT_SRC")" && pwd)}"
CONFIG="$REPO_DIR/config.json"
JQ=$(command -v jq 2>/dev/null || echo /opt/homebrew/bin/jq)

_default_palette() {
  case "$1" in
    running) echo accent_1 ;;
    waiting) echo warning  ;;
    idle)    echo accent_3 ;;
    error)   echo alert    ;;
  esac
}

# Per-state emoji prefix for the tab title. iTerm2 fades inactive tab
# backgrounds so emoji in the title gives a state signal that survives.
_state_emoji() {
  case "$1" in
    running) echo "🟢" ;;
    waiting) echo "🟡" ;;
    idle)    echo "🔵" ;;
    error)   echo "🔴" ;;
  esac
}

# Lift dim RGB colors so iTerm's inactive-tab dimming doesn't wash them out.
# If max(r,g,b) < 200 we scale all three channels proportionally until the
# brightest one hits 200, preserving hue. Bright colors pass through unchanged.
_boost_rgb() {
  awk -v r="$1" -v g="$2" -v b="$3" 'BEGIN{
    max=r; if(g>max) max=g; if(b>max) max=b;
    if (max>=200) { printf "%d %d %d", r, g, b; exit }
    if (max==0)   { printf "0 0 0"; exit }
    f = 200 / max;
    nr = int(r*f + 0.5); if (nr>255) nr=255;
    ng = int(g*f + 0.5); if (ng>255) ng=255;
    nb = int(b*f + 0.5); if (nb>255) nb=255;
    printf "%d %d %d", nr, ng, nb
  }'
}

# Read hook stdin JSON once (if present) so we can extract cwd for tab title.
# Hooks pipe JSON with fields like .cwd / .workspace.current_dir; if stdin is
# empty or not JSON we silently fall back to $PWD.
_read_stdin() {
  if [ -t 0 ]; then
    echo ""
  else
    cat 2>/dev/null || true
  fi
}

_resolve_cwd() {
  local input="$1" cwd=""
  if [ -n "$input" ]; then
    cwd=$("$JQ" -r '.cwd // .workspace.current_dir // empty' <<<"$input" 2>/dev/null)
  fi
  echo "${cwd:-$PWD}"
}

: "${TAB_STATE_OUT:=/dev/tty}"
[[ -w "$TAB_STATE_OUT" ]] || exit 0

state="${1-}"
case "$state" in
  running|waiting|idle|error)
    [[ -f "$CONFIG" ]] || exit 0
    enabled=$("$JQ" -r '.tab_state.enabled // false' "$CONFIG" 2>/dev/null)
    [[ "$enabled" != "true" ]] && exit 0

    # Tab title → "<basename> <emoji>" (emoji suffix, not prefix).
    # Narrow iTerm2 tabs truncate from the START, so emoji goes to the END
    # where it survives truncation (e.g. "…tusline 🟡").
    stdin_input=$(_read_stdin)
    cwd=$(_resolve_cwd "$stdin_input")
    title=$(basename "$cwd")
    emoji=$(_state_emoji "$state")
    printf '\e]1;%s %s\a' "$title" "$emoji" > "$TAB_STATE_OUT"

    # Resolve palette name
    palette=$("$JQ" -r --arg s "$state" '.tab_state[$s] // empty' "$CONFIG" 2>/dev/null)
    palette="${palette:-$(_default_palette "$state")}"

    # 'none' → reset tab bg to iTerm default; skip RGB lookup
    if [ "$palette" = "none" ]; then
      printf '\e]6;1;bg;*;default\a' > "$TAB_STATE_OUT"
      [[ "$state" == "waiting" ]] && printf '\e]1337;RequestAttention=yes\a' > "$TAB_STATE_OUT"
      exit 0
    fi

    theme=$("$JQ" -r '.theme // "terminal-glitch"' "$CONFIG" 2>/dev/null)
    theme_file="$REPO_DIR/themes/$theme.json"
    [[ -f "$theme_file" ]] || exit 0
    hex=$("$JQ" -r --arg k "$palette" '.colors[$k] // empty' "$theme_file" 2>/dev/null)
    [[ -z "$hex" || "${hex:0:1}" != "#" || "${#hex}" -ne 7 ]] && exit 0

    r=$((16#${hex:1:2}))
    g=$((16#${hex:3:2}))
    b=$((16#${hex:5:2}))
    read r g b <<<"$(_boost_rgb "$r" "$g" "$b")"
    printf '\e]6;1;bg;red;brightness;%d\a'   "$r" > "$TAB_STATE_OUT"
    printf '\e]6;1;bg;green;brightness;%d\a' "$g" > "$TAB_STATE_OUT"
    printf '\e]6;1;bg;blue;brightness;%d\a'  "$b" > "$TAB_STATE_OUT"
    [[ "$state" == "waiting" ]] && printf '\e]1337;RequestAttention=yes\a' > "$TAB_STATE_OUT"
    ;;
  clear)
    printf '\e]6;1;bg;*;default\a' > "$TAB_STATE_OUT"
    ;;
  *)
    echo "usage: $0 {running|waiting|idle|error|clear}" >&2
    exit 1
    ;;
esac
