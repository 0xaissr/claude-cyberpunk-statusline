#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" != "--line" ]; then
  echo "usage: statusline.sh --line" >&2
  exit 2
fi

CONFIG_TOML="${CODEX_CONFIG_TOML:-$HOME/.codex/config.toml}"
SESSIONS_DIR="${CODEX_SESSIONS_DIR:-$HOME/.codex/sessions}"

read_config_value() {
  local key="$1" default="$2"
  if [ ! -f "$CONFIG_TOML" ]; then
    printf '%s' "$default"
    return
  fi

  awk -F= -v key="$key" '
    $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      value = $2
      sub(/[[:space:]]*#.*/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      found = 1
      exit
    }
    END { if (!found) exit 1 }
  ' "$CONFIG_TOML" 2>/dev/null || printf '%s' "$default"
}

latest_session_file() {
  [ -d "$SESSIONS_DIR" ] || return 1
  find "$SESSIONS_DIR" -type f -name '*.jsonl' -print 2>/dev/null | sort | tail -1
}

read_latest_usage_field() {
  local field="$1" file="$2"
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    printf -- '--'
    return
  fi

  jq -r --arg field "$field" '
    select(type == "object" and has($field)) | .[$field]
  ' "$file" 2>/dev/null | tail -1 | awk 'NF { print; found=1 } END { if (!found) print "--" }'
}

format_percent() {
  local value="$1"
  if [ "$value" = "--" ] || [ -z "$value" ]; then
    printf -- '--'
  else
    printf '%s%%' "$value"
  fi
}

git_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null || printf -- '--'
}

model="$(read_config_value model "codex")"
effort="$(read_config_value model_reasoning_effort "")"
session_file="$(latest_session_file || true)"
ctx="$(read_latest_usage_field context_used_percent "$session_file")"
five="$(read_latest_usage_field five_hour_percent "$session_file")"
weekly="$(read_latest_usage_field weekly_percent "$session_file")"
branch="$(git_branch)"
project="$(basename "$(pwd)")"

model_part="$model"
if [ -n "$effort" ]; then
  model_part="$model_part $effort"
fi

printf '%s|%s|git(%s)|Ctx:%s|5h:%s|7d:%s\n' \
  "$model_part" \
  "$project" \
  "$branch" \
  "$(format_percent "$ctx")" \
  "$(format_percent "$five")" \
  "$(format_percent "$weekly")"
