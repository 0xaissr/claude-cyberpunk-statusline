# One-time Credit 區塊 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在配額制（quota）帳號的 statusline 上，於 spend 區塊左側新增顯示 Claude Code one-time credit（`cinder_cove`）的用量百分比與到期倒數。

**Architecture:** 資料層 `core/fetch-usage.sh` 在 quota 契約中新增 `credit` 物件（百分比 + 由 ISO 轉成 epoch 的到期時間）。顯示層 `statusline.sh` 複用既有的百分比區塊渲染器（與 5H/7D 同款），並在 quota 組裝邏輯把 credit 插在 spend 之前。僅在 `cinder_cove` 存在時顯示，否則隱藏。不修改任何 theme 檔。

**Tech Stack:** Bash、jq、既有 fixture 驅動測試（`USAGE_FIXTURE` / `USAGE_CACHE_OVERRIDE` / `CONFIG_OVERRIDE`）。

---

## File Structure

- `core/fetch-usage.sh` — quota 分支新增 `credit` 物件輸出。
- `statusline.sh` — 讀取 credit 快取欄位、新增 `S_CREDIT` 符號、`block_text_credit` / `render_block_credit`、quota 組裝插入 credit、兩處 dispatch case。
- `tests/core/fixtures/usage-quota-credit.json` — 含 `cinder_cove` 的新 fixture。
- `tests/core/test-fetch-usage.sh` — 新增 credit 契約測試。
- `tests/test-statusline.sh` — 新增 credit 區塊渲染/隱藏測試。
- `README.md` / `docs/README.zh-TW.md` / `LOG.md` — 文件同步。

---

## Task 1: 資料層在 quota 契約輸出 credit

**Files:**
- Create: `tests/core/fixtures/usage-quota-credit.json`
- Modify: `core/fetch-usage.sh:45-62`
- Test: `tests/core/test-fetch-usage.sh`

- [ ] **Step 1: 建立含 cinder_cove 的 fixture**

Create `tests/core/fixtures/usage-quota-credit.json`:

```json
{
  "five_hour": null,
  "seven_day": null,
  "cinder_cove": {
    "utilization": 7.8261234,
    "resets_at": "2026-09-07T12:53:42.383812+00:00"
  },
  "extra_usage": {
    "is_enabled": true,
    "monthly_limit": 50000,
    "used_credits": 12156.0,
    "utilization": 24.312,
    "currency": "USD",
    "disabled_reason": null
  }
}
```

- [ ] **Step 2: 寫失敗測試**

在 `tests/core/test-fetch-usage.sh` 第 20 行（quota 區塊 `resets_at>now` 那行）之後插入：

```bash
# quota + one-time credit (cinder_cove)
out=$(USAGE_FIXTURE="$FIX/usage-quota-credit.json" bash "$FETCH")
check "credit: account_type"   "quota" "$(echo "$out" | jq -r '.account_type')"
check "credit: utilization"    "8"     "$(echo "$out" | jq -r '.credit.utilization | round')"
check "credit: resets_at>now"  "yes"   "$([ "$(echo "$out" | jq -r '.credit.resets_at')" -gt "$(date +%s)" ] && echo yes || echo no)"
check "credit: spend retained" "12156" "$(echo "$out" | jq -r '.spend.used_cents')"

# quota WITHOUT credit → no .credit key
out=$(USAGE_FIXTURE="$FIX/usage-quota.json" bash "$FETCH")
check "no-credit: key absent" "null" "$(echo "$out" | jq -r '.credit // "null"')"
```

- [ ] **Step 3: 執行測試確認失敗**

Run: `bash tests/core/test-fetch-usage.sh`
Expected: FAIL — `credit: utilization` 等項目失敗（目前契約無 `.credit`）。

- [ ] **Step 4: 實作 — 在 quota 分支加入 credit**

Modify `core/fetch-usage.sh`，將第 45-62 行的 jq filter 中 quota 分支（`if (.extra_usage.monthly_limit | type) == "number" then { ... }`）改為先建 base 物件，再依 `cinder_cove` 條件合併 `credit`。把原本：

```bash
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
```

替換為：

```bash
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
    + (if (.cinder_cove.utilization | type) == "number" then
        {
          credit: {
            utilization: .cinder_cove.utilization,
            resets_at: (
              .cinder_cove.resets_at
              | if type == "string"
                then (try (sub("\\.[0-9]+";"") | sub("\\+00:00$";"Z") | fromdateiso8601) catch null)
                else null end
            )
          }
        }
      else {} end)
```

說明：`fromdateiso8601` 只吃 `%Y-%m-%dT%H:%M:%SZ`，故先以 `sub` 去掉小數秒與把 `+00:00` 換成 `Z`；轉換失敗則 `resets_at` 為 null（顯示層自動不顯示倒數）。

- [ ] **Step 5: 執行測試確認通過**

Run: `bash tests/core/test-fetch-usage.sh`
Expected: `PASS=N FAIL=0`（含新增的 credit 測項全過）。

- [ ] **Step 6: Commit**

```bash
git add core/fetch-usage.sh tests/core/test-fetch-usage.sh tests/core/fixtures/usage-quota-credit.json
git commit -m "feat(usage): quota 契約新增 one-time credit（cinder_cove）輸出

- cinder_cove.utilization 存在時輸出 credit 物件
- resets_at ISO 轉 epoch（去小數秒、+00:00→Z），失敗則 null
- cinder_cove 不存在則不輸出 credit 鍵
- 新增 fixture 與 fetch-usage 測試

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: 顯示層讀取 credit 快取欄位

**Files:**
- Modify: `statusline.sh:283-291`

- [ ] **Step 1: 新增 credit 變數讀取**

Modify `statusline.sh`，將第 283 行：

```bash
spend_used_cents="" spend_limit_cents="" spend_pct="" spend_currency="" spend_reset=""
```

改為：

```bash
spend_used_cents="" spend_limit_cents="" spend_pct="" spend_currency="" spend_reset=""
credit_pct="" credit_reset=""
```

並在第 290 行（`spend_reset=$(...)`）之後、第 291 行 `fi` 之前插入：

```bash
  credit_pct=$("$JQ" -r '.credit.utilization // empty' "$USAGE_CACHE" 2>/dev/null)
  credit_reset=$("$JQ" -r '.credit.resets_at // empty' "$USAGE_CACHE" 2>/dev/null)
```

- [ ] **Step 2: 語法檢查**

Run: `bash -n statusline.sh`
Expected: 無輸出（語法正確）。

- [ ] **Step 3: Commit**

```bash
git add statusline.sh
git commit -m "feat(statusline): 從快取讀取 credit.utilization / resets_at

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: credit 符號與區塊渲染函式

**Files:**
- Modify: `statusline.sh:114-120`（符號）
- Modify: `statusline.sh:471-472`（render_block_*）
- Modify: `statusline.sh:406`（block_text_* 之後）

- [ ] **Step 1: 新增 S_CREDIT 符號（fallback 到 spend）**

Modify `statusline.sh`，在第 115 行（`[ "$S_SPEND" = "?" ] && S_SPEND="$S_COST"`）之後插入：

```bash
S_CREDIT=$(sym credit)
[ "$S_CREDIT" = "?" ] && S_CREDIT="$S_SPEND"
```

並把第 119 行的 show_icons 清除行：

```bash
  S_MODEL="" S_CTX="" S_5H="" S_7D="" S_DIR="" S_GIT="" S_TIME="" S_COST="" S_SPEND=""
```

改為（行尾追加 `S_CREDIT=""`）：

```bash
  S_MODEL="" S_CTX="" S_5H="" S_7D="" S_DIR="" S_GIT="" S_TIME="" S_COST="" S_SPEND="" S_CREDIT=""
```

- [ ] **Step 2: 新增 block_text_credit（PL 模式用）**

Modify `statusline.sh`，在第 406 行（`block_text_spend()` 函式結尾的 `}`）之後插入：

```bash
block_text_credit() {
  block_text_pct "rate_7d" "$S_CREDIT" "CR" "$credit_pct" "$credit_reset"
}
```

- [ ] **Step 3: 新增 render_block_credit（classic 模式用）**

Modify `statusline.sh`，在第 472 行（`render_block_rate_7d() { ... }`）之後插入：

```bash
render_block_credit() { render_pct_block "rate_7d" "$S_CREDIT" "CR" "$credit_pct" "$credit_reset"; }
```

說明：credit 複用 `rate_7d` 的顏色設定（quota 模式下 rate_7d 不顯示，不衝突），與 spend 複用 `rate_5h` 對稱；標籤 `CR` 與 `5H`/`7D` 風格一致。

- [ ] **Step 4: 語法檢查**

Run: `bash -n statusline.sh`
Expected: 無輸出。

- [ ] **Step 5: Commit**

```bash
git add statusline.sh
git commit -m "feat(statusline): 新增 credit 符號與 block_text_credit / render_block_credit

複用 rate_7d 顏色與百分比區塊渲染器，標籤 CR，符號 fallback 至 spend

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: quota 組裝插入 credit 並接上 dispatch

**Files:**
- Modify: `statusline.sh:594-596`（quota 組裝結尾）
- Modify: `statusline.sh:642`（PL dispatch）
- Modify: `statusline.sh:672`（classic dispatch）

- [ ] **Step 1: 寫失敗測試（credit 顯示 + 位於 spend 左側）**

在 `tests/test-statusline.sh` 第 200 行（`test_subscription_keeps_rate` 函式結尾 `}`）之後插入兩個測試：

```bash
test_credit_block_quota() {
  local cfg=$(mktemp) cache=$(mktemp)
  printf '{"theme":"terminal-glitch","symbol_set":"nerd","spacing":"normal","style":"classic","separator":"|","blocks":["model","rate_5h","rate_7d","time"],"bar_width":6,"show_icons":false,"account_type":"auto"}' > "$cfg"
  printf '{"account_type":"quota","credit":{"utilization":8,"resets_at":%s},"spend":{"used_cents":12156,"limit_cents":50000,"utilization":24,"currency":"USD","resets_at":%s}}' "$(($(date +%s)+7776000))" "$(($(date +%s)+1814400))" > "$cache"
  local out=$(cat "$SAMPLE" | CONFIG_OVERRIDE="$cfg" USAGE_CACHE_OVERRIDE="$cache" bash "$STATUSLINE" 2>/dev/null || true)
  rm -f "$cfg" "$cache"
  # credit 區塊出現（CR 8%），且位於 spend（$122/$500）左邊
  local cr_pos=$(echo "$out" | grep -bo 'CR' | head -1 | cut -d: -f1)
  local sp_pos=$(echo "$out" | grep -bo '122/' | head -1 | cut -d: -f1)
  if echo "$out" | grep -q 'CR' && echo "$out" | grep -q '8%' && [ -n "$cr_pos" ] && [ -n "$sp_pos" ] && [ "$cr_pos" -lt "$sp_pos" ]; then
    echo "✓ test_credit_block_quota: credit 區塊顯示且在 spend 左側"; ((PASS++))
  else
    echo "✗ test_credit_block_quota: credit 未顯示或順序錯誤 — got: $out"; ((FAIL++))
  fi
}

test_credit_absent_hidden() {
  local cfg=$(mktemp) cache=$(mktemp)
  printf '{"theme":"terminal-glitch","symbol_set":"nerd","spacing":"normal","style":"classic","separator":"|","blocks":["model","rate_5h","rate_7d","time"],"bar_width":6,"show_icons":false,"account_type":"auto"}' > "$cfg"
  printf '{"account_type":"quota","spend":{"used_cents":12156,"limit_cents":50000,"utilization":24,"currency":"USD","resets_at":%s}}' "$(($(date +%s)+1814400))" > "$cache"
  local out=$(cat "$SAMPLE" | CONFIG_OVERRIDE="$cfg" USAGE_CACHE_OVERRIDE="$cache" bash "$STATUSLINE" 2>/dev/null || true)
  rm -f "$cfg" "$cache"
  if echo "$out" | grep -q 'CR'; then
    echo "✗ test_credit_absent_hidden: 無 credit 時仍出現 CR — got: $out"; ((FAIL++))
  else
    echo "✓ test_credit_absent_hidden: 無 credit 時隱藏 credit 區塊"; ((PASS++))
  fi
}
```

並在 `main()` 中（第 214 行 `test_subscription_keeps_rate` 之後）登記：

```bash
  test_credit_block_quota
  test_credit_absent_hidden
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `bash tests/test-statusline.sh`
Expected: FAIL — `test_credit_block_quota` 失敗（credit 尚未組裝進輸出）。

- [ ] **Step 3: 實作 — quota 組裝插入 credit**

Modify `statusline.sh`，在第 594 行（quota `if` 分支結尾、`else` 之前；即第 593 行 `fi` 與第 594 行 `else` 之間）插入：

```bash
  # one-time credit 區塊：存在時插在第一個 spend 之前（credit → spend）
  if [ -n "$credit_pct" ]; then
    _tmp_blocks=()
    _cr_inserted=false
    for b in "${eff_blocks[@]}"; do
      if [ "$b" = "spend" ] && ! $_cr_inserted; then
        _tmp_blocks+=("credit")
        _cr_inserted=true
      fi
      _tmp_blocks+=("$b")
    done
    eff_blocks=("${_tmp_blocks[@]}")
  fi
```

（此區塊位於 `if [ "$eff_account_type" = "quota" ]; then ... ` 內、緊接在第 586-593 行的 fallback `if ! $_spend_added` 區塊之後、`else`（非 quota 分支）之前。）

- [ ] **Step 4: 接上 dispatch — PL 模式**

Modify `statusline.sh`，在第 642 行（`spend)     text=$(block_text_spend) ;;`）之後插入：

```bash
      credit)    text=$(block_text_credit) ;;
```

- [ ] **Step 5: 接上 dispatch — classic 模式**

Modify `statusline.sh`，在第 672 行（`spend)     output+=$(render_block_spend) ;;`）之後插入：

```bash
      credit)    output+=$(render_block_credit) ;;
```

- [ ] **Step 6: 執行測試確認通過**

Run: `bash tests/test-statusline.sh`
Expected: `test_credit_block_quota` 與 `test_credit_absent_hidden` 皆 ✓，整體 `FAIL=0`。

- [ ] **Step 7: 全套測試 + 語法檢查**

Run: `bash -n statusline.sh && bash tests/core/test-fetch-usage.sh && bash tests/test-statusline.sh`
Expected: 全部 PASS、無語法錯誤。

- [ ] **Step 8: Commit**

```bash
git add statusline.sh tests/test-statusline.sh
git commit -m "feat(statusline): quota 模式在 spend 左側插入 one-time credit 區塊

- credit_pct 存在時把 credit 插在第一個 spend 之前
- PL 與 classic 兩條 dispatch 路徑新增 credit case
- 新增 credit 顯示與無 credit 隱藏的整合測試

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: 文件同步

**Files:**
- Modify: `README.md`
- Modify: `docs/README.zh-TW.md`
- Modify: `LOG.md`

- [ ] **Step 1: 更新 README（英文）**

在 `README.md` 描述 quota / spend 顯示的段落中，補充說明：quota 帳號若有 Claude Code one-time credit（`cinder_cove`），會在 spend 區塊左側額外顯示一個 `CR` 區塊（百分比 + 到期倒數）；無此 credit 時自動隱藏。

- [ ] **Step 2: 更新 README（繁中）**

在 `docs/README.zh-TW.md` 對應段落做相同補充（依專案慣例：README 中英版必須同步）。

- [ ] **Step 3: 更新 LOG.md**

在 `LOG.md` 最新段落追加本次變更摘要：新增 one-time credit（cinder_cove）區塊、僅 quota 帳號、排在 spend 左側、無資料則隱藏。

- [ ] **Step 4: Commit**

```bash
git add README.md docs/README.zh-TW.md LOG.md
git commit -m "docs: 同步 README（中英）與 LOG 說明 one-time credit 區塊

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

- **Spec coverage：**
  - 同時顯示兩區塊 → Task 4 組裝插入。✓
  - credit 在 spend 左邊 → Task 4 插入邏輯 + 測試驗證位置。✓
  - 僅 quota → 插入邏輯位於 quota 分支內。✓
  - 缺 cinder_cove 隱藏 → Task 1 不輸出 credit 鍵 + Task 4 `credit_pct` 空則不插入 + `test_credit_absent_hidden`。✓
  - 百分比 + 到期倒數 → 複用 `render_pct_block` / `block_text_pct`。✓
  - 不改 theme → S_CREDIT fallback、複用 rate_7d 顏色。✓
- **Placeholder scan：** 無 TBD/TODO，所有 step 含實際程式碼與指令。
- **Type consistency：** 變數 `credit_pct` / `credit_reset`、契約鍵 `.credit.utilization` / `.credit.resets_at`、區塊名 `credit`、函式 `block_text_credit` / `render_block_credit`、符號 `S_CREDIT` 全程一致。
