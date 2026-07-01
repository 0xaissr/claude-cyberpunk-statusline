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
CACHE_TTL_SECONDS="${CODEX_STATUSLINE_CACHE_TTL_SECONDS:-5}"

cache_key() {
  local material="$PWD|$HOME|$CONFIG_TOML|$STATUSLINE_CONFIG"
  if command -v md5 >/dev/null 2>&1; then
    printf '%s' "$material" | md5
  else
    printf '%s' "$material" | shasum | awk '{ print $1 }'
  fi
}

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cyberpunk-statusline/codex-adapter"
CACHE_FILE="$CACHE_DIR/$(cache_key).line"
CACHE_LOCK="$CACHE_FILE.lock"

refresh_cache_in_background() {
  [ -z "${CODEX_STATUSLINE_CACHE_REFRESH:-}" ] || return 0
  mkdir -p "$CACHE_DIR"
  if mkdir "$CACHE_LOCK" 2>/dev/null; then
    (
      tmp="$CACHE_FILE.tmp.$$"
      CODEX_STATUSLINE_CACHE_REFRESH=1 CODEX_STATUSLINE_DISABLE_CACHE=1 bash "$0" --line > "$tmp" 2>/dev/null \
        && [ -s "$tmp" ] \
        && mv "$tmp" "$CACHE_FILE"
      rm -f "$tmp"
      rmdir "$CACHE_LOCK" 2>/dev/null || true
    ) &
    disown "$!" 2>/dev/null || true
  fi
}

read_cache() {
  [ -z "${CODEX_STATUSLINE_DISABLE_CACHE:-}" ] || return 1
  [ -f "$CACHE_FILE" ] || return 1
  local now mtime age
  now=$(date +%s)
  mtime=$(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
  age=$((now - mtime))
  if [ "$age" -gt "$CACHE_TTL_SECONDS" ]; then
    refresh_cache_in_background
  fi
  cat "$CACHE_FILE"
}

write_cache() {
  [ -z "${CODEX_STATUSLINE_DISABLE_CACHE:-}" ] || return 0
  mkdir -p "$CACHE_DIR"
  printf '%s\n' "$1" > "$CACHE_FILE"
}

if cached_line="$(read_cache)"; then
  printf '%s\n' "$cached_line"
  exit 0
fi

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
    def context_pct:
      (.payload.info.last_token_usage.total_tokens // empty) as $tokens
      | (.payload.info.model_context_window // empty) as $window
      | if (($tokens | type) == "number" and ($window | type) == "number" and $window > 0) then
          12000 as $baseline
          | if $window <= $baseline then
              100
            else
              (((($tokens - $baseline) | if . > 0 then . else 0 end) * 100 / ($window - $baseline)) + 0.5 | floor)
            end
        else
          empty
        end;

    select(type == "object")
    | if has($field) then
        .[$field]
      elif $field == "context_used_percent" then
        context_pct
      elif $field == "five_hour_percent" then
        .payload.rate_limits.primary.used_percent // empty
      elif $field == "five_hour_reset" then
        .payload.rate_limits.primary.resets_at // empty
      elif $field == "weekly_percent" then
        .payload.rate_limits.secondary.used_percent // empty
      elif $field == "weekly_reset" then
        .payload.rate_limits.secondary.resets_at // empty
      else
        empty
      end
  ' "$file" 2>/dev/null | tail -1 | awk 'NF { print; found=1 }'
}

codex_estimated_cost() {
  local file="$1"
  [ -n "$file" ] && [ -f "$file" ] || return 0

  jq -r '
    select(type == "object" and .type == "event_msg" and .payload.type == "token_count")
    | .payload.info.total_token_usage
    | [
        (.input_tokens // 0),
        (.cached_input_tokens // 0),
        (.output_tokens // 0)
      ]
    | @tsv
  ' "$file" 2>/dev/null | tail -1 | awk '
    NF == 3 {
      input = $1
      cached = $2
      output = $3
      non_cached = input - cached
      if (non_cached < 0) non_cached = 0
      cost = (non_cached * 5 + cached * 0.5 + output * 30) / 1000000
      printf "%.2f", cost
    }
  '
  return 0
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
  "blocks": ["model", "context", "rate_5h", "rate_7d", "cost", "burn", "git", "time"],
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
  if [ -n "$codex_cost" ]; then
    printf '%s' "$codex_cost" > "$tmp_home/.cache/cyberpunk-statusline/daily-cost"
  fi
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
    HISTORY_FILE="$CACHE_DIR/usage-history.jsonl" \
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
five_reset="$(read_latest_usage_field five_hour_reset "$session_file")"
weekly="$(read_latest_usage_field weekly_percent "$session_file")"
weekly_reset="$(read_latest_usage_field weekly_reset "$session_file")"
codex_cost="$(codex_estimated_cost "$session_file")"

model_part="$model"
if [ -n "$effort" ]; then
  model_part="$model_part ($(capitalise "$effort"))"
fi

input_json=$(jq -n \
  --arg model "$model_part" \
  --arg cwd "$PWD" \
  --arg ctx "$ctx" \
  --arg five "$five" \
  --arg five_reset "$five_reset" \
  --arg weekly "$weekly" \
  --arg weekly_reset "$weekly_reset" '
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
      five_hour: {
        used_percentage: pct($five),
        resets_at: pct($five_reset)
      },
      seven_day: {
        used_percentage: pct($weekly),
        resets_at: pct($weekly_reset)
      }
    }
  }
')

rendered_line="$(render_with_claude_style "$input_json")"
if [ -n "$rendered_line" ]; then
  write_cache "$rendered_line"
  printf '%s\n' "$rendered_line"
fi
