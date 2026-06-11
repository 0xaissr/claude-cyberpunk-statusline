# 單日消耗速率追蹤 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 記錄每次有消耗的對話的使用率快照，累積成時間序列，計算平均每日速率與「剛好用完」的每日速率，在 statusline 即時告警、在 overview.sh 呈現每日趨勢。

**Architecture:** 兩個可獨立測試的 sourced bash 函式庫 —— `core/usage-history.sh`（依數值變化去重的記錄器）與 `core/burn-rate.sh`（速率計算器），由 statusline.sh 與 overview.sh 共用。所有指標統一抽象成 `utilization`（0~100% 累積使用率）+ `resets_at`（epoch 秒）。

**Tech Stack:** bash、jq（JSON / JSONL 處理與浮點運算）、awk（既有專案的浮點慣例）。測試沿用專案的 `check desc expected actual` 骨架。

**重要事實（已從程式碼確認）：**
- `resets_at` 在本專案各處皆為 **epoch 秒整數**（`format_countdown` 用 `resets_at - now_ts` 做整數運算；測試用 `-gt $(date +%s)` 比較）。history 也以 epoch 秒存 `ts` 與 `resets_at`。
- statusline.sh 區塊機制：`block_text_<name>`（rainbow 模式文字）、`render_block_<name>`（classic 模式含色塊）、assemble 區的兩個 `case` dispatch、`cfg_blocks` 預設清單。
- 指標依帳號類型挑選：quota 且有 credit → credit；quota 無 credit → spend；subscription → seven_day。
- 測試以 `bash <script>` 子行程搭配 env 覆寫（如 `USAGE_FIXTURE`、`CONFIG_OVERRIDE`、`USAGE_CACHE_OVERRIDE`）執行。本計畫的函式庫測試改用 `source` 後直接呼叫函式，並用 `HISTORY_FILE` env 指向暫存檔。

---

## File Structure

- **Create `core/usage-history.sh`** — 記錄器函式庫。提供 `history_append`，依 `HISTORY_FILE` env（預設 `~/.cache/cyberpunk-statusline/usage-history.jsonl`）讀寫。職責：依數值去重 append、跨重置偵測、30 天保留期裁切。
- **Create `core/burn-rate.sh`** — 計算器函式庫。提供 `burn_rate_calc`（輸出當前視窗的 actual / sustainable / too_fast / current / remaining）與 `burn_rate_daily`（每日消耗量 / 剩餘量趨勢）。讀同一個 `HISTORY_FILE`。
- **Create `tests/core/test-usage-history.sh`** — 記錄器測試。
- **Create `tests/core/test-burn-rate.sh`** — 計算器測試。
- **Modify `statusline.sh`** — source 兩個函式庫；算出指標後呼叫 `history_append`；新增 `burn` 區塊（`block_text_burn` + `render_block_burn` + 兩處 dispatch + symbol fallback）；預設 `blocks` 加入 `burn`。
- **Modify `overview.sh`** — 新增「DAILY BURN TREND」段落，呼叫 `burn_rate_daily`。
- **Modify `README.md` 與 `docs/README.zh-TW.md`** — 同步說明 burn 區塊（專案規定兩版本必須同步）。
- **Modify `LOG.md`** — 記錄本次變更（專案規定每次變更後更新 LOG）。

---

## Task 1: history 記錄器函式庫

**Files:**
- Create: `core/usage-history.sh`
- Test: `tests/core/test-usage-history.sh`

- [ ] **Step 1: 寫失敗測試**

Create `tests/core/test-usage-history.sh`:

```bash
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

# 跨重置：resets_at 改變即使 util 相同也視為新視窗 → 寫入
history_append subscription seven_day 12 "$(( RESET + 7*86400 ))" "$(( NOW + 180 ))"
check "reset change written" "3" "$(wc -l < "$HISTORY_FILE" | tr -d ' ')"

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
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `bash tests/core/test-usage-history.sh`
Expected: FAIL（`core/usage-history.sh: No such file` 或 `history_append: command not found`）

- [ ] **Step 3: 寫最小實作**

Create `core/usage-history.sh`:

```bash
#!/usr/bin/env bash
# 使用率時間序列記錄器：依數值變化去重 append，30 天保留期。
# 被 statusline.sh source；測試可用 HISTORY_FILE env 覆寫路徑。

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
    > "$tmp" 2>/dev/null && mv -f "$tmp" "$file"
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `bash tests/core/test-usage-history.sh`
Expected: PASS（`PASS=7 FAIL=0`）

- [ ] **Step 5: Commit**

```bash
git add core/usage-history.sh tests/core/test-usage-history.sh
git commit -m "feat(usage): 新增使用率時間序列記錄器（依數值變化去重、30 天保留）

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: burn-rate 計算器（actual / sustainable / too_fast）

**Files:**
- Create: `core/burn-rate.sh`
- Test: `tests/core/test-burn-rate.sh`

`burn_rate_calc` 讀 `HISTORY_FILE`，針對「當前視窗」（最新 `resets_at` 對應的那段）計算並印出一行 pipe 分隔字串：
`actual|sustainable|too_fast|current|remaining`
- `actual` = 本視窗目前已用 util ÷ 視窗已過天數（%/day，保留 2 位；無法計算時為空）
- `sustainable` = `(100 − current)` ÷ 距 `resets_at` 剩餘天數（%/day；剩餘天數 ≤ 0 時為空）
- `too_fast` = `actual > sustainable` 為 `yes`，否則 `no`；任一為空時 `na`
- `current` = 最後一筆 util
- `remaining` = `100 − current`

視窗起點：history 中的相異 `resets_at` ≥ 2 個 → `視窗長度 = 最新 − 次新`，`視窗起點 = 最新 resets_at − 視窗長度`；否則以「當前視窗第一筆 ts」近似（spec 已載明初期近似偏差會隨資料修正）。

- [ ] **Step 1: 寫失敗測試**

Create `tests/core/test-burn-rate.sh`:

```bash
#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
JQ=$(command -v jq)

source "$PROJECT_DIR/core/burn-rate.sh"

PASS=0; FAIL=0
check() { if [ "$2" = "$3" ]; then echo "✓ $1"; ((PASS++)); else echo "✗ $1 — expected [$2] got [$3]"; ((FAIL++)); fi; }

mkrow() { # ts_offset_days util reset_epoch
  "$JQ" -cn --argjson t "$1" --argjson u "$2" --argjson r "$3" \
    '{ts:$t,account_type:"subscription",metric:"seven_day",utilization:$u,resets_at:$r}'
}

TMP=$(mktemp); export HISTORY_FILE="$TMP"
NOW=$(date +%s)
DAY=86400

# 場景：7 天視窗，視窗起點 = NOW-3d，resets_at = NOW+4d。
# 視窗已過 3 天用掉 60% → actual = 20%/day。剩餘 40% / 剩 4 天 → sustainable = 10%/day。
# actual(20) > sustainable(10) → too_fast = yes。
RESET=$(( NOW + 4*DAY ))
PREV_RESET=$(( RESET - 7*DAY ))
{
  mkrow $(( NOW - 7*DAY )) 90 "$PREV_RESET"   # 舊視窗，提供第二個相異 resets_at 供推算視窗長度
  mkrow $(( NOW - 3*DAY )) 0  "$RESET"
  mkrow $(( NOW - 1*DAY )) 40 "$RESET"
  mkrow "$NOW"             60 "$RESET"
} > "$TMP"

OUT=$(burn_rate_calc)
IFS='|' read -r actual sustainable too_fast current remaining <<< "$OUT"
check "actual ~20"      "20.00" "$actual"
check "sustainable ~10" "10.00" "$sustainable"
check "too_fast"        "yes"   "$too_fast"
check "current"         "60"    "$current"
check "remaining"       "40"    "$remaining"

# 慢速場景：3 天用 9% → actual=3；剩餘 91% / 4 天 → sustainable≈22.75 → too_fast=no
{
  mkrow $(( NOW - 7*DAY )) 90 "$PREV_RESET"
  mkrow $(( NOW - 3*DAY )) 0  "$RESET"
  mkrow "$NOW"             9  "$RESET"
} > "$TMP"
OUT=$(burn_rate_calc); IFS='|' read -r a s tf c r <<< "$OUT"
check "slow not too_fast" "no" "$tf"

# 邊界：空 history → 全空、too_fast=na
: > "$TMP"
OUT=$(burn_rate_calc); IFS='|' read -r a s tf c r <<< "$OUT"
check "empty actual blank" "" "$a"
check "empty too_fast na"  "na" "$tf"

# 邊界：剩餘天數 ≤ 0（resets_at 已過）→ sustainable 空、too_fast=na
EXP=$(( NOW - 3600 ))
{ mkrow $(( NOW - 3*DAY )) 0 "$EXP"; mkrow "$NOW" 50 "$EXP"; } > "$TMP"
OUT=$(burn_rate_calc); IFS='|' read -r a s tf c r <<< "$OUT"
check "expired sustainable blank" "" "$s"
check "expired too_fast na"       "na" "$tf"

rm -f "$TMP"
echo "---"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `bash tests/core/test-burn-rate.sh`
Expected: FAIL（`core/burn-rate.sh: No such file` 或 `burn_rate_calc: command not found`）

- [ ] **Step 3: 寫最小實作**

Create `core/burn-rate.sh`:

```bash
#!/usr/bin/env bash
# 從使用率時間序列計算單日消耗速率。被 statusline.sh / overview.sh source。
# 讀 HISTORY_FILE（與 usage-history.sh 同一份）。

_BR_JQ="$(command -v jq 2>/dev/null || echo /opt/homebrew/bin/jq)"

_br_file() { echo "${HISTORY_FILE:-$HOME/.cache/cyberpunk-statusline/usage-history.jsonl}"; }

# burn_rate_calc [now_epoch]
# 印出 "actual|sustainable|too_fast|current|remaining"
burn_rate_calc() {
  local file; file="$(_br_file)"
  local now="${1:-$(date +%s)}"
  if [ ! -s "$file" ]; then printf '|||na|\n'; return 0; fi

  "$_BR_JQ" -rs --argjson now "$now" '
    if (length == 0) then "|||na|"
    else
      # 最新視窗 = 最後一筆的 resets_at
      (.[-1]) as $last
      | $last.resets_at as $reset
      | $last.utilization as $current
      | (100 - $current) as $remaining
      | [ .[] | select(.resets_at == $reset) ] as $win
      | ([ .[] | .resets_at ] | unique | sort) as $resets
      # 視窗長度：相異 resets_at ≥ 2 → 最新 − 次新；否則用視窗第一筆 ts 當起點
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
  ' "$file" 2>/dev/null || printf '|||na|\n'
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `bash tests/core/test-burn-rate.sh`
Expected: PASS（`PASS=9 FAIL=0`）。若 `actual` 出現如 `20` 而非 `20.00`，調整測試比對為數值容差或改 jq 輸出固定 2 位：用 `(... *100|round/100)` 已四捨五入到 2 位但會去尾零；此時把測試的 `"20.00"` 改成 `"20"`、`"10.00"` 改成 `"10"` 以符合 jq 數值字串輸出。

- [ ] **Step 5: Commit**

```bash
git add core/burn-rate.sh tests/core/test-burn-rate.sh
git commit -m "feat(usage): 新增 burn-rate 計算器（平均每日速率 vs 剛好用完速率）

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: 每日趨勢聚合（供 overview 使用）

**Files:**
- Modify: `core/burn-rate.sh`（新增 `burn_rate_daily`）
- Test: `tests/core/test-burn-rate.sh`（追加測項）

`burn_rate_daily` 印出每日一行 `YYYY-MM-DD<TAB>consumed<TAB>remaining`：
- `consumed` = 該日最後一筆 util − 該日第一筆 util（同日內；負值代表跨重置，歸 0）
- `remaining` = 該日最後一筆的 `100 − util`
- 依日期升冪排序

- [ ] **Step 1: 追加失敗測試**

在 `tests/core/test-burn-rate.sh` 的 `rm -f "$TMP"` 之前插入：

```bash
# burn_rate_daily：兩天資料，第一天 0→30（消耗 30，剩 70），第二天 30→50（消耗 20，剩 50）
D1=$(date -j -f %s "$(( NOW - 1*DAY ))" +%Y-%m-%d 2>/dev/null || date -d "@$(( NOW - 1*DAY ))" +%Y-%m-%d)
D0=$(date -j -f %s "$(( NOW - 2*DAY ))" +%Y-%m-%d 2>/dev/null || date -d "@$(( NOW - 2*DAY ))" +%Y-%m-%d)
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
```

並把檔尾 `PASS=9` 的預期數字心裡更新為 12（測試輸出自動計算，不需改程式）。

- [ ] **Step 2: 執行測試確認失敗**

Run: `bash tests/core/test-burn-rate.sh`
Expected: FAIL（`burn_rate_daily: command not found`）

- [ ] **Step 3: 實作 `burn_rate_daily`**

在 `core/burn-rate.sh` 末尾追加：

```bash
# burn_rate_daily：印出 "YYYY-MM-DD\tconsumed\tremaining"，依日期升冪
burn_rate_daily() {
  local file; file="$(_br_file)"
  [ ! -s "$file" ] && return 0
  "$_BR_JQ" -rs '
    map(. + {day: (.ts | strftime("%Y-%m-%d"))})
    | group_by(.day)
    | map(
        (sort_by(.ts)) as $g
        | { day: $g[0].day,
            consumed: (($g[-1].utilization - $g[0].utilization) | if . < 0 then 0 else . end),
            remaining: (100 - $g[-1].utilization) }
      )
    | sort_by(.day)[]
    | "\(.day)\t\(.consumed)\t\(.remaining)"
  ' "$file" 2>/dev/null
}
```

注意：jq 的 `strftime` 使用 UTC。若需本地時區，於 `.ts` 先做 `(. + <utc_offset_seconds>)`；本計畫採 UTC 即可（趨勢用途，跨日切點差異可接受），如需在地時區於後續迭代調整。

- [ ] **Step 4: 執行測試確認通過**

Run: `bash tests/core/test-burn-rate.sh`
Expected: PASS（`FAIL=0`）

- [ ] **Step 5: Commit**

```bash
git add core/burn-rate.sh tests/core/test-burn-rate.sh
git commit -m "feat(usage): burn-rate 計算器新增每日消耗/剩餘趨勢聚合

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: 在 statusline.sh 接上記錄器

**Files:**
- Modify: `statusline.sh`（source 函式庫 + 算出指標後 append）

- [ ] **Step 1: 寫失敗測試**

在 `tests/test-statusline.sh` 末尾（`echo "PASS=..."` 之前）追加（若該檔的 check 變數名不同，沿用該檔既有骨架）：

```bash
# burn history：subscription 輸入跑一次 statusline 後，history 檔應有一筆 seven_day 列
HTMP=$(mktemp); rm -f "$HTMP"
SAMPLE_7D=$(( $(date +%s) + 4*86400 ))
echo '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":50},"rate_limits":{"seven_day":{"used_percentage":33,"resets_at":'"$SAMPLE_7D"'}}}' \
  | HISTORY_FILE="$HTMP" USAGE_CACHE_OVERRIDE="$FIX/usage-subscription.json" CONFIG_OVERRIDE="$CFG" bash "$STATUSLINE" >/dev/null 2>&1
check "burn: history row written" "seven_day" "$(tail -n1 "$HTMP" 2>/dev/null | jq -r '.metric // "none"')"
check "burn: history util" "33" "$(tail -n1 "$HTMP" 2>/dev/null | jq -r '.utilization')"
rm -f "$HTMP"
```

（`STATUSLINE`/`FIX`/`CFG` 變數沿用該測試檔開頭既有定義；若無 `CFG`，用 `CONFIG_OVERRIDE` 指向含 `burn` 的暫存 config，或省略該 override 用預設 config。）

- [ ] **Step 2: 執行測試確認失敗**

Run: `bash tests/test-statusline.sh`
Expected: FAIL（history 檔為空 → `none`）

- [ ] **Step 3: source 函式庫**

在 `statusline.sh` 的 helpers 區之後、`# ── Load config` 之前（約 line 20 後）加入：

```bash
# ── Burn-rate libraries ────────────────────────────────────────────────────
source "$SCRIPT_DIR/core/usage-history.sh"
source "$SCRIPT_DIR/core/burn-rate.sh"
```

- [ ] **Step 4: 算出指標後寫入 history**

在 `eff_account_type` 決定之後（約 line 302，`# ── Custom renderer check` 之前）加入：

```bash
# ── Record usage history for burn-rate tracking ───────────────────────────
# 依帳號類型挑指標：quota+credit→credit；quota→spend；否則→seven_day。
burn_metric="" burn_util="" burn_reset=""
if [ "$eff_account_type" = "quota" ]; then
  if [ -n "$credit_pct" ]; then
    burn_metric="credit"; burn_util="$credit_pct"; burn_reset="$credit_reset"
  elif [ -n "$spend_pct" ]; then
    burn_metric="spend"; burn_util="$spend_pct"; burn_reset="$spend_reset"
  fi
else
  if [ -n "$week_pct" ]; then
    burn_metric="seven_day"; burn_util="$week_pct"; burn_reset="$week_reset"
  fi
fi
if [ -n "$burn_metric" ]; then
  history_append "$eff_account_type" "$burn_metric" "$burn_util" "$burn_reset" 2>/dev/null || true
fi
```

- [ ] **Step 5: 執行測試確認通過**

Run: `bash tests/test-statusline.sh`
Expected: PASS（新增兩項通過；其餘原有測項不退步）

- [ ] **Step 6: Commit**

```bash
git add statusline.sh tests/test-statusline.sh
git commit -m "feat(statusline): 每次 render 依帳號類型記錄使用率到 history

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: statusline 新增 burn 區塊

**Files:**
- Modify: `statusline.sh`（symbol、`block_text_burn`、`render_block_burn`、兩處 dispatch、預設 blocks）

burn 區塊顯示「平均每日速率 / 剛好用完速率」（單位 %/day），太快時用 alert 色。
資料不足（`actual` 空）時顯示 ` 󱐋 --/-- `。

- [ ] **Step 1: 寫失敗測試**

在 `tests/test-statusline.sh` 追加（沿用既有變數）：

```bash
# burn block：植入一段「太快」的 history，輸出應含 BURN 數字且帶 alert 色碼
HTMP2=$(mktemp); NOW2=$(date +%s); R2=$(( NOW2 + 4*86400 )); PR2=$(( R2 - 7*86400 ))
jq -cn --argjson t $(( NOW2 - 7*86400 )) --argjson r $PR2 '{ts:$t,account_type:"subscription",metric:"seven_day",utilization:90,resets_at:$r}' > "$HTMP2"
jq -cn --argjson t $(( NOW2 - 3*86400 )) --argjson r $R2 '{ts:$t,account_type:"subscription",metric:"seven_day",utilization:0,resets_at:$r}' >> "$HTMP2"
jq -cn --argjson t $NOW2 --argjson r $R2 '{ts:$t,account_type:"subscription",metric:"seven_day",utilization:60,resets_at:$r}' >> "$HTMP2"
CFG2=$(mktemp); echo '{"blocks":["model","burn"],"style":"classic","separator":"|","account_type":"subscription"}' > "$CFG2"
OUT=$(echo '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/tmp"},"rate_limits":{"seven_day":{"used_percentage":60,"resets_at":'"$R2"'}}}' \
  | HISTORY_FILE="$HTMP2" USAGE_CACHE_OVERRIDE="$FIX/usage-subscription.json" CONFIG_OVERRIDE="$CFG2" bash "$STATUSLINE" 2>/dev/null)
check "burn block renders rate" "yes" "$(echo "$OUT" | grep -q '20' && echo yes || echo no)"
rm -f "$HTMP2" "$CFG2"
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `bash tests/test-statusline.sh`
Expected: FAIL（burn 區塊不存在，輸出不含速率）

- [ ] **Step 3: 加入 symbol fallback**

在 `statusline.sh` symbol 區（約 line 117 `S_CREDIT` 之後）加入：

```bash
S_BURN=$(sym burn)
[ "$S_BURN" = "?" ] && S_BURN="󱐋"
```

並在 `show_icons=false` 清空那行（line 121）末尾加入 `S_BURN=""`：

```bash
  S_MODEL="" S_CTX="" S_5H="" S_7D="" S_DIR="" S_GIT="" S_TIME="" S_COST="" S_SPEND="" S_CREDIT="" S_BURN=""
```

- [ ] **Step 4: 加入文字與色塊 renderer**

在 `block_text_credit`（約 line 415）之後加入：

```bash
block_text_burn() {
  IFS='|' read -r _ba _bs _btf _bc _br <<< "$(burn_rate_calc)"
  if [ -z "$_ba" ]; then echo -n " ${S_BURN} --/-- "; return; fi
  echo -n " ${S_BURN} ${_ba}/${_bs}%/d "
}
```

在 `render_block_credit`（約 line 482）之後加入：

```bash
render_block_burn() {
  local fg_hex=$(block_color rate_7d)
  local bg=$(hex_to_bg "$(block_bg rate_7d)")
  local dim_fg=$(hex_to_fg "$C_DIM")
  IFS='|' read -r _ba _bs _btf _bc _br <<< "$(burn_rate_calc)"
  if [ -z "$_ba" ]; then
    echo -n "${bg}${dim_fg} ${S_BURN} --/-- ${RESET}"; return
  fi
  local col; if [ "$_btf" = "yes" ]; then col=$(hex_to_fg "$C_ALERT"); else col=$(hex_to_fg "$fg_hex"); fi
  echo -n "${bg}${col}${BOLD} ${S_BURN} ${_ba}/${_bs}%/d ${RESET}"
}
```

- [ ] **Step 5: 兩處 dispatch 加 case**

在 rainbow assembly 的 `case "$block"`（約 line 666 `credit)` 之後）加入：

```bash
      burn)      text=$(block_text_burn) ;;
```

在 classic assembly 的 `case "$block"`（約 line 697 `credit)` 之後）加入：

```bash
      burn)      output+=$(render_block_burn) ;;
```

- [ ] **Step 6: 預設 blocks 加入 burn**

修改 `cfg_blocks` 預設（line 71），在 `time` 前插入 `burn`：

```bash
cfg_blocks=$("$JQ" -r '.blocks // ["model","context","rate_5h","rate_7d","cost","burn","directory","git","time"] | .[]' "$CONFIG")
```

- [ ] **Step 7: 執行測試確認通過**

Run: `bash tests/test-statusline.sh`
Expected: PASS（含新 burn 區塊測項；其餘不退步）

- [ ] **Step 8: 手動目視驗證**

Run:
```bash
HTMP=$(mktemp); NOW=$(date +%s); R=$(( NOW+4*86400 )); PR=$(( R-7*86400 ))
jq -cn --argjson t $(( NOW-7*86400 )) --argjson r $PR '{ts:$t,account_type:"subscription",metric:"seven_day",utilization:90,resets_at:$r}' > "$HTMP"
jq -cn --argjson t $(( NOW-3*86400 )) --argjson r $R '{ts:$t,account_type:"subscription",metric:"seven_day",utilization:0,resets_at:$r}' >> "$HTMP"
jq -cn --argjson t $NOW --argjson r $R '{ts:$t,account_type:"subscription",metric:"seven_day",utilization:60,resets_at:$r}' >> "$HTMP"
echo '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/tmp"},"rate_limits":{"seven_day":{"used_percentage":60,"resets_at":'"$R"'}}}' \
  | HISTORY_FILE="$HTMP" bash statusline.sh
rm -f "$HTMP"
```
Expected: 狀態列出現 burn 區塊，顯示如 `󱐋 20/10%/d`，且因太快呈 alert 色。

- [ ] **Step 9: Commit**

```bash
git add statusline.sh tests/test-statusline.sh
git commit -m "feat(statusline): 新增 burn 區塊顯示平均每日速率/剛好用完速率（太快變色）

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: overview.sh 每日趨勢段落

**Files:**
- Modify: `overview.sh`

- [ ] **Step 1: source 計算器並新增段落**

在 `overview.sh` 的 `JQ=...`（line 8）之後加入：

```bash
source "$SCRIPT_DIR/core/burn-rate.sh"
```

在「CURRENT CONFIG」段落（約 line 83 `echo ""` 之後）插入：

```bash
# ── Daily burn trend ──────────────────────────────────────────────────────
echo -e "  ${Y}DAILY BURN TREND${R}"
echo -e "  ${D}----------------------------------------------------${R}"
_daily=$(burn_rate_daily)
if [ -n "$_daily" ]; then
  printf "  ${B}%-12s %10s %10s${R}\n" "DATE" "CONSUMED" "REMAINING"
  while IFS=$'\t' read -r _d _c _rem; do
    printf "  %-12s %9s%% %9s%%\n" "$_d" "$_c" "$_rem"
  done <<< "$_daily"
  IFS='|' read -r _a _s _tf _cur _r <<< "$(burn_rate_calc)"
  if [ "$_tf" = "yes" ]; then
    echo -e "  ${M}► 速率偏快：目前 ${_a}%/day，剛好用完應為 ${_s}%/day${R}"
  elif [ "$_tf" = "no" ]; then
    echo -e "  ${G}► 速率正常：目前 ${_a}%/day ≤ 可持續 ${_s}%/day${R}"
  fi
else
  echo -e "  ${D}尚無消耗紀錄（statusline 執行幾次後即會累積）${R}"
fi
echo ""
```

- [ ] **Step 2: 手動驗證**

Run:
```bash
HTMP=$(mktemp); NOW=$(date +%s); R=$(( NOW+4*86400 ))
jq -cn --argjson t $(( NOW-2*86400 )) --argjson r $R '{ts:$t,account_type:"subscription",metric:"seven_day",utilization:0,resets_at:$r}' > "$HTMP"
jq -cn --argjson t $(( NOW-1*86400 )) --argjson r $R '{ts:$t,account_type:"subscription",metric:"seven_day",utilization:30,resets_at:$r}' >> "$HTMP"
jq -cn --argjson t $NOW --argjson r $R '{ts:$t,account_type:"subscription",metric:"seven_day",utilization:55,resets_at:$r}' >> "$HTMP"
HISTORY_FILE="$HTMP" bash overview.sh | sed -n '/DAILY BURN TREND/,/^$/p'
rm -f "$HTMP"
```
Expected: 列出每日 DATE / CONSUMED% / REMAINING%，並有速率正常或偏快的提示行。

- [ ] **Step 3: Commit**

```bash
git add overview.sh
git commit -m "feat(overview): 新增每日消耗趨勢段落（每日消耗/剩餘 + 速率提示）

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: 文件同步（README 中英 + LOG）

**Files:**
- Modify: `README.md`、`docs/README.zh-TW.md`、`LOG.md`

- [ ] **Step 1: README（英）新增 burn 區塊說明**

在 `README.md` 的 blocks 列表處新增一行（與既有 block 說明同格式）：

```markdown
- `burn` — daily burn rate: average %/day used vs the %/day that would exactly exhaust the quota by reset. Turns alert-colored when you are on pace to run out early. Backed by a per-render usage-history log (`~/.cache/cyberpunk-statusline/usage-history.jsonl`, deduped by value, 30-day retention).
```

- [ ] **Step 2: README（繁中）同步新增**

在 `docs/README.zh-TW.md` 對應位置新增：

```markdown
- `burn` — 單日消耗速率：平均每日用量（%/day）對比「剛好在重置前用完」的每日用量。若以目前速率會提早耗盡則轉為告警色。資料來自每次 render 的使用率歷史記錄（`~/.cache/cyberpunk-statusline/usage-history.jsonl`，依數值去重、保留 30 天）。
```

- [ ] **Step 3: LOG.md 記錄變更**

在 `LOG.md` 最上方（最新區段）新增條目，說明：新增 usage-history 記錄器與 burn-rate 計算器、statusline burn 區塊、overview 每日趨勢段落；統一模型 `utilization + resets_at`；依數值去重、30 天保留；太快判斷採線性外推是否在 `resets_at` 前耗盡。格式對齊 LOG.md 既有條目。

- [ ] **Step 4: 執行全測試套件確認無退步**

Run:
```bash
for t in tests/core/test-usage-history.sh tests/core/test-burn-rate.sh tests/test-statusline.sh tests/core/test-fetch-usage.sh; do
  echo "== $t =="; bash "$t" || echo "FAILED: $t"
done
```
Expected: 每個皆 `FAIL=0`。

- [ ] **Step 5: Commit**

```bash
git add README.md docs/README.zh-TW.md LOG.md
git commit -m "docs: 同步 README（中英）與 LOG 說明 burn 單日消耗速率區塊

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage：**
- 統一模型 `utilization + resets_at` → Task 1/2 的資料列與計算 ✓
- 依帳號類型挑指標（quota credit/spend、subscription 7D）→ Task 4 ✓
- 依數值變化去重、跨重置、30 天保留 → Task 1 ✓
- 平均每日速率 / 剛好用完速率 / 太快（線性外推）→ Task 2 ✓
- statusline 區塊（兩數字、太快變色）→ Task 5 ✓
- overview 每日消耗/剩餘趨勢 → Task 3 + Task 6 ✓
- 錯誤處理（空/單筆/剩餘天數 0/缺 resets_at、靜默降級）→ Task 1/2 守衛 + Task 4 `|| true` ✓
- 視窗起點推算與 fallback → Task 2 ✓
- 範圍外項目未實作 ✓

**Placeholder scan：** 無 TBD/TODO；每個 code step 皆含完整程式碼與指令。

**Type/介面一致性：**
- `history_append <account_type> <metric> <utilization> <resets_at> [ts]` — Task 1 定義，Task 4 呼叫一致 ✓
- `burn_rate_calc` 輸出 `actual|sustainable|too_fast|current|remaining` — Task 2 定義，Task 5/6 解析一致 ✓
- `burn_rate_daily` 輸出 `day\tconsumed\tremaining` — Task 3 定義，Task 6 解析一致 ✓
- `HISTORY_FILE` env 名稱在記錄器、計算器、測試、statusline 接線一致 ✓
- 區塊名 `burn` 在 symbol、text/render 函式、兩處 dispatch、預設 blocks 一致 ✓

**已知近似（spec 已載明）：** 視窗起點在只有單一 resets_at 時以「視窗第一筆 ts」近似；`burn_rate_daily` 以 UTC 切日。兩者皆為可接受的初期偏差。
