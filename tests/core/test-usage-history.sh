#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
JQ=$(command -v jq)

source "$PROJECT_DIR/core/usage-history.sh"

PASS=0; FAIL=0
check() { if [ "$2" = "$3" ]; then echo "✓ $1"; ((PASS++)); else echo "✗ $1 — expected [$2] got [$3]"; ((FAIL++)); fi; }

TMP=$(mktemp); rm -f "$TMP"
export HISTORY_FILE="$TMP"
NOW=$(date +%s)
RESET=$(( NOW + 4*86400 ))

# 第一筆一定寫入
history_append subscription seven_day 10 "$RESET" "$NOW"
check "first row written" "1" "$(wc -l < "$HISTORY_FILE" | tr -d ' ')"

# 數值相同 → 不寫
history_append subscription seven_day 10 "$RESET" "$(( NOW + 60 ))"
check "same value skipped" "1" "$(wc -l < "$HISTORY_FILE" | tr -d ' ')"

# 數值不同 → 寫入
history_append subscription seven_day 12 "$RESET" "$(( NOW + 120 ))"
check "changed value written" "2" "$(wc -l < "$HISTORY_FILE" | tr -d ' ')"

# resets_at 漂移但 util 與 metric 相同 → 跳過（避免每次 render 漂移都寫一筆）
history_append subscription seven_day 12 "$(( RESET + 7*86400 ))" "$(( NOW + 180 ))"
check "drift same-util skipped" "2" "$(wc -l < "$HISTORY_FILE" | tr -d ' ')"

# metric 不同即使 util 相同 → 寫入（reset 本質是 util 下降，會被當作 util 改變記錄）
history_append quota spend 12 "$RESET" "$(( NOW + 181 ))"
check "diff metric written" "3" "$(wc -l < "$HISTORY_FILE" | tr -d ' ')"

# 空 util 或空 resets_at → 不寫
history_append subscription seven_day "" "$RESET" "$(( NOW + 240 ))"
history_append subscription seven_day 14 "" "$(( NOW + 240 ))"
check "empty inputs skipped" "3" "$(wc -l < "$HISTORY_FILE" | tr -d ' ')"

# 30 天保留期：植入一筆 31 天前的舊列，新 append 後應被裁掉
OLD=$(( NOW - 31*86400 ))
"$JQ" -cn --argjson ts "$OLD" --argjson r "$RESET" '{ts:$ts,account_type:"subscription",metric:"seven_day",utilization:1,resets_at:$r}' >> "$HISTORY_FILE"
history_append subscription seven_day 20 "$(( RESET + 7*86400 ))" "$(( NOW + 300 ))"
check "old row pruned" "0" "$("$JQ" -s --argjson cut "$(( NOW - 30*86400 ))" '[.[] | select(.ts <= $cut)] | length' "$HISTORY_FILE")"

rm -f "$TMP"
echo "---"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
