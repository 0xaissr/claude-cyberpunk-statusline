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

  # 設計：API 每次 render 回傳的 resets_at 會隨「現在時間」漂移（每筆差幾秒～幾天），
  # 不是穩定的視窗識別碼，故不可用 resets_at 推算視窗起點。改採：
  #   1. 依「當前指標」（最後一筆的 metric）過濾，避免混合 credit/spend/seven_day。
  #   2. 視窗起點 = 最後一次 utilization 下降（reset）之後的那一筆；無下降則為首筆。
  #   3. days_left 直接用最新 resets_at（漂移幾秒對天級尺度無感）。
  "$_BR_JQ" -rs --argjson now "$now" '
    if (length == 0) then "||na||"
    else
      (.[-1].metric) as $m
      | [ .[] | select(.metric == $m) ] as $s
      | ($s[-1]) as $last
      | $last.resets_at as $reset
      | $last.utilization as $current
      | (100 - $current) as $remaining
      | ($s|length) as $n
      | (reduce range(1; $n) as $i (0;
           # 視 i 為 reset 起點：須是下降，且非「單點離群」——
           # utilization 是累積量、視窗內只增不減，若下一筆又彈回到跌前水準（≥ 前一筆），
           # 則這個下降是雜訊（V 形），不算 reset；無下一筆或下一筆仍低於跌前才算真重置。
           if ($s[$i].utilization < $s[$i-1].utilization)
              and (($i+1 >= $n) or ($s[$i+1].utilization < $s[$i-1].utilization))
           then $i else . end)) as $si
      | $s[$si] as $startrow
      | (($now - $startrow.ts) / 86400) as $elapsed_d
      | (($reset - $now) / 86400) as $left_d
      | (if $elapsed_d > 0 then (($current - $startrow.utilization) / $elapsed_d) else null end) as $actual
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

# burn_rate_daily：印出 "YYYY-MM-DD\tconsumed\tremaining"，依日期升冪
burn_rate_daily() {
  local file; file="$(_br_file)"
  [ ! -s "$file" ] && return 0
  "$_BR_JQ" -rs '
    if length == 0 then empty
    else
    (.[-1].metric) as $m
    | map(select(.metric == $m))
    | map(. + {day: (.ts | strftime("%Y-%m-%d"))})
    | group_by(.day)
    | map(
        (sort_by(.ts)) as $g
        | { day: $g[0].day,
            consumed: ((($g[-1].utilization - $g[0].utilization) | if . < 0 then 0 else . end) * 10 | round / 10),
            remaining: ((100 - $g[-1].utilization) * 10 | round / 10) }
      )
    | sort_by(.day)[]
    | "\(.day)\t\(.consumed)\t\(.remaining)"
    end
  ' "$file" 2>/dev/null
}
