# One-time Credit 區塊設計

日期：2026-06-10

## 背景

配額制（quota）帳號的 Claude Code / Cowork **one-time credit**（一次性額度）會在 spend limit 之前被優先扣用。使用者希望 statusline 能把這筆 credit 的用量顯示出來，與既有的 spend 區塊並列。

`/api/oauth/usage` 回應中，這筆 credit 對應 `cinder_cove` 欄位：

```json
"cinder_cove": {
  "utilization": 7.8261234,
  "resets_at": "2026-09-07T12:53:42.383812+00:00"
}
```

對應 UI 上的「Claude Code and Cowork credit / Included credit — 8% used / Expires September 7」。

**限制**：`cinder_cove` 只有 `utilization`（百分比）與 `resets_at`（到期日），**沒有金額欄位**，因此 credit 只能以百分比＋到期倒數呈現，無法顯示 `$x/$y`。

## 需求決策（已與使用者確認）

1. **同時顯示**兩個區塊：credit 與 spend 並列。
2. **排序**：credit 在 spend **左邊**（語意上 credit → spend 的消耗順序）。
3. **範圍**：credit 區塊只在 **quota 帳號**出現（與 spend 綁定）。訂閱制帳號即使有 Claude Code credit 也不顯示。
4. **缺資料處理**：只有 `cinder_cove` 欄位存在（utilization 為數字）時才顯示 credit 區塊；欄位為 null／不存在時**整個區塊隱藏**，不合成假的 100%。

## 設計

### 1. 資料層：`core/fetch-usage.sh`

在現有 quota 契約輸出中，當 `cinder_cove.utilization` 為數字時，新增 `credit` 物件：

```json
{
  "account_type": "quota",
  "credit": {
    "utilization": 7.83,
    "resets_at": "2026-09-07T12:53:42.383812+00:00"
  },
  "spend": { "used_cents": 12156, "limit_cents": 50000, "utilization": 24.312, "currency": "USD", "resets_at": 1234567890 }
}
```

- `credit.utilization`：直接取 `cinder_cove.utilization`。
- `credit.resets_at`：取 `cinder_cove.resets_at`（ISO 字串，由顯示層轉成倒數，與既有 reset 處理一致）。
- `cinder_cove` 為 null 或 `utilization` 非數字 → **不輸出 `credit` 鍵**（資料層保持誠實，缺值由顯示層決定隱藏）。
- 不影響既有 `subscription` / `unknown` 契約路徑。

### 2. 渲染層：`statusline.sh`

- 從 `USAGE_CACHE` 讀取 `credit.utilization` → `credit_pct`、`credit.resets_at` → `credit_reset`（沿用既有 spend 欄位的讀取模式）。
- 新增 `credit` 區塊，**複用既有百分比區塊渲染器**（`render_pct_block` / `block_text_pct`），與 5H/7D 區塊同款：符號＋進度條＋已用百分比＋到期倒數。
  - PL（powerline rainbow）模式走 `block_text_pct`；classic 模式走 `render_pct_block`。
- 顏色複用既有區塊設定：以 `render_pct_block "rate_7d" ...` 的 block_name 取色（如同 spend 複用 `rate_5h`），**不需修改任何 theme 檔**。
- 符號：透過 `sym credit` 查 theme symbol；查無（回傳 `?`）時 fallback 到 `S_SPEND`／`S_COST`，確保 13 個既有 theme 無需改動也能運作。
- 標籤：`CR`（與 `5H`/`7D` 短標籤風格一致）。

### 3. 區塊排序：`statusline.sh` quota 組裝邏輯

目前 quota 模式會把 `rate_5h`/`rate_7d` 兩格塌縮成單一 `spend`。改為：當 `credit` 資料存在時，該位置展開成 **`credit` + `spend`**（credit 在左）；`credit` 不存在時維持只有 `spend`。

- PL rainbow 與 classic 兩條組裝路徑共用 `eff_blocks` 陣列，故只需在組裝 `eff_blocks` 時插入 `credit`。
- 兩處 dispatch（`block_text_*` 與 `render_block_*` 的 `case`）各新增一個 `credit` 分支。

## 測試

沿用既有測試風格（fixture 驅動、`USAGE_FIXTURE` 注入）：

1. **fetch-usage**（`tests/core/test-fetch-usage.sh`）：
   - 有 `cinder_cove` 的 fixture → 契約含 `credit.utilization` / `credit.resets_at`。
   - `cinder_cove: null` 的 fixture → 契約**不含** `credit` 鍵，但 spend 仍正常。
2. **renderer / statusline**：
   - quota + credit → 輸出同時含 credit 區塊與 spend 區塊，且 credit 在 spend 左邊。
   - quota 無 credit → 只有 spend 區塊。
   - 訂閱制 → 無 credit 區塊（範圍限制）。

## 影響範圍

- `core/fetch-usage.sh`：契約新增 `credit`。
- `statusline.sh`：讀取、區塊渲染、排序、dispatch。
- 測試 fixtures 與測試檔。
- 文件：README.md / docs/README.zh-TW.md 同步、LOG.md。
- **不需**修改 theme 檔。
