#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
JQ=$(command -v jq)

source "$PROJECT_DIR/core/burn-rate.sh"

PASS=0; FAIL=0
check() { if [ "$2" = "$3" ]; then echo "✓ $1"; ((PASS++)); else echo "✗ $1 — expected [$2] got [$3]"; ((FAIL++)); fi; }

mkrow() { # ts util reset_epoch
  "$JQ" -cn --argjson t "$1" --argjson u "$2" --argjson r "$3" \
    '{ts:$t,account_type:"subscription",metric:"seven_day",utilization:$u,resets_at:$r}'
}

TMP=$(mktemp); export HISTORY_FILE="$TMP"
NOW=$(date +%s)
DAY=86400

# 7天視窗，視窗起點=NOW-3d，resets_at=NOW+4d。3天用60% → actual=20/day。剩40%/剩4天 → sustainable=10/day → too_fast=yes
RESET=$(( NOW + 4*DAY ))
PREV_RESET=$(( RESET - 7*DAY ))
{
  mkrow $(( NOW - 7*DAY )) 90 "$PREV_RESET"
  mkrow $(( NOW - 3*DAY )) 0  "$RESET"
  mkrow $(( NOW - 1*DAY )) 40 "$RESET"
  mkrow "$NOW"             60 "$RESET"
} > "$TMP"

OUT=$(burn_rate_calc "$NOW")
IFS='|' read -r actual sustainable too_fast current remaining <<< "$OUT"
check "actual ~20"      "20" "$actual"
check "sustainable ~10" "10" "$sustainable"
check "too_fast"        "yes"   "$too_fast"
check "current"         "60"    "$current"
check "remaining"       "40"    "$remaining"

# 慢速：3天用9% → actual=3；剩91%/4天 → sustainable≈22.75 → too_fast=no
{
  mkrow $(( NOW - 7*DAY )) 90 "$PREV_RESET"
  mkrow $(( NOW - 3*DAY )) 0  "$RESET"
  mkrow "$NOW"             9  "$RESET"
} > "$TMP"
OUT=$(burn_rate_calc "$NOW"); IFS='|' read -r a s tf c r <<< "$OUT"
check "slow not too_fast" "no" "$tf"

# 空 history → 全空、too_fast=na
: > "$TMP"
OUT=$(burn_rate_calc "$NOW"); IFS='|' read -r a s tf c r <<< "$OUT"
check "empty actual blank" "" "$a"
check "empty too_fast na"  "na" "$tf"

# 剩餘天數 ≤ 0 → sustainable 空、too_fast=na
EXP=$(( NOW - 3600 ))
{ mkrow $(( NOW - 3*DAY )) 0 "$EXP"; mkrow "$NOW" 50 "$EXP"; } > "$TMP"
OUT=$(burn_rate_calc "$NOW"); IFS='|' read -r a s tf c r <<< "$OUT"
check "expired sustainable blank" "" "$s"
check "expired too_fast na"       "na" "$tf"

# burn_rate_daily：兩天資料，第一天 0→30（消耗30，剩70），第二天 30→50（消耗20，剩50）
D1=$(date -u -r "$(( NOW - 1*DAY ))" +%Y-%m-%d 2>/dev/null || date -u -d "@$(( NOW - 1*DAY ))" +%Y-%m-%d)
D0=$(date -u -r "$(( NOW - 2*DAY ))" +%Y-%m-%d 2>/dev/null || date -u -d "@$(( NOW - 2*DAY ))" +%Y-%m-%d)
{
  mkrow $(( NOW - 2*DAY ))        0  "$RESET"
  mkrow $(( NOW - 2*DAY + 3600 )) 30 "$RESET"
  mkrow $(( NOW - 1*DAY ))        30 "$RESET"
  mkrow $(( NOW - 1*DAY + 3600 )) 50 "$RESET"
} > "$TMP"
DAILY=$(burn_rate_daily)
check "daily day0 consumed" "30" "$(echo "$DAILY" | awk -v d="$D0" '$1==d{print $2}')"
check "daily day1 consumed" "20" "$(echo "$DAILY" | awk -v d="$D1" '$1==d{print $2}')"
check "daily day1 remaining" "50" "$(echo "$DAILY" | awk -v d="$D1" '$1==d{print $3}')"

# 同一天內 utilization 下降（視窗重置）→ consumed 夾到 0
DR=$(date -u -r "$NOW" +%Y-%m-%d 2>/dev/null || date -u -d "@$NOW" +%Y-%m-%d)
{
  mkrow "$NOW"            90 "$RESET"
  mkrow $(( NOW + 3600 )) 5  "$RESET"
} > "$TMP"
DAILY=$(burn_rate_daily)
check "daily clamp negative→0" "0" "$(echo "$DAILY" | awk -v d="$DR" '$1==d{print $2}')"

# ── Regression：resets_at 每筆漂移時，視窗起點不可用 resets_at 推算 ──
# util 10→20→30 over 2d，resets_at 每筆 +100s 漂移，reset 遠在未來。
# 視窗無 util 下降 → 起點為首筆 → actual=(30-10)/2d=10/day，必須非空（舊碼會算出未來起點→空）。
DRIFT=$(( NOW + 5*DAY ))
{
  mkrow $(( NOW - 2*DAY )) 10 "$DRIFT"
  mkrow $(( NOW - 1*DAY )) 20 "$(( DRIFT + 100 ))"
  mkrow "$NOW"             30 "$(( DRIFT + 200 ))"
} > "$TMP"
OUT=$(burn_rate_calc "$NOW"); IFS='|' read -r a s tf c r <<< "$OUT"
check "drift actual not blank" "10" "$a"
check "drift too_fast no"      "no" "$tf"

# ── metric 過濾：混入其他 metric 的雜訊列不應汙染當前 metric 計算 ──
# 當前（最後一筆）為 seven_day；插入 credit/spend 雜訊 → 只用 seven_day：(30-10)/2d=10
{
  mkrow $(( NOW - 2*DAY )) 10 "$DRIFT"
  "$JQ" -cn --argjson t $(( NOW - 2*DAY )) '{ts:$t,account_type:"quota",metric:"credit",utilization:99,resets_at:1}'
  "$JQ" -cn --argjson t $(( NOW - 1*DAY )) '{ts:$t,account_type:"quota",metric:"spend",utilization:1,resets_at:2}'
  mkrow "$NOW"             30 "$DRIFT"
} > "$TMP"
OUT=$(burn_rate_calc "$NOW"); IFS='|' read -r a s tf c r <<< "$OUT"
check "metric-filter actual" "10" "$a"

# ── reset（util 下降）偵測：視窗起點在最後一次下降之後 ──
# util 10,80,5,25：最後下降 80→5，視窗從 5（NOW-2d）起 → actual=(25-5)/2d=10
{
  mkrow $(( NOW - 4*DAY )) 10 "$RESET"
  mkrow $(( NOW - 3*DAY )) 80 "$RESET"
  mkrow $(( NOW - 2*DAY )) 5  "$RESET"
  mkrow "$NOW"             25 "$RESET"
} > "$TMP"
OUT=$(burn_rate_calc "$NOW"); IFS='|' read -r a s tf c r <<< "$OUT"
check "reset-detect actual" "10" "$a"

# ── 單點離群值（V 形：掉下去又彈回）不可當作 reset ──
# util 10,20,8,21,22：中間的 8 是雜訊（下一筆 21 ≥ 跌前 20），應忽略 → 視窗從首筆 10
# actual=(22-10)/4d=3（若誤判為 reset 會變成 (22-8)/2d=7）
{
  mkrow $(( NOW - 4*DAY )) 10 "$RESET"
  mkrow $(( NOW - 3*DAY )) 20 "$RESET"
  mkrow $(( NOW - 2*DAY )) 8  "$RESET"
  mkrow $(( NOW - 1*DAY )) 21 "$RESET"
  mkrow "$NOW"             22 "$RESET"
} > "$TMP"
OUT=$(burn_rate_calc "$NOW"); IFS='|' read -r a s tf c r <<< "$OUT"
check "outlier dip ignored" "3" "$a"

rm -f "$TMP"
echo "---"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
