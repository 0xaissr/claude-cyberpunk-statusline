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
    idle)    echo none     ;;
    error)   echo alert    ;;
  esac
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

    # Tab title → project basename (works regardless of tab width)
    stdin_input=$(_read_stdin)
    cwd=$(_resolve_cwd "$stdin_input")
    title=$(basename "$cwd")
    printf '\e]1;%s\a' "$title" > "$TAB_STATE_OUT"

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
