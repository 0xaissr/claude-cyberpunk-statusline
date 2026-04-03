# Changelog

## 2026-04-03

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
