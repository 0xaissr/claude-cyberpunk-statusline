# 配額制 spend-limit 顯示與帳號類型自動偵測 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 偵測到 Enterprise/配額制帳號時，把 statusline 的 5H/7D 區塊換成「本月 spend / 上限」區塊（`$122/$500 24% ↻21d`），資料取自逆向出的 `GET /api/oauth/usage` 端點。

**Architecture:** 新增 `core/fetch-usage.sh` 負責讀本機 OAuth token、呼叫 usage 端點、輸出正規化 JSON；`statusline.sh` 以 60s 快取 + 背景刷新（沿用 daily-cost 模式）讀取結果，依 `account_type` 動態把 `rate_5h`/`rate_7d` 替換為 `spend` 區塊。失敗一律降級為 `$--`，statusline 永不阻塞。

**Tech Stack:** Bash、jq、curl、macOS `security`（keychain）、BSD `date`（GNU fallback）。測試為 bash 斷言（對齊 `tests/` 既有風格）。

**Spec:** `docs/superpowers/specs/2026-06-10-quota-spend-statusline-design.md`

---

## File Structure

- **Create** `core/fetch-usage.sh` — 取得並正規化 usage 資料，輸出 JSON 到 stdout。可用 `USAGE_FIXTURE` 注入假回應。唯一對外介面就是「執行它、讀 stdout」。
- **Create** `tests/core/test-fetch-usage.sh` — fetch-usage.sh 單元測試（用 fixtures，不打網路）。
- **Create** `tests/core/fixtures/usage-quota.json`、`usage-subscription.json`、`usage-empty.json` — 模擬 `/api/oauth/usage` 原始回應。
- **Modify** `statusline.sh` — 加 usage 快取讀取 + 背景刷新、token 無關（交給 fetch-usage.sh）、帳號類型決議、`spend` 區塊渲染（classic + rainbow）、區塊替換。
- **Modify** `config.json` — 新增 `account_type: "auto"`。
- **Modify** `configure.sh` — `account_type` 選項與 `spend` 區塊支援（最小變更）。
- **Modify** `tests/test-statusline.sh` — 用 `USAGE_CACHE_OVERRIDE` 測 spend 區塊渲染與替換。
- **Modify** `README.md` + `docs/README.zh-TW.md` — 文件同步（專案規則）。
- **Modify** `LOG.md` — 變更紀錄（專案規則）。

---

## Task 1: 驗證 spike — 確認端點可用與回傳結構

> 這是逆向出的未公開端點，**先實打確認**才動手建模組，避免 header 不足或結構不符。此 task 由人在場執行（會讀取本機 token）。

**Files:** 無（僅手動驗證並產生 fixtures）

- [ ] **Step 1: 取得 token 並呼叫端點**

```bash
# macOS keychain 優先，fallback credentials.json
TOKEN=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
  | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
[ -z "$TOKEN" ] && [ -f "$HOME/.claude/.credentials.json" ] && \
  TOKEN=$(jq -r '.claudeAiOauth.accessToken // empty' "$HOME/.claude/.credentials.json")

curl -sS --max-time 5 \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "anthropic-version: 2023-06-01" \
  "https://api.anthropic.com/api/oauth/usage" | jq .
```

- [ ] **Step 2: 確認回傳**

Expected：HTTP 200，JSON 含 `extra_usage` 物件，其 `used_credits` / `monthly_limit`（cents）/ `utilization` / `currency` 與後台 `$121.56 of $500.00 · 24%` 吻合。

若 401/403 或缺 header：逐一加減 header（移除 `anthropic-beta` 或 `anthropic-version`、加 `User-Agent: claude-cli`）找出最小可用組合，並把最終 header 組合記到本 task 下方。若完全失敗，停止並回報使用者（端點可能已變動）。

- [ ] **Step 3: 存成測試 fixtures**

把實際回傳（去識別化後）存為 `tests/core/fixtures/usage-quota.json`。內容形如：

```json
{
  "extra_usage": {
    "is_enabled": true,
    "monthly_limit": 50000,
    "used_credits": 12156,
    "utilization": 24,
    "currency": "USD"
  }
}
```

再手寫另外兩個 fixture：

`tests/core/fixtures/usage-subscription.json`：
```json
{
  "five_hour": { "utilization": 23.5, "resets_at": "2026-06-10T18:00:00Z" },
  "seven_day": { "utilization": 41.2, "resets_at": "2026-06-15T00:00:00Z" },
  "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null, "currency": null }
}
```

`tests/core/fixtures/usage-empty.json`：
```json
{}
```

- [ ] **Step 4: Commit**

```bash
git add tests/core/fixtures/usage-quota.json tests/core/fixtures/usage-subscription.json tests/core/fixtures/usage-empty.json
git commit -m "test(usage): 新增 /api/oauth/usage 回應 fixtures（驗證端點後擷取）"
```

---

## Task 2: `core/fetch-usage.sh` 正規化模組（TDD）

**Files:**
- Create: `core/fetch-usage.sh`
- Test: `tests/core/test-fetch-usage.sh`

正規化輸出契約（stdout，單行 JSON）：
```jsonc
// quota
{"account_type":"quota","spend":{"used_cents":12156,"limit_cents":50000,"utilization":24,"currency":"USD","resets_at":1751328000}}
// subscription
{"account_type":"subscription"}
// 無法判定 / 任何錯誤
{"account_type":"unknown"}
```
判定規則：`extra_usage.monthly_limit` 為數字 → `quota`；否則有 `five_hour` 或 `seven_day` → `subscription`；否則 `unknown`。
`resets_at` = 本機時區「下月 1 號 00:00」的 epoch 秒。

- [ ] **Step 1: 寫失敗測試 `tests/core/test-fetch-usage.sh`**

```bash
#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
FETCH="$PROJECT_DIR/core/fetch-usage.sh"
FIX="$SCRIPT_DIR/fixtures"

PASS=0; FAIL=0
check() { # desc, expected, actual
  if [ "$2" = "$3" ]; then echo "✓ $1"; ((PASS++)); else echo "✗ $1 — expected [$2] got [$3]"; ((FAIL++)); fi
}

# quota 樣本
out=$(USAGE_FIXTURE="$FIX/usage-quota.json" bash "$FETCH")
check "quota: account_type"  "quota" "$(echo "$out" | jq -r '.account_type')"
check "quota: used_cents"    "12156" "$(echo "$out" | jq -r '.spend.used_cents')"
check "quota: limit_cents"   "50000" "$(echo "$out" | jq -r '.spend.limit_cents')"
check "quota: utilization"   "24"    "$(echo "$out" | jq -r '.spend.utilization | round')"
check "quota: currency"      "USD"   "$(echo "$out" | jq -r '.spend.currency')"
check "quota: resets_at>now" "yes"   "$([ "$(echo "$out" | jq -r '.spend.resets_at')" -gt "$(date +%s)" ] && echo yes || echo no)"

# subscription 樣本
out=$(USAGE_FIXTURE="$FIX/usage-subscription.json" bash "$FETCH")
check "subscription: account_type" "subscription" "$(echo "$out" | jq -r '.account_type')"

# 空 / 壞輸入
out=$(USAGE_FIXTURE="$FIX/usage-empty.json" bash "$FETCH")
check "empty: account_type" "unknown" "$(echo "$out" | jq -r '.account_type')"
out=$(echo 'not json' > /tmp/cyberpunk-bad.json; USAGE_FIXTURE="/tmp/cyberpunk-bad.json" bash "$FETCH"; rm -f /tmp/cyberpunk-bad.json)
check "bad json: account_type" "unknown" "$(echo "$out" | jq -r '.account_type')"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `bash tests/core/test-fetch-usage.sh`
Expected: FAIL（`core/fetch-usage.sh` 不存在）

- [ ] **Step 3: 實作 `core/fetch-usage.sh`**

```bash
#!/usr/bin/env bash
# Fetch & normalize Claude usage from the (reverse-engineered) /api/oauth/usage
# endpoint. Outputs a single-line JSON contract to stdout. Never errors out:
# any failure yields {"account_type":"unknown"} with exit 0.
set -uo pipefail

JQ=$(command -v jq 2>/dev/null || echo "/opt/homebrew/bin/jq")
fail() { printf '{"account_type":"unknown"}\n'; exit 0; }
"$JQ" --version >/dev/null 2>&1 || fail

# ── Obtain raw response ─────────────────────────────────────────────────────
raw=""
if [ -n "${USAGE_FIXTURE:-}" ]; then
  # Test / offline injection
  raw=$(cat "$USAGE_FIXTURE" 2>/dev/null)
else
  # Read OAuth access token: macOS keychain first, then credentials.json
  token=""
  if command -v security >/dev/null 2>&1; then
    token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
      | "$JQ" -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
  fi
  if [ -z "$token" ] && [ -f "$HOME/.claude/.credentials.json" ]; then
    token=$("$JQ" -r '.claudeAiOauth.accessToken // empty' "$HOME/.claude/.credentials.json" 2>/dev/null)
  fi
  [ -z "$token" ] && fail
  command -v curl >/dev/null 2>&1 || fail
  raw=$(curl -sS --max-time 5 \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "anthropic-version: 2023-06-01" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
fi

# Validate JSON
echo "$raw" | "$JQ" empty >/dev/null 2>&1 || fail

# ── Compute next-month-1st reset (local midnight) epoch ─────────────────────
reset_epoch=$(date -v1d -v+1m -v0H -v0M -v0S +%s 2>/dev/null)
if [ -z "$reset_epoch" ]; then
  # GNU date fallback
  reset_epoch=$(date -d "$(date +%Y-%m-01) +1 month" +%s 2>/dev/null || echo 0)
fi

# ── Normalize ───────────────────────────────────────────────────────────────
echo "$raw" | "$JQ" -c --argjson reset "$reset_epoch" '
  if (.extra_usage.monthly_limit | type) == "number" then
    {
      account_type: "quota",
      spend: {
        used_cents:  (.extra_usage.used_credits // 0 | round),
        limit_cents: (.extra_usage.monthly_limit | round),
        utilization: (.extra_usage.utilization // 0),
        currency:    (.extra_usage.currency // "USD"),
        resets_at:   $reset
      }
    }
  elif (.five_hour != null) or (.seven_day != null) then
    {account_type: "subscription"}
  else
    {account_type: "unknown"}
  end
' 2>/dev/null || fail
```

然後 `chmod +x core/fetch-usage.sh`。

- [ ] **Step 4: 跑測試確認通過**

Run: `chmod +x core/fetch-usage.sh && bash tests/core/test-fetch-usage.sh`
Expected: PASS（`PASS=9 FAIL=0`）

- [ ] **Step 5: Commit**

```bash
git add core/fetch-usage.sh tests/core/test-fetch-usage.sh
git commit -m "feat(usage): 新增 fetch-usage.sh 正規化 /api/oauth/usage 並支援 fixture 注入"
```

---

## Task 3: statusline 讀取 usage 快取 + 背景刷新 + 帳號類型決議

**Files:**
- Modify: `statusline.sh`（在 daily-cost 區塊後，約 `statusline.sh:262` 之後插入；config 讀取區 `statusline.sh:69` 附近加 `account_type`）

- [ ] **Step 1: 讀取 `account_type` 設定**

在 `statusline.sh:69`（`cfg_time_format=...` 之後）新增：

```bash
cfg_account_type=$("$JQ" -r '.account_type // "auto"' "$CONFIG")
```

- [ ] **Step 2: 在 daily-cost 區塊後插入 usage 快取邏輯**

於 `statusline.sh:262`（`fi` 結束 daily-cost 之後、`# ── Custom renderer check` 之前）插入：

```bash
# ── Usage / spend (cached, background refresh) ────────────────────────────
USAGE_CACHE="${USAGE_CACHE_OVERRIDE:-$COST_CACHE_DIR/usage.json}"
USAGE_CACHE_MAX_AGE=60

# Background-refresh when stale (skip entirely when a test override is set —
# the override supplies a fixed cache and must not trigger a network call).
if [ -z "${USAGE_CACHE_OVERRIDE:-}" ]; then
  if [ ! -f "$USAGE_CACHE" ] || [ $(($(date +%s) - $(stat -f%m "$USAGE_CACHE" 2>/dev/null || echo 0))) -gt "$USAGE_CACHE_MAX_AGE" ]; then
    mkdir -p "$COST_CACHE_DIR"
    ( "$SCRIPT_DIR/core/fetch-usage.sh" > "$USAGE_CACHE.tmp" 2>/dev/null && mv -f "$USAGE_CACHE.tmp" "$USAGE_CACHE" ) &
    disown 2>/dev/null || true
  fi
fi

# Read whatever the cache currently holds (may be from previous render).
acct_type="unknown"
spend_used_cents="" spend_limit_cents="" spend_pct="" spend_currency="" spend_reset=""
if [ -f "$USAGE_CACHE" ]; then
  acct_type=$("$JQ" -r '.account_type // "unknown"' "$USAGE_CACHE" 2>/dev/null || echo unknown)
  spend_used_cents=$("$JQ" -r '.spend.used_cents // empty' "$USAGE_CACHE" 2>/dev/null)
  spend_limit_cents=$("$JQ" -r '.spend.limit_cents // empty' "$USAGE_CACHE" 2>/dev/null)
  spend_pct=$("$JQ" -r '.spend.utilization // empty' "$USAGE_CACHE" 2>/dev/null)
  spend_currency=$("$JQ" -r '.spend.currency // "USD"' "$USAGE_CACHE" 2>/dev/null)
  spend_reset=$("$JQ" -r '.spend.resets_at // empty' "$USAGE_CACHE" 2>/dev/null)
fi

# Effective account type: config override wins over detection.
case "$cfg_account_type" in
  subscription|quota) eff_account_type="$cfg_account_type" ;;
  *)                  eff_account_type="$acct_type" ;;
esac
```

- [ ] **Step 3: 手動 smoke test（不破壞現有行為）**

Run:
```bash
echo '{"account_type":"unknown"}' > /tmp/u.json
cat tests/sample-input.json | USAGE_CACHE_OVERRIDE=/tmp/u.json bash statusline.sh
```
Expected: 正常輸出（unknown → 維持現有 5H/7D 行為），無報錯。

- [ ] **Step 4: Commit**

```bash
git add statusline.sh
git commit -m "feat(statusline): 讀取 usage 快取並做帳號類型決議（背景刷新沿用 daily-cost 模式）"
```

---

## Task 4: spend 區塊渲染與 5H/7D 替換

**Files:**
- Modify: `statusline.sh`（symbol 區 `:112` 附近、helper 區、render 區、兩處 assembly 迴圈）

- [ ] **Step 1: 新增 spend symbol（fallback 到 cost icon）**

在 `statusline.sh:112`（`S_COST=$(sym cost)` 之後）新增：

```bash
S_SPEND=$(sym spend)
[ "$S_SPEND" = "?" ] && S_SPEND="$S_COST"
```

並在 `statusline.sh:116` 的 show_icons 清除行尾加上 `S_SPEND=""`：

```bash
  S_MODEL="" S_CTX="" S_5H="" S_7D="" S_DIR="" S_GIT="" S_TIME="" S_COST="" S_SPEND=""
```

- [ ] **Step 2: 新增金額格式 helper（緊接在 `format_countdown` 之後，約 `:289`）**

```bash
# ── Spend formatting helpers ──────────────────────────────────────────────
# Round cents → whole-dollar integer.
spend_dollars() { local c="${1:-0}"; echo $(( (c + 50) / 100 )); }
# Currency prefix: "$" for USD, otherwise "<CODE> ".
spend_cur() { if [ "${1:-USD}" = "USD" ] || [ -z "${1:-}" ]; then echo -n "\$"; else echo -n "${1} "; fi; }
```

- [ ] **Step 3: 新增 `block_text_spend`（rainbow 用，text only）**

在 `block_text_cost`（`:354`）之後新增：

```bash
block_text_spend() {
  if [ -z "$spend_limit_cents" ]; then echo -n " ${S_SPEND} \$-- "; return; fi
  local cur=$(spend_cur "$spend_currency")
  local used=$(spend_dollars "$spend_used_cents")
  local limit=$(spend_dollars "$spend_limit_cents")
  local pct_int=$(printf "%.0f" "$spend_pct")
  local countdown=$(format_countdown "$spend_reset")
  local reset_str=""; [ -n "$countdown" ] && reset_str=" ${countdown}"
  echo -n " ${S_SPEND} ${cur}${used}/${cur}${limit} ${pct_int}%${reset_str} "
}
```

- [ ] **Step 4: 新增 `render_block_spend`（classic 用，含 neon 色與 bar）**

在 `render_block_cost`（`:456`）之後新增。沿用 `rate_5h` 的色彩對映（spend 佔據 5H/7D 的位置）：

```bash
render_block_spend() {
  local fg_hex=$(block_color rate_5h)
  local bg_hex=$(block_bg rate_5h)
  local fg=$(hex_to_fg "$fg_hex")
  local bg=$(hex_to_bg "$bg_hex")
  local bar_bg=$(hex_to_bg "$C_BG_PRIMARY")
  local dim_fg=$(hex_to_fg "$C_DIM")

  if [ -z "$spend_limit_cents" ]; then
    echo -n "${bg}${dim_fg} ${S_SPEND} \$-- ${RESET}"
    return
  fi

  local cur=$(spend_cur "$spend_currency")
  local used=$(spend_dollars "$spend_used_cents")
  local limit=$(spend_dollars "$spend_limit_cents")
  local pct_int=$(printf "%.0f" "$spend_pct")
  local col=$(neon_colour "$pct_int" "$fg_hex" "$C_WARNING" "$C_ALERT")
  local countdown=$(format_countdown "$spend_reset")
  local reset_str=""; [ -n "$countdown" ] && reset_str=" ${dim_fg}${countdown}${RESET}"
  local amt="${cur}${used}/${cur}${limit}"

  case "$cfg_spacing" in
    ultra-compact)
      echo -n "${bar_bg}${col} ${S_SPEND} ${BOLD}${amt} ${pct_int}%${reset_str} ${RESET}"
      ;;
    *)
      local c_bar_f="${cfg_bar_filled:-$S_BAR_FILLED}" c_bar_e="${cfg_bar_empty:-$S_BAR_EMPTY}"
      local bar=$(make_bar "$pct_int" "$cfg_bar_width" "$c_bar_f" "$c_bar_e")
      echo -n "${bg}${fg}${BOLD} ${S_SPEND} ${RESET}${bar_bg}${col} ${amt} ${bar} ${BOLD}${pct_int}%${reset_str} ${RESET}"
      ;;
  esac
}
```

- [ ] **Step 5: 新增 effective blocks 計算（替換 5H/7D → spend）**

在 assembly 區塊開始前（`# ── Assemble`，`:485` 附近、`output=""` 之後）新增：

```bash
# When the effective account type is quota, replace the rate_5h/rate_7d slot
# with a single spend block (first rate block becomes spend, the other drops).
eff_blocks=()
if [ "$eff_account_type" = "quota" ]; then
  _spend_added=false
  for b in $cfg_blocks; do
    if [ "$b" = "rate_5h" ] || [ "$b" = "rate_7d" ]; then
      if ! $_spend_added; then eff_blocks+=("spend"); _spend_added=true; fi
      continue
    fi
    eff_blocks+=("$b")
  done
  # If config had neither rate block, surface spend after context (or at end).
  if ! $_spend_added; then
    eff_blocks=()
    for b in $cfg_blocks; do
      eff_blocks+=("$b")
      [ "$b" = "context" ] && eff_blocks+=("spend") && _spend_added=true
    done
    $_spend_added || eff_blocks+=("spend")
  fi
else
  for b in $cfg_blocks; do eff_blocks+=("$b"); done
fi
```

- [ ] **Step 6: 兩處 assembly 改用 `eff_blocks` 並加 `spend` case**

rainbow 區（`:491`）把 `for b in $cfg_blocks; do block_list+=("$b"); done` 改成：

```bash
  block_list=()
  for b in "${eff_blocks[@]}"; do block_list+=("$b"); done
```

並在 rainbow 的 `case "$block"`（`:523`）加一行（在 `cost)` 之後）：

```bash
      spend)     text=$(block_text_spend) ;;
```

classic 區（`:546`）把 `for block in $cfg_blocks; do` 改成：

```bash
  for block in "${eff_blocks[@]}"; do
```

並在 classic 的 `case "$block"`（`:560`）加一行（在 `cost)` 之後）：

```bash
      spend)     output+=$(render_block_spend) ;;
```

- [ ] **Step 7: 手動驗證 quota 顯示**

Run（classic）:
```bash
printf '{"account_type":"quota","spend":{"used_cents":12156,"limit_cents":50000,"utilization":24,"currency":"USD","resets_at":%s}}' \
  "$(($(date +%s)+1814400))" > /tmp/uq.json
printf '{"theme":"terminal-glitch","symbol_set":"nerd","spacing":"normal","style":"classic","separator":"|","blocks":["model","context","rate_5h","rate_7d","cost","time"],"bar_width":6,"show_icons":true,"account_type":"auto"}' > /tmp/cq.json
cat tests/sample-input.json | CONFIG_OVERRIDE=/tmp/cq.json USAGE_CACHE_OVERRIDE=/tmp/uq.json bash statusline.sh
```
Expected: 輸出含 `$122/$500 24% ↻21d`（或近似），且**不含** 5H / 7D。

- [ ] **Step 8: Commit**

```bash
git add statusline.sh
git commit -m "feat(statusline): 配額制帳號將 5H/7D 替換為 spend 區塊（金額/百分比/重置倒數）"
```

---

## Task 5: 整合測試（statusline + USAGE_CACHE_OVERRIDE）

**Files:**
- Modify: `tests/test-statusline.sh`

- [ ] **Step 1: 在 `tests/test-statusline.sh` 末端（PASS/FAIL 統計列印前）新增測試函式並呼叫**

```bash
test_spend_block_quota() {
  local cfg=$(mktemp) cache=$(mktemp)
  printf '{"theme":"terminal-glitch","symbol_set":"nerd","spacing":"ultra-compact","style":"classic","separator":"|","blocks":["model","rate_5h","rate_7d","time"],"bar_width":6,"show_icons":true,"account_type":"auto"}' > "$cfg"
  printf '{"account_type":"quota","spend":{"used_cents":12156,"limit_cents":50000,"utilization":24,"currency":"USD","resets_at":%s}}' "$(($(date +%s)+1814400))" > "$cache"
  local out=$(cat "$SAMPLE" | CONFIG_OVERRIDE="$cfg" USAGE_CACHE_OVERRIDE="$cache" bash "$STATUSLINE" 2>/dev/null || true)
  rm -f "$cfg" "$cache"
  if echo "$out" | grep -q '\$122/\$500' && echo "$out" | grep -q '24%'; then
    echo "✓ test_spend_block_quota: spend block 顯示金額與百分比"; ((PASS++))
  else
    echo "✗ test_spend_block_quota: 未顯示 spend 金額/百分比 — got: $out"; ((FAIL++))
  fi
}

test_spend_replaces_rate() {
  local cfg=$(mktemp) cache=$(mktemp)
  printf '{"theme":"terminal-glitch","symbol_set":"nerd","spacing":"normal","style":"classic","separator":"|","blocks":["model","rate_5h","rate_7d","time"],"bar_width":6,"show_icons":false,"account_type":"auto"}' > "$cfg"
  printf '{"account_type":"quota","spend":{"used_cents":12156,"limit_cents":50000,"utilization":24,"currency":"USD","resets_at":%s}}' "$(($(date +%s)+1814400))" > "$cache"
  local out=$(cat "$SAMPLE" | CONFIG_OVERRIDE="$cfg" USAGE_CACHE_OVERRIDE="$cache" bash "$STATUSLINE" 2>/dev/null || true)
  rm -f "$cfg" "$cache"
  # show_icons=false → labels 出現；spend 取代後不應看到 5H / 7D label
  if echo "$out" | grep -qE '5H|7D'; then
    echo "✗ test_spend_replaces_rate: quota 模式仍出現 5H/7D — got: $out"; ((FAIL++))
  else
    echo "✓ test_spend_replaces_rate: quota 模式已移除 5H/7D"; ((PASS++))
  fi
}

test_spend_degraded() {
  local cfg=$(mktemp) cache=$(mktemp)
  printf '{"theme":"terminal-glitch","symbol_set":"nerd","spacing":"ultra-compact","style":"classic","separator":"|","blocks":["model","rate_5h","time"],"bar_width":6,"show_icons":true,"account_type":"quota"}' > "$cfg"
  printf '{"account_type":"unknown"}' > "$cache"
  local out=$(cat "$SAMPLE" | CONFIG_OVERRIDE="$cfg" USAGE_CACHE_OVERRIDE="$cache" bash "$STATUSLINE" 2>/dev/null || true)
  rm -f "$cfg" "$cache"
  # 強制 quota 但無 spend 資料 → 顯示 $-- 占位
  if echo "$out" | grep -q '\$--'; then
    echo "✓ test_spend_degraded: 無資料時顯示 \$-- 占位"; ((PASS++))
  else
    echo "✗ test_spend_degraded: 未顯示 \$-- 占位 — got: $out"; ((FAIL++))
  fi
}

test_subscription_keeps_rate() {
  local cfg=$(mktemp) cache=$(mktemp)
  printf '{"theme":"terminal-glitch","symbol_set":"nerd","spacing":"normal","style":"classic","separator":"|","blocks":["model","rate_5h","rate_7d","time"],"bar_width":6,"show_icons":false,"account_type":"auto"}' > "$cfg"
  printf '{"account_type":"subscription"}' > "$cache"
  local out=$(cat "$SAMPLE" | CONFIG_OVERRIDE="$cfg" USAGE_CACHE_OVERRIDE="$cache" bash "$STATUSLINE" 2>/dev/null || true)
  rm -f "$cfg" "$cache"
  if echo "$out" | grep -qE '5H|7D'; then
    echo "✓ test_subscription_keeps_rate: 訂閱制維持 5H/7D"; ((PASS++))
  else
    echo "✗ test_subscription_keeps_rate: 訂閱制遺失 5H/7D — got: $out"; ((FAIL++))
  fi
}
```

並在檔案底部現有測試呼叫清單中加上：
```bash
test_spend_block_quota
test_spend_replaces_rate
test_spend_degraded
test_subscription_keeps_rate
```

> 註：`sample-input.json` 無 `rate_limits`，故 subscription 測試中 5H/7D 會以 `--` 呈現但 label 仍在——足以驗證「區塊未被移除」。

- [ ] **Step 2: 跑全部 statusline 測試**

Run: `bash tests/test-statusline.sh`
Expected: 全數 PASS（含新增 4 項）

- [ ] **Step 3: Commit**

```bash
git add tests/test-statusline.sh
git commit -m "test(statusline): 新增 spend 區塊渲染、替換、降級與訂閱制保留的整合測試"
```

---

## Task 6: 設定檔與 configure.sh

**Files:**
- Modify: `config.json`
- Modify: `configure.sh`

- [ ] **Step 1: `config.json` 新增 `account_type`**

在 `config.json` 加入（置於 `time_format` 之後）：
```json
  "account_type": "auto"
```

- [ ] **Step 2: configure.sh 寫出 `account_type`（最小變更）**

在 `configure.sh` 產生 `config.json` 的 jq/heredoc 區塊找出 `time_format` 寫出處，比照加入 `account_type`（預設 `auto`）。若 configure.sh 以固定鍵集合寫檔，於同處新增 `--arg account_type "${ACCOUNT_TYPE:-auto}"` 與對應 `account_type: $account_type`。保持與既有鍵相同寫法（讀檔確認後再改）。

> spend 區塊不需出現在 configure 的 block 選單——它由 `auto` 偵測自動取代 5H/7D，使用者無需手動選。

- [ ] **Step 3: 驗證 config 有效且 statusline 不報錯**

Run:
```bash
jq . config.json >/dev/null && echo "config.json valid"
cat tests/sample-input.json | bash statusline.sh >/dev/null && echo "statusline ok"
bash tests/test-configure.sh
```
Expected: `config.json valid`、`statusline ok`、configure 測試 PASS

- [ ] **Step 4: Commit**

```bash
git add config.json configure.sh
git commit -m "feat(config): 新增 account_type 設定（auto/subscription/quota，預設 auto）"
```

---

## Task 7: 文件同步與 LOG

**Files:**
- Modify: `README.md`、`docs/README.zh-TW.md`、`LOG.md`

- [ ] **Step 1: README 雙語同步**

在 `README.md` 的功能/區塊說明處新增 spend 區塊與 `account_type` 說明：偵測到 Enterprise/配額制帳號（無 rate limits）時，自動以本月 spend 用量（`$used/$limit pct% ↻reset`）取代 5H/7D；資料取自 Claude Code 自身使用的 usage 端點，僅讀本機憑證、不外傳；`account_type` 可設 `auto`（預設）/`subscription`/`quota`。
在 `docs/README.zh-TW.md` 對應段落做**相同**內容的繁中更新（專案規則：兩版本必須同步）。

- [ ] **Step 2: 更新 LOG.md**

在 `LOG.md` 最新區段新增本次變更摘要（配額制 spend 顯示 + 自動偵測 + usage 端點來源 + 安全性註記）。

- [ ] **Step 3: 全測試回歸**

Run:
```bash
bash tests/core/test-fetch-usage.sh; bash tests/test-statusline.sh; bash tests/test-configure.sh
```
Expected: 全數 PASS

- [ ] **Step 4: Commit**

```bash
git add README.md docs/README.zh-TW.md LOG.md
git commit -m "docs: 同步 README（中英）與 LOG 說明配額制 spend 顯示與 account_type"
```

---

## 完成後驗證清單

- [ ] 真實環境：把 `account_type` 設 `auto`，重繪 statusline，第二次重繪起應看到 `$122/$500 24% ↻Nd`（首繪可能仍是舊狀態，因背景刷新）。
- [ ] 斷網或改壞 token：spend 區塊降級為 `$--`，statusline 不卡、不報錯。
- [ ] `account_type: "subscription"` 強制 → 維持 5H/7D。
- [ ] rainbow 與 classic 兩種 style 皆正常。
