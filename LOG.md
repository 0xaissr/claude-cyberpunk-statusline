# Changelog

## 2026-04-03

### 重構：Powerline → Rainbow 風格 + Head/Tail 設定
- **重命名：** Powerline → Rainbow（參照 p10k prompt style 命名）
- **新增 `style` 設定：** `"classic"` 或 `"rainbow"`，取代用 separator 字元偵測
- **新增 Head 設定：** segment 左端形狀 — flat / sharp () / slanted () / rounded ()
- **新增 Tail 設定：** segment 間分隔 + 右端 — flat / sharp () / slanted () / rounded ()
- **Wizard 流程：** Step 4 改為 Prompt Style 選擇 → Rainbow 進入 Head/Tail 子步驟，Classic 進入 Separator 選擇
- **Config：** 新增 `style`、`head`、`tail` 欄位，所有下游預覽都傳遞 style 參數

### 新增：Powerline 風格渲染模式（已重構為 Rainbow）
- **功能：** 支援 Powerline 風格 — 每個 block 用 accent color 當背景、深色文字，blocks 間用 `` 箭頭連接
- **statusline.sh：** 新增 `PL_MODE` 偵測（separator 為 `` 或 ``）、`pl_block_bg()`/`pl_block_fg()` 色彩查詢、`block_text_*()` 內容 helpers、powerline assembly 迴圈
- **Theme：** 所有 14 個 theme 的 blocks 新增 `pl_bg`（accent 循環 1→2→3）和 `pl_fg`（bg_primary）
- **Configure wizard：** Step 4 separator 新增 Powerline 選項（第一個）

### 修正：所有 theme 的 nerd icons 缺失 + icon spacing 測試不完整
- **問題：** 所有 theme JSON 中 `rate_5h`、`directory`、`git`、`time` 的 nerd icon 為空字串，導致 font detection icon spacing 測試只顯示 3 個 icon（應有 7 個）
- **修正：** 補齊 14 個 theme 的 nerd icons（󰕐 timer-sand、󰉋 folder、󰊢 source-branch、󰅐 clock-outline），並重建 configure.sh 的 icon spacing 測試行

### 修正：configure wizard Step 2 blocks 預設改為全選（全開）
- 修正先前誤解：使用者要的是預設全選，讓使用者取消不要的 blocks

### 修正：configure wizard Step 1 font detection 圖示顯示為亂碼
- **問題：** `ask_yn` 用 `printf '%s'` 輸出 visual 內容，`\033[` 跳脫序列未被解析，直接顯示為文字
- **修正：** 改用 `printf '%b'` 讓 ANSI 色彩碼正確渲染

### 修正：configure wizard preview 全開時跳行 — 縮短 bar、model 名、重置時間
- **問題：** 全部 blocks 開啟時 preview 太寬導致跳行，影響可讀性
- **修正 1：** model display_name 從 `Opus 4.6 (1M context)` 縮短為 `Opus 4.6 (1M)`
- **修正 2：** 重置時間從不合理的 `↻95194d14h` 改為實際的 `↻99d23h`（動態計算 now + 99d23h）
- **修正 3：** Step 3 preview 的 bar_width 預設從 10 降為 6，避免在 bar_width 未選擇前就太寬

### 修正：configure wizard Step 2 blocks 預設應為全關
- **問題：** Step 2 checkbox 初始狀態從現有 config 讀取，預設全開，但使用者期望全關（opt-in）
- **修正：** 初始 states 全部設為 `0`，讓使用者自己勾選要顯示的 blocks

### 修正：configure wizard Step 1 問題文字被選項蓋掉
- **問題：** `ask_yn()` 的 prompt/visual 參數傳空字串，問題文字手動印在 row 5 後被 `ask_yn` 從同一行覆蓋，導致只看到 (y)/(n) 卻不知道在問什麼
- **修正：** 將三個 font detection 問題的文字和圖示改由 `ask_yn()` 的參數傳入，`ask_yn()` 內部依序排版 prompt → visual → 選項，不再互相覆蓋

### 實作：Configure Wizard v2 — 完整重寫
- `scripts/configure.sh` 全面重寫為 v2 wizard
  - Step 1: 字型能力偵測（y/n 問答，自動推斷 nerd/unicode/ascii）
  - Step 2: Blocks 選擇（checkbox toggle + 嵌入式 preview）
  - Step 3: Spacing + bar_width（數字選擇 + 嵌入式 preview，bar_width 條件觸發）
  - Step 4: Separator（數字選擇 + 嵌入式 preview）
  - Step 5: Time format（條件觸發，僅 time block 啟用時顯示）
  - Step 6: Theme（方向鍵導覽 + 即時 preview，「大揭曉」）
  - Step 7: 確認儲存（含 plugin cache 同步）
- 新增 `ask_yn()` 和 `ask_choice()` p10k 風格輸入函式
- 全域 `r` 鍵 restart 支援
- `scripts/statusline.sh` 新增 `time_format` 支援（24h/12h/24h-no-sec/12h-no-sec）
- config.json 新增 `time_format` 和 `bar_width` 可配置欄位

### 文件：Configure Wizard v2 改進計畫（v2 更新）
- 更新 `docs/plans/2026-04-03-configure-wizard-v2-plan.md` — 重新 brainstorming
- 混合輸入模式：字型偵測用 y/n（p10k 風格）、blocks 用 checkbox、其他用數字選擇、theme 用方向鍵
- 嵌入式 preview：每個選項下方直接嵌入渲染結果（使用預設主題），theme 步驟最後才選（大揭曉）
- 新流程 7 步：字型偵測 → blocks → spacing+bar_width → separator → time_format → theme → 儲存

### 新增：Midnight Phantom 主題
- 新增 `themes/midnight-phantom.json` — 午夜幻影賽博龐克主題
- `docs/all-themes.html` 加入第 13 號主題預覽，更新主題總數
- `scripts/configure.sh` 的 cyberpunk_order 加入 midnight-phantom

### 修正：configure.sh 設定不生效
- **問題：** configure.sh 寫入開發目錄的 config.json，但 Claude Code 讀取的是 plugin cache 目錄
- **修正：** step_done() 新增 plugin cache 同步邏輯 — 自動從 `~/.claude/settings.json` 偵測 plugin 安裝路徑並同步 config.json 和新主題檔案

### 修正：statusline 輸出缺少尾部換行
- **問題：** 輸出後沒有換行，導致其他提示文字接在同一行
- **修正：** statusline.sh 末尾加上 `echo ""` 確保換行

### 修正：倒數計時不顯示天數
- **問題：** format_countdown() 只計算時/分，超過 24 小時不會顯示天數格式
- **修正：** 加入 days 計算，超過 24h 顯示 `↻Xd Xh` 格式

### 設定變更
- config.json 更新為使用者選擇：midnight-phantom / ultra-compact / 4 blocks
