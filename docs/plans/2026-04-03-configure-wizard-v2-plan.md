# Configure.sh 改進計畫：借鑑 Powerlevel10k 設定體驗

## Context

對比 Powerlevel10k 的 16 步設定精靈與 cyberpunk-statusline 目前的 5 步設定精靈，分析不足之處並新增缺失的流程。

p10k 的核心設計哲學：**讓使用者看到實際渲染結果來做決定**，而非讓使用者猜測技術選項的含義。

## 目前 configure.sh 的 5 步流程

1. Symbol Set（直接選 nerd/unicode/ascii）
2. Blocks（勾選要顯示的區塊）
3. Spacing（normal/compact/ultra-compact）
4. Separator（│ / · 空格 ›）
5. Theme（從 13 個主題中選）

## 對比 p10k 後的不足之處分析

### A. 重大缺失：字型能力偵測（p10k 步驟 1-4）

**問題：** 目前 Step 1 直接列出「Nerd Font / Unicode / ASCII」讓使用者選，但多數使用者不知道自己終端支援哪種。

**p10k 做法：** 逐一顯示特定字元（鎖頭、箭頭、圖示間距），問「你看到的是否正確？」，根據回答自動推斷最佳 symbol set。

**改進：** 新增 2-3 個視覺驗證問題，自動偵測 symbol set：
- Q1: 顯示 Nerd Font 圖示 `󰚩`，問「這看起來是一個圖示嗎？」→ Yes=可能支援 nerd font
- Q2: 顯示 Unicode 符號 `⬡ ◈ ⚡`，問「這三個符號都正確顯示嗎？」→ Yes=至少支援 unicode
- Q3:（若 nerd=yes）顯示多個 nerd icons 並排，問「圖示之間有沒有重疊？」→ 確認 nerd font 間距正常
- 根據回答自動選擇最佳 symbol set，而非讓使用者手動選

### B. 缺失：全域 (r) Restart 導覽

**問題：** 目前只有 `b`（上一步）和 `q`（離開），沒有重頭開始的選項。

**p10k 做法：** 每一步都有 `(r) Restart from the beginning`。

**改進：** 在每個步驟的 footer 中新增 `r` 鍵支援，重設所有 `sel_*` 變數並跳回 step 1。

### C. 缺失：bar_width 設定步驟

**問題：** `bar_width` 在 config.json 中存在但 wizard 中無法設定（硬寫 10）。

**改進：** 在 spacing 步驟中，若選擇 `normal` 或 `compact`（有 bar 的模式），追加 bar 寬度子選項（短 6 / 中 10 / 長 16），附 live preview。ultra-compact 不需要此步驟。

### D. 缺失：時間格式選項

**問題：** time block 硬編碼為 `HH:MM:SS`（24h），沒有 12h 或不顯示秒數的選項。

**p10k 做法：** 專門一步問「Show current time? No / 12-hour / 24-hour」。

**改進：** 新增 `time_format` 設定（`24h` / `12h` / `24h-no-sec` / `12h-no-sec`），在 blocks 步驟後、如果 time block 被啟用，插入此子步驟。

### E. 改善：步驟順序優化

**問題：** 目前 Theme 放在最後（Step 5），但主題是最影響視覺的選項，應該更早讓使用者看到。

**p10k 做法：** Prompt Style（大方向）在前，細節在後。

**改進建議的新順序：**
1. 字型能力偵測（自動，2-3 個 y/n 問題）
2. Theme（最大視覺影響，提前到第 2 步）
3. Blocks（選擇顯示哪些區塊）
4. Spacing + bar_width（顯示密度）
5. Separator（分隔符）
6. Time format（若啟用 time block）
7. 確認儲存

### F. 缺失：Preview 品質提升

**問題：** 目前 preview 位置固定在畫面底部，選項多時可能被擋到。

**p10k 做法：** 每個選項下方直接嵌入 preview，選項和 preview 視覺上緊密關聯。

**改進：** 在選項列表之後、footer 之前的固定區域渲染 preview，確保不會和選項重疊。對於 theme 步驟（選項多），可在游標移動時即時更新同一個 preview 區域（目前已有此功能，保持）。

## 修改檔案

| 檔案 | 變更 |
|------|------|
| `scripts/configure.sh` | 重構 wizard 流程、新增字型偵測步驟、新增 restart、調整步驟順序、新增 bar_width 和 time_format 步驟 |
| `scripts/statusline.sh` | 支援 `time_format` 設定欄位 |
| `config.json` | 新增 `time_format` 欄位 |

## 實作步驟

### Step 1: 新增字型能力偵測流程
- 新增 `step_font_detect()` 函式
- 問題 1：顯示 Nerd Font 圖示，問是否正確顯示
- 問題 2：顯示 Unicode 符號，問是否正確顯示
- 問題 3：（條件式）Nerd Font 間距測試
- 根據回答自動設定 `sel_symbols`
- 使用 y/n/r/q 輸入模式（類似 p10k）

### Step 2: 調整步驟順序
- 新順序：font_detect → theme → blocks → spacing（含 bar_width）→ separator → time_format → done
- 更新 main wizard loop 的 case 分支
- 更新 step 編號顯示（draw_header 的 step/total）

### Step 3: 新增全域 restart 支援
- 在 `read_key()` 中新增 `r` 鍵處理
- 每個 step 的 footer 加上 `r restart` 提示
- `r` 鍵行為：清除所有 `sel_*` 變數，`current_step=1`

### Step 4: 新增 bar_width 子步驟
- 在 spacing 步驟中，若選了 normal 或 compact，顯示 bar_width 選項
- 選項：Short (6) / Medium (10) / Long (16)
- Live preview 即時反映不同寬度

### Step 5: 新增 time_format 步驟
- 條件觸發：僅當 blocks 中包含 `time` 時顯示
- 選項：24h (16:23:42) / 12h (04:23:42 PM) / 24h short (16:23) / 12h short (4:23 PM)
- 在 `statusline.sh` 中讀取 `time_format` 並對應不同 `date` 格式

### Step 6: statusline.sh 支援新設定
- 讀取 `time_format` 設定（預設 `24h`）
- 根據值使用不同的 `date` 格式字串

### Step 7: 同步與測試
- 確保 `step_done()` 的 plugin cache 同步包含新欄位
- 向下相容：舊 config 無 `time_format` 時預設 `24h`

## 驗證方式

1. 執行 `bash scripts/configure.sh`，走完整個新流程
2. 確認字型偵測正確推斷 symbol set
3. 確認 (r) 鍵能重頭開始、所有選項重設
4. 確認 bar_width 選項只在 normal/compact spacing 時出現
5. 確認 time_format 步驟只在 time block 啟用時出現
6. 確認產出的 config.json 包含所有新欄位
7. 確認 statusline.sh 正確讀取 time_format 並渲染
8. 確認 plugin cache 同步正常
