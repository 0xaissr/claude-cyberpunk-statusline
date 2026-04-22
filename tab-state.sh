#!/usr/bin/env bash
# Claude Code session state → iTerm2 tab background
# Usage: tab-state.sh {running|waiting|idle|error|clear}

[[ "$TERM_PROGRAM" != "iTerm.app" ]] && exit 0

state="${1-}"
case "$state" in
  running|waiting|idle|error|clear)
    exit 0
    ;;
  *)
    echo "usage: $0 {running|waiting|idle|error|clear}" >&2
    exit 1
    ;;
esac
