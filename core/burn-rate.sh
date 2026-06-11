#!/usr/bin/env bash
# 從使用率時間序列計算單日消耗速率。被 statusline.sh / overview.sh source。
# 讀 HISTORY_FILE（與 usage-history.sh 同一份）。本檔被 source，故不設 set -uo pipefail。

_BR_JQ="$(command -v jq 2>/dev/null || echo /opt/homebrew/bin/jq)"

_br_file() { echo "${HISTORY_FILE:-$HOME/.cache/cyberpunk-statusline/usage-history.jsonl}"; }

# burn_rate_calc [now_epoch]
# 印出 "actual|sustainable|too_fast|current|remaining"
burn_rate_calc() {
  local file; file="$(_br_file)"
  local now="${1:-$(date +%s)}"
  if [ ! -s "$file" ]; then printf '||na||\n'; return 0; fi

  "$_BR_JQ" -rs --argjson now "$now" '
    if (length == 0) then "||na||"
    else
      (.[-1]) as $last
      | $last.resets_at as $reset
      | $last.utilization as $current
      | (100 - $current) as $remaining
      | [ .[] | select(.resets_at == $reset) ] as $win
      | ([ .[] | .resets_at ] | unique | sort) as $resets
      | (if ($resets | length) >= 2
           then $reset - $resets[-2]
           else null end) as $winlen
      | (if $winlen != null then ($reset - $winlen) else $win[0].ts end) as $start
      | (($now - $start) / 86400) as $elapsed_d
      | (($reset - $now) / 86400) as $left_d
      | (if $elapsed_d > 0 then ($current / $elapsed_d) else null end) as $actual
      | (if $left_d > 0 then ($remaining / $left_d) else null end) as $sustainable
      | (if ($actual != null and $sustainable != null)
           then (if $actual > $sustainable then "yes" else "no" end)
           else "na" end) as $too_fast
      | ((if $actual != null then ($actual*100|round/100|tostring) else "" end)
         + "|" + (if $sustainable != null then ($sustainable*100|round/100|tostring) else "" end)
         + "|" + $too_fast
         + "|" + ($current|tostring)
         + "|" + ($remaining|tostring))
    end
  ' "$file" 2>/dev/null || printf '||na||\n'
}
