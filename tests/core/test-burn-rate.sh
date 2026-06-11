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

rm -f "$TMP"
echo "---"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
