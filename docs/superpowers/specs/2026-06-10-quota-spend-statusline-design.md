# 配額制帳號 spend-limit 顯示與帳號類型自動偵測 — 設計文件

- 日期：2026-06-10
- 狀態：設計已確認，待寫實作計畫
- 相關檔案：`statusline.sh`、`core/`、`config.json`、`configure.sh`、`tests/`

## 背景與問題

使用者的 Claude 帳號從個人訂閱制（Pro/Max）轉為公司的 **Enterprise 固定月配額制（spend limit）**。
後台「Your usage limits」顯示：`$121.56 of $500.00 spent · Spend limit · Resets Wed, Jul 1, 8:00 AM GMT+8 · 24% used`。

目前 statusline 透過 stdin JSON 讀 `rate_limits.five_hour` / `rate_limits.seven_day`，但這兩個欄位**只有個人 Pro/Max 訂閱才會出現**。配額制帳號的 stdin JSON 完全沒有 `rate_limits`（實測：`cost.total_api_duration_ms > 0` 但 `rate_limits` 為 `null`），導致 5H / 7D 永遠顯示 `--`，也看不到任何用量百分比。

### 已排除的方案

- **stdin JSON**：配額制帳號完全沒有用量/配額欄位。
- **官方公開 API**：Anthropic 未提供個人成員可用的 spend 查詢端點（GitHub issue #19880、#44328、#45392 皆被標記 not planned / duplicate）。
- **Admin API**（`/v1/organizations/spend_limits/effective`）：能拿到精確 spend，但需 `sk-ant-admin-*` 管理員金鑰，一般組織成員產不出來。
- **本地 ccusage 月累計**：可行但為近似值，且非使用者選擇。

## 解法：逆向 Claude Code 內部 usage 端點

逆向 Claude Code 2.1.170 二進位檔得知 `/usage` 指令背後呼叫的端點與回傳結構：

### 端點

```
GET https://api.anthropic.com/api/oauth/usage
Headers:
  Authorization: Bearer <oauth-access-token>
  Content-Type: application/json
```

（二進位中函式名為 `fetchUtilization`，呼叫時帶 `refreshOAuth` 旗標、timeout 5s。）

### 回傳結構（Zod schema 摘要，`.describe("Plan rate-limit utilization windows")`）

```jsonc
{
  // 訂閱制才有；配額制為 null/缺席
  "five_hour":  { "utilization": <number>, "resets_at": <ISO8601>, ... },
  "seven_day":  { "utilization": <number>, "resets_at": <ISO8601>, ... },
  "seven_day_opus":   { ... },
  "seven_day_sonnet": { ... },

  // 配額/Enterprise 制才有意義
  "extra_usage": {
    "is_enabled":    <boolean>,
    "monthly_limit": <number|null>,   // 上限，單位 cents（$500 → 50000）
    "used_credits":  <number|null>,   // 已花，單位 cents（$121.56 → 12156）
    "utilization":   <number|null>,   // 已算好的百分比（例：24）
    "currency":      <string|null>    // 例："USD"
  }
}
```

> 注意：同一端點同時涵蓋訂閱制（`five_hour`/`seven_day`）與配額制（`extra_usage`），因此偵測與顯示都能以此回傳為準，比 stdin 更可靠。
> `extra_usage` 沒有 reset 欄位；spend limit 每月 1 號重置，reset 倒數於本地推算到「下月 1 號 00:00（當地時區）」。

### 憑證讀取

- **macOS（優先）**：`security find-generic-password -s "Claude Code-credentials" -w` → 解析 JSON → `.claudeAiOauth.accessToken`。
- **Fallback**：`~/.claude/.credentials.json` → `.claudeAiOauth.accessToken`。
- ⚠️ 安全性：腳本讀取使用者**自己的** OAuth token，僅用於查詢使用者**自己的**用量，**不寫入任何檔案、不外傳**。讀取失敗或 keychain 拒絕時靜默降級。

## 架構

新增單一模組，與現有 daily-cost 快取模式對齊；render 邏輯改動最小。

### 1. `core/fetch-usage.sh`（新檔，可獨立測試）

職責：取得 usage 資料並回傳正規化 JSON。對外介面為一個函式 / 可直接執行的腳本，輸出一段 JSON 到 stdout：

```jsonc
{
  "account_type": "quota" | "subscription" | "unknown",
  "spend": {            // 僅 quota 時存在
    "used_cents":  12156,
    "limit_cents": 50000,
    "utilization": 24,
    "currency":    "USD",
    "resets_at":   1751328000   // 下月 1 號 epoch 秒（本地推算）
  }
}
```

- 帳號類型判定：`extra_usage.monthly_limit` 有值（非 null）→ `quota`；否則若有 `five_hour`/`seven_day` → `subscription`；都沒有 → `unknown`。
- **可注入性（測試用）**：若環境變數 `USAGE_FIXTURE` 指向一個 JSON 檔，直接讀該檔當作 API 回傳，跳過網路與 token 讀取。供測試與離線開發。
- 任何錯誤（無 token、401、逾時、非 200、jq 失敗）→ 輸出 `{"account_type":"unknown"}` 並 exit 0（永不讓 statusline 失敗）。

### 2. 快取 + 背景刷新（沿用既有 daily-cost 寫法）

- 快取檔：`~/.cache/cyberpunk-statusline/usage.json`，TTL 60s。
- statusline 每次重繪讀快取；若快取過期，**背景**（`&` detach、與 daily-cost 相同手法）跑 `core/fetch-usage.sh` 更新快取，當次仍用舊快取值。
- 絕不在前景同步打 API（statusline 每秒可能重繪多次）。
- 測試可用 `USAGE_CACHE_OVERRIDE` 指向暫存快取檔，避免污染家目錄。

### 3. `statusline.sh` 改動

- **解析階段**：讀取 usage 快取，取得 `account_type` 與 `spend.*`，存入變數（`acct_type`、`spend_used`、`spend_limit`、`spend_pct`、`spend_reset`、`spend_currency`）。
- **帳號類型決議**：依 `config.account_type`（`auto`/`subscription`/`quota`）：
  - `auto`（預設）：用快取的 `account_type`。
  - `subscription`/`quota`：強制指定，跳過偵測。
- **block 決議**：當有效帳號類型為 `quota` 時，render 階段把 `rate_5h`、`rate_7d` 兩個 block 替換為單一 `spend` block（不改使用者的 blocks 設定檔，於 render 時動態置換）。訂閱制維持現狀。

### 4. `spend` block 渲染

- 沿用既有 `render_pct_block` / `block_text_pct` 的視覺樣式（圖示、bar、neon 警示色：utilization ≥50% 黃、≥80% 紅；bar 寬度/字元沿用 config）。
- 文字格式（使用者選定）：`<icon> $<used>/$<limit> <pct>% ↻<countdown>`
  - 金額由 cents 轉為整數美元顯示（`$122/$500`）；幣別非 USD 時改用對應符號/代碼。
  - `↻<countdown>` 沿用既有 `format_countdown`，目標為下月 1 號。
- **降級**：無法取得 spend（`account_type` 為 quota 但 spend 缺失，或 token/API 失敗）時，顯示 `<icon> $--` 占位（保留 block）。
- 圖示：沿用 nerd-font，挑一個錢/配額語意的符號（如 `󰈐`/`$`，實作時於 symbol map 增列 `spend`）。

### 5. 設定（`config.json` + `configure.sh`）

- `config.json` 新增 `account_type`（預設 `"auto"`）。
- `spend` 加入可選 block 與 symbol map；`configure.sh` 的 block 選單與預覽支援 `spend`。
- 不需使用者手動把 `spend` 放進 blocks——`auto` 模式下偵測到 quota 即自動以 spend 取代 5H/7D 的位置。

## 資料流

```
statusline 重繪
  └─ 讀 usage 快取 (~/.cache/.../usage.json)
       ├─ 命中且新鮮 → 用之
       └─ 過期/不存在 → 背景啟動 core/fetch-usage.sh（當次用舊值或 unknown）
                            └─ 讀 token（keychain → .credentials.json）
                               └─ GET /api/oauth/usage
                                  └─ 正規化 → 寫快取
  └─ 決議 account_type（config.account_type 或快取偵測值）
  └─ quota → render spend block（取代 5H/7D）
     subscription/unknown → 維持現有 5H/7D（stdin rate_limits）
```

## 錯誤處理

| 情境 | 行為 |
|------|------|
| 無 token / keychain 拒絕 | `account_type=unknown`；quota 已知時 spend 顯示 `$--` |
| API 401（token 過期） | 同上；交由 Claude Code 自行刷新 token，下次重繪讀到新 token |
| API 逾時 / 非 200 | 用既有快取；無快取則 `unknown` |
| jq / 解析失敗 | `unknown`，exit 0 |
| 任何狀況 | **statusline 永不報錯、永不阻塞** |

## 測試（對齊 `tests/` 既有 bash 斷言風格）

新增 `tests/core/test-fetch-usage.sh`：

- 以 `USAGE_FIXTURE` 餵入 quota 樣本 → 斷言輸出 `account_type=quota` 且 spend 數值正確（cents→dollar、utilization）。
- 餵入 subscription 樣本 → `account_type=subscription`。
- 餵入空 / 壞 JSON → `account_type=unknown` 且 exit 0。
- reset 推算：固定一個「現在時間」驗證下月 1 號 epoch。

擴充 `tests/test-statusline.sh`：

- 以 `USAGE_CACHE_OVERRIDE` 指向 quota 快取 + `account_type=auto` 的 config → 斷言輸出含 spend block（`$122/$500` 與百分比），且**不含** 5H/7D。
- quota 快取但 spend 缺失 → 斷言輸出 `$--` 占位。
- subscription / unknown → 斷言維持 5H/7D 行為。

新增 fixtures：`tests/core/fixtures/usage-quota.json`、`usage-subscription.json`、`usage-empty.json`。

## 範圍與 YAGNI

- **只**新增配額制的 spend 顯示與自動偵測；**不**改動訂閱制現有 5H/7D 行為（仍走 stdin `rate_limits`）。
- 不做 Admin API、不做本地 ccusage 月累計、不做 token 自動刷新。
- 不處理非 macOS 平台的 keychain（僅 `~/.claude/.credentials.json` fallback）；本專案主要使用環境為 macOS。

## 開放項目（實作時確認）

- spend block 的 nerd-font 圖示字元最終選定。
- 幣別非 USD 時的金額格式（先支援 USD，其他顯示代碼）。
- reset 倒數的時區基準（以本機時區的下月 1 號 00:00 為準）。
