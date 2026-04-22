#!/usr/bin/env bash
# Shared helpers for managing iTerm2 tab-state hooks in ~/.claude/settings.json.
# Meant to be sourced by configure.sh and uninstall.sh.

_tab_state_settings_path() {
  echo "${CLAUDE_SETTINGS_OVERRIDE:-$HOME/.claude/settings.json}"
}

_tab_state_scripts_dir() {
  echo "${CLAUDE_SCRIPTS_DIR_OVERRIDE:-$HOME/.claude/scripts}"
}

_install_tab_state_hooks() {
  local repo_dir="$1"
  local settings; settings=$(_tab_state_settings_path)
  local scripts_dir; scripts_dir=$(_tab_state_scripts_dir)
  local jq_bin; jq_bin=$(command -v jq) || return 1

  mkdir -p "$scripts_dir" || return 1
  ln -sfn "$repo_dir/tab-state.sh" "$scripts_dir/tab-state.sh" || return 1

  if [ -f "$settings" ]; then
    cp "$settings" "$settings.bak.$(date +%Y%m%d-%H%M%S)" || return 1
  else
    mkdir -p "$(dirname "$settings")"
    echo '{}' > "$settings"
  fi

  local hook_cmd_prefix="$scripts_dir/tab-state.sh"
  local new_hooks; new_hooks=$(cat <<JSON
{
  "hooks": {
    "SessionStart":     [{"hooks": [{"type": "command", "command": "$hook_cmd_prefix idle"}]}],
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "$hook_cmd_prefix running"}]}],
    "PreToolUse":       [{"matcher": "*", "hooks": [{"type": "command", "command": "$hook_cmd_prefix running"}]}],
    "Notification":     [{"hooks": [{"type": "command", "command": "$hook_cmd_prefix waiting"}]}],
    "Stop":             [{"hooks": [{"type": "command", "command": "$hook_cmd_prefix idle"}]}],
    "SessionEnd":       [{"hooks": [{"type": "command", "command": "$hook_cmd_prefix clear"}]}]
  }
}
JSON
)

  local tmp; tmp=$(mktemp)
  "$jq_bin" -s '
    .[0] as $orig | .[1] as $new |
    $orig | .hooks = (
      ($orig.hooks // {}) as $old_hooks |
      reduce ($new.hooks | keys[]) as $event (
        $old_hooks;
        .[$event] = ((.[$event] // []) + $new.hooks[$event])
      )
    )
  ' "$settings" <(echo "$new_hooks") > "$tmp" || { rm -f "$tmp"; return 1; }

  "$jq_bin" empty "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$settings"
}

_remove_tab_state_hooks() {
  local settings; settings=$(_tab_state_settings_path)
  local scripts_dir; scripts_dir=$(_tab_state_scripts_dir)
  local jq_bin; jq_bin=$(command -v jq) || return 1

  if [ -f "$settings" ]; then
    cp "$settings" "$settings.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    local tmp; tmp=$(mktemp)
    "$jq_bin" '
      if (.hooks // null) == null then .
      else
        .hooks = (
          .hooks | to_entries | map(
            .value = (
              .value | map(
                .hooks = (.hooks | map(select((.command // "") | contains("tab-state.sh") | not)))
              ) | map(select((.hooks | length) > 0))
            )
          ) | map(select((.value | length) > 0)) | from_entries
        )
      end
    ' "$settings" > "$tmp" || { rm -f "$tmp"; return 1; }

    "$jq_bin" empty "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$settings"
  fi

  rm -f "$scripts_dir/tab-state.sh"
  rmdir "$scripts_dir" 2>/dev/null || true
  return 0
}
