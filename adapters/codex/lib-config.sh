#!/usr/bin/env bash

_codex_backup_file() {
  local file="$1"
  cp "$file" "$file.bak.$(date +%Y%m%d-%H%M%S)"
}

_codex_toml_quote() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

_codex_set_status_line_command() {
  local config_file="$1" command="$2"
  local quoted tmp
  quoted=$(_codex_toml_quote "$command")
  tmp=$(mktemp)

  [ -f "$config_file" ] || printf '' > "$config_file"
  _codex_backup_file "$config_file"

  awk -v cmd="status_line_command = \"$quoted\"" '
    BEGIN {
      in_tui = 0
      saw_tui = 0
      wrote_cmd = 0
    }

    /^\[tui\][[:space:]]*$/ {
      in_tui = 1
      saw_tui = 1
      print
      next
    }

    /^\[/ {
      if (in_tui && !wrote_cmd) {
        print cmd
        wrote_cmd = 1
      }
      in_tui = 0
      print
      next
    }

    in_tui && /^[[:space:]]*status_line_command[[:space:]]*=/ {
      if (!wrote_cmd) {
        print cmd
        wrote_cmd = 1
      }
      next
    }

    { print }

    END {
      if (in_tui && !wrote_cmd) {
        print cmd
        wrote_cmd = 1
      }
      if (!saw_tui) {
        print ""
        print "[tui]"
        print cmd
      }
    }
  ' "$config_file" > "$tmp"

  mv "$tmp" "$config_file"
}

_codex_remove_status_line_command() {
  local config_file="$1" project_root="$2"
  local tmp
  tmp=$(mktemp)

  [ -f "$config_file" ] || return 0
  _codex_backup_file "$config_file"

  awk -v root="$project_root" '
    /^[[:space:]]*status_line_command[[:space:]]*=/ {
      if (index($0, root) > 0) {
        next
      }
    }
    { print }
  ' "$config_file" > "$tmp"

  mv "$tmp" "$config_file"
}
