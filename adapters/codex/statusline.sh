#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" != "--line" ]; then
  echo "usage: statusline.sh --line" >&2
  exit 2
fi

CONFIG_TOML="${CODEX_CONFIG_TOML:-$HOME/.codex/config.toml}"
SESSIONS_DIR="${CODEX_SESSIONS_DIR:-$HOME/.codex/sessions}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ -n "${CYBERPUNK_STATUSLINE_ROOT:-}" ]; then
  STATUSLINE_ROOT="$CYBERPUNK_STATUSLINE_ROOT"
elif [ -f "$WORKTREE_ROOT/config.json" ]; then
  STATUSLINE_ROOT="$WORKTREE_ROOT"
elif [ "$(basename "$(dirname "$WORKTREE_ROOT")")" = ".worktrees" ] \
  && [ -f "$(dirname "$(dirname "$WORKTREE_ROOT")")/config.json" ]; then
  STATUSLINE_ROOT="$(dirname "$(dirname "$WORKTREE_ROOT")")"
else
  STATUSLINE_ROOT="$WORKTREE_ROOT"
fi

MAIN_RENDERER="$STATUSLINE_ROOT/statusline.sh"
STATUSLINE_CONFIG="${CODEX_STATUSLINE_CONFIG:-$STATUSLINE_ROOT/config.json}"

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
    return
  fi

  jq -r --arg field "$field" '
    select(type == "object" and has($field)) | .[$field]
  ' "$file" 2>/dev/null | tail -1 | awk 'NF { print; found=1 }'
}

capitalise() {
  local value="$1"
  [ -n "$value" ] || return
  printf '%s%s' "$(printf '%s' "${value:0:1}" | tr '[:lower:]' '[:upper:]')" "${value:1}"
}

fallback_config() {
  cat <<'JSON'
{
  "theme": "terminal-glitch",
  "symbol_set": "nerd",
  "spacing": "ultra-compact",
  "style": "rainbow",
  "separator": "",
  "head": "rounded",
  "tail": "sharp",
  "blocks": ["model", "context", "rate_5h", "rate_7d", "git", "time"],
  "bar_width": 6,
  "bar_filled": "●",
  "bar_empty": "○",
  "show_icons": true,
  "time_format": "24h",
  "account_type": "subscription"
}
JSON
}

render_with_claude_style() {
  local input_json="$1"
  local tmp_home tmp_config tmp_usage tmp_output
  tmp_home=$(mktemp -d)
  tmp_config=$(mktemp)
  tmp_usage=$(mktemp)
  tmp_output=$(mktemp)

  mkdir -p "$tmp_home/.cache/cyberpunk-statusline"
  printf -- '--' > "$tmp_home/.cache/cyberpunk-statusline/daily-cost"
  printf '{"account_type":"subscription"}' > "$tmp_usage"

  if [ -f "$STATUSLINE_CONFIG" ]; then
    cp "$STATUSLINE_CONFIG" "$tmp_config"
  else
    fallback_config > "$tmp_config"
  fi

  if [ ! -x "$MAIN_RENDERER" ]; then
    printf '%s\n' "$model_part"
    rm -rf "$tmp_home" "$tmp_config" "$tmp_usage" "$tmp_output"
    return
  fi

  HOME="$tmp_home" \
    CONFIG_OVERRIDE="$tmp_config" \
    USAGE_CACHE_OVERRIDE="$tmp_usage" \
    bash "$MAIN_RENDERER" <<< "$input_json" > "$tmp_output" 2>/dev/null || true

  awk 'NF { print; exit }' "$tmp_output"
  rm -rf "$tmp_home" "$tmp_config" "$tmp_usage" "$tmp_output"
}

model="$(read_config_value model "codex")"
effort="$(read_config_value model_reasoning_effort "")"
session_file="$(latest_session_file || true)"
ctx="$(read_latest_usage_field context_used_percent "$session_file")"
five="$(read_latest_usage_field five_hour_percent "$session_file")"
weekly="$(read_latest_usage_field weekly_percent "$session_file")"

model_part="$model"
if [ -n "$effort" ]; then
  model_part="$model_part ($(capitalise "$effort"))"
fi

input_json=$(jq -n \
  --arg model "$model_part" \
  --arg cwd "$PWD" \
  --arg ctx "$ctx" \
  --arg five "$five" \
  --arg weekly "$weekly" '
  def pct($value):
    if ($value | test("^[0-9]+(\\.[0-9]+)?$")) then
      ($value | tonumber)
    else
      null
    end;

  {
    model: { display_name: $model },
    workspace: { current_dir: $cwd },
    cwd: $cwd,
    context_window: { used_percentage: pct($ctx) },
    rate_limits: {
      five_hour: { used_percentage: pct($five) },
      seven_day: { used_percentage: pct($weekly) }
    }
  }
')

render_with_claude_style "$input_json"
