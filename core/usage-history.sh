#!/usr/bin/env bash
# 使用率時間序列記錄器：依數值變化去重 append，30 天保留期。
# 被 statusline.sh source；測試可用 HISTORY_FILE env 覆寫路徑。
# 注意：本檔案刻意不設 set -uo pipefail，因為它被 source 進呼叫方的 shell。

_HIST_JQ="$(command -v jq 2>/dev/null || echo /opt/homebrew/bin/jq)"
HISTORY_RETENTION_DAYS="${HISTORY_RETENTION_DAYS:-30}"

_history_file() {
  echo "${HISTORY_FILE:-$HOME/.cache/cyberpunk-statusline/usage-history.jsonl}"
}

# history_append <account_type> <metric> <utilization> <resets_at> [ts]
history_append() {
  local acct="$1" metric="$2" util="$3" reset="$4" ts="${5:-$(date +%s)}"
  [ -z "$util" ] && return 0
  [ -z "$reset" ] && return 0
  [[ "$util" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || return 0
  [[ "$reset" =~ ^-?[0-9]+$ ]] || return 0

  local file; file="$(_history_file)"
  mkdir -p "$(dirname "$file")" 2>/dev/null || true

  # 去重：與最後一筆比對 util 與 resets_at；兩者皆相同才跳過。
  if [ -f "$file" ]; then
    local last; last="$(tail -n1 "$file" 2>/dev/null)"
    if [ -n "$last" ]; then
      local same
      same=$(echo "$last" | "$_HIST_JQ" -r \
        --argjson u "$util" --argjson r "$reset" \
        'if (.utilization == $u and .resets_at == $r) then "yes" else "no" end' 2>/dev/null)
      [ "$same" = "yes" ] && return 0
    fi
  fi

  local row
  row=$("$_HIST_JQ" -cn \
    --arg a "$acct" --arg m "$metric" \
    --argjson u "$util" --argjson r "$reset" --argjson t "$ts" \
    '{ts:$t, account_type:$a, metric:$m, utilization:$u, resets_at:$r}')

  # append + 裁切超過保留期的舊列（一次重寫，檔案很小）
  local cutoff=$(( ts - HISTORY_RETENTION_DAYS * 86400 ))
  local tmp="$file.tmp.$$"
  { [ -f "$file" ] && cat "$file"; echo "$row"; } \
    | "$_HIST_JQ" -c --argjson cut "$cutoff" 'select(.ts > $cut)' \
    > "$tmp" 2>/dev/null && mv -f "$tmp" "$file" || { rm -f "$tmp"; return 1; }
}
