#!/usr/bin/env bash
# Claude Code session state → iTerm2 tab background
# Usage: tab-state.sh {running|waiting|idle|error|clear}

[[ "$TERM_PROGRAM" != "iTerm.app" ]] && exit 0

# Resolve symlink chain back to repo root (portable: no GNU readlink -f)
SCRIPT_SRC="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SRC" ]; do
  _DIR="$(cd -P "$(dirname "$SCRIPT_SRC")" && pwd)"
  SCRIPT_SRC="$(readlink "$SCRIPT_SRC")"
  [[ "$SCRIPT_SRC" != /* ]] && SCRIPT_SRC="$_DIR/$SCRIPT_SRC"
done
REPO_DIR="${CYBERPUNK_STATUSLINE_REPO_DIR:-$(cd -P "$(dirname "$SCRIPT_SRC")" && pwd)}"
CONFIG="$REPO_DIR/config.json"
JQ=$(command -v jq 2>/dev/null || echo /opt/homebrew/bin/jq)

: "${TAB_STATE_OUT:=/dev/tty}"
[[ -w "$TAB_STATE_OUT" ]] || exit 0

state="${1-}"
case "$state" in
  running|waiting|idle|error)
    [[ -f "$CONFIG" ]] || exit 0
    enabled=$("$JQ" -r '.tab_state.enabled // false' "$CONFIG" 2>/dev/null)
    [[ "$enabled" != "true" ]] && exit 0
    ;;
  clear)
    : # handled later
    ;;
  *)
    echo "usage: $0 {running|waiting|idle|error|clear}" >&2
    exit 1
    ;;
esac
