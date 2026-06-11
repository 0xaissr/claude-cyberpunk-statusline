# 單日消耗速率追蹤（Daily Burn Rate）設計

- 日期：2026-06-11
- 狀態：設計完成，待實作計畫

## 目標

目前 statusline 只顯示「當下值」（5h/7d rate limit 使用率、今日花費、spend/credit 額度），
沒有任何時間序列，因此無法判斷「今天消耗得太快」。

本設計新增一套**單日消耗速率追蹤**機制：記錄每次（有消耗的）對話的使用率快照，
累積成時間序列，計算出「平均每日速率」與「剛好用完的每日速率」，
並在 statusline 即時告警、在 overview.sh 呈現每日趨勢。

判斷「太快」的基準為**自動預估**：若以目前速率線性外推會在 `resets_at` 之前就耗盡，即視為太快。

## 統一模型

不論帳號類型，追蹤的指標統一抽象成兩個共通屬性：

- `utilization`：0~100% 的累積使用率，在視窗內單調遞增，到 `resets_at` 歸零
- `resets_at`：視窗重置時間（epoch 秒）

追蹤的指標依帳號類型決定（重用 statusline 現有「依帳號類型挑指標」邏輯）：

| 帳號類型 | 追蹤的指標 |
|---|---|
| 配額制（quota） | 目前使用中的 credit 或 spend（沿用現有挑選邏輯） |
| 訂閱制（subscription） | 7D rate limit（`rate_limits.seven_day`） |

因為三者都可化約為 `utilization + resets_at`，計算與顯示邏輯只需寫一份。

## 架構：三個獨立單元

### 1. history logger（記錄）

- 檔案：`~/.cache/cyberpunk-statusline/usage-history.jsonl`（沿用現有 cache 目錄）
- 每筆 JSON：
  ```json
  {"ts": 1749600000, "account_type": "subscription", "metric": "seven_day", "utilization": 42.5, "resets_at": 1749945600}
  ```
- **寫入策略：依數值變化寫入**
  - 讀 history 最後一筆；若 `utilization` 與上一筆**相同**則不寫，**不同**才 append 一筆
  - 等同「每次有消耗就記一筆」，沒消耗時完全不寫 → 零重複、檔案乾淨
  - 不需要計時器：只比對「上一筆的值」
- **跨重置處理**：偵測 `resets_at` 與上一筆不同 → 視為進入新視窗（新視窗第一筆照常寫入）
- **保留期**：保留 30 天；每次寫入時順手清掉時間戳超過 30 天的舊列
- 觸發點：在 statusline.sh 算出當前指標後呼叫（此時 utilization / resets_at 皆已備妥）

設計理由：statusline 腳本是「每次 render 被叫起跑一次」的無常駐腳本，
拿不到「一次對話」這個事件，render 又很頻繁；以數值變化去重可精準對應「真正的消耗事件」。

### 2. rate calculator（計算）

從 history 讀取當前視窗（最新 `resets_at` 對應的那一段）的快照，計算：

- **平均每日速率（actual）** = `本視窗目前已用 utilization ÷ 視窗已過天數`
- **剛好用完的每日速率（sustainable）** = `(100 − 目前 utilization) ÷ 距 resets_at 剩餘天數`
- **今日消耗量** = 今天範圍內 utilization 的變化量（末筆 − 今天首筆；跨重置時以視窗為界處理）
- **剩餘量** = `100 − 目前 utilization`
- **太快判斷** = `actual > sustainable`（等價於線性外推會在 `resets_at` 前耗盡）

被 statusline 與 overview.sh 共用，避免重複計算邏輯。

#### 視窗起點與天數的處理（實作修正）

> 註：原設計打算用「history 中相異 `resets_at` 推算視窗長度」來定位視窗起點。
> 實作後以真實資料驗證發現：**API 每次 render 回傳的 `resets_at` 會隨現在時間漂移**
> （每筆差幾秒～幾天），並非穩定的視窗識別碼，該推算法會算出落在未來的起點而失效。
> 故改為下列做法。

- **先依當前指標過濾**：取最後一筆的 `metric`，只用同 metric 的列計算，避免 credit / spend / seven_day 混算。
- **視窗起點 = 最後一次 utilization 下降（reset）之後的那一筆**；若整段同 metric 序列無下降，則為第一筆。
  - reset 會把 utilization 歸零，所以「utilization 下降」就是視窗邊界的可靠訊號，不需依賴漂移的 `resets_at`。
- **剩餘天數（days_left）** 直接用最新一筆的 `resets_at`（漂移幾秒對天級尺度無感）。
- 視窗資料很少時（例如剛開始累積數十分鐘），平均速率會偏高，屬可接受的初期偏差，隨資料累積到整天即收斂。

### 3. 顯示層

#### statusline 新區塊

- 顯示「平均每日速率 / 剛好用完速率」兩個數字
- 太快（actual > sustainable）時變色告警
- 預設加入 `blocks` 設定，可由 config 開關（沿用現有 block 開關機制與 symbol/render 模式）

#### overview.sh

- 新增一段「每日消耗趨勢」：列出每天的消耗量與剩餘量
- 資料來源同樣是 usage-history.jsonl

## 資料流

```
statusline.sh render
  │
  ├─ 算出當前 utilization + resets_at（依帳號類型）
  ├─ history logger：與上一筆比值 → 有變化才 append（順手清 30 天前舊列）
  ├─ rate calculator：讀 history → actual / sustainable / 太快判斷
  └─ 顯示層：statusline 新區塊（太快變色）

overview.sh
  └─ rate calculator + 讀 history → 每日消耗量 / 剩餘量趨勢表
```

## 錯誤處理

- history 檔不存在 / 空 / 第一筆：正常建立，速率區塊顯示「資料不足」佔位（如 `--`），不報錯
- `resets_at` 缺失或無法解析：跳過該次記錄與速率計算，statusline 其他區塊不受影響
- 距 `resets_at` 剩餘天數 ≤ 0（已過期未刷新）：sustainable 不做除以零，顯示佔位
- 任何讀寫失敗都靜默降級，絕不阻斷 statusline 主流程（沿用現有快取降級慣例）

## 測試

- logger 去重：相同 utilization 不重複寫；不同才寫；跨 `resets_at` 視為新視窗
- 保留期：超過 30 天的列被清除
- rate calculator：給定 history fixtures，驗證 actual / sustainable / 今日消耗 / 剩餘 / 太快判斷
- 邊界：空 history、單筆、剩餘天數為 0、resets_at 缺失
- 沿用 tests/ 既有 fixtures 與測試骨架（參考 tests/core、tests/adapters）

## 範圍外（YAGNI）

- 不做跨日/跨週的長期統計圖表（overview 趨勢表已足夠）
- 不做使用者自訂每日預算（基準採自動預估）
- 不做背景常駐程式或 cron（純靠 render 觸發 + 數值去重）
