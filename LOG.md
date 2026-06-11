# Changelog

## 2026-06-11

### 新增：burn 單日消耗速率區塊 + 使用率歷史記錄 + overview 每日趨勢

- **使用率歷史記錄（usage-history logger）**：每次 statusline render 時將當前使用率（utilization%）與 resets_at 寫入 `~/.cache/cyberpunk-statusline/usage-history.jsonl`；採依數值去重（utilization 未改變時不重複寫入），自動保留最近 30 天資料
- **Burn rate 計算器**：從歷史記錄計算「平均每日消耗速率（avg %/day）」與「剛好在重置前用完的可持續速率（sustainable %/day）」；歷史資料不足時回傳 `--/--`
- **`burn` statusline 區塊**：格式為 `󱐋 avg/sustainable%/d`（例：`󱐋 20/10%/d`）；當平均速率超過可持續速率（即以目前速度會在重置前提早耗盡）時自動轉為告警色；`burn` 已加入預設 blocks 清單（位於 `cost` 之後）
- **統一 utilization 模型**：metric 依帳號類型跟隨既有邏輯 — quota 帳號取 credit 或 spend（以使用中的為準）；subscription 帳號取 7D 速率限制；統一以 utilization% + resets_at 表示，不需個別處理
- **overview.sh DAILY BURN TREND 區塊**：`overview.sh` 新增每日趨勢段落，顯示各天已消耗%／剩餘% 及當前速率預測（pace hint）
- **文件同步**：`README.md`（英文）與 `docs/README.zh-TW.md`（繁中）的可用區塊表格新增 `burn` 說明

### 修正：burn 區塊永遠顯示 `--/--`（視窗起點計算錯誤）

- **根本原因**：實際資料顯示 API 每次 render 回傳的 `resets_at` 會隨「現在時間」漂移（每筆差幾秒～幾天），並非穩定的視窗識別碼。原 `burn_rate_calc` 用「history 中相異 resets_at 推算視窗長度」（`reset − resets[-2]`），在漂移與多 metric 混雜下會算出**落在未來的視窗起點** → `elapsed_days` 為負 → `actual` 為 null → 顯示 `--/--`
- **修正**：`burn_rate_calc` / `burn_rate_daily` 改為 (1) 先依「當前指標」（最後一筆 metric）過濾，避免 credit/spend/seven_day 混算；(2) 視窗起點改用「最後一次 utilization 下降（reset）之後」偵測，不再用 resets_at 推算；(3) `days_left` 直接用最新 `resets_at`
- **記錄器去重改鍵**：由 `(utilization, resets_at)` 改為 `(metric, utilization)`。因 resets_at 漂移會讓 util 未變卻每次 render 都寫一筆而爆量（實測 1 小時 78 筆）；reset 本質是 util 下降，仍會被記錄，視窗邊界不漏
- **資料修復**：清理開發測試期間混入真實 history 的 fixture 殘留（util 8/24/33 等多 metric 雜訊），備份為 `usage-history.jsonl.bak.*`

### 調整：burn 顯示改為「預估耗盡天數/重置天數」

- 原顯示 `actual/sustainable%/d`（兩個 %/day 數字）不易解讀。改為 `Xd/Yd`：以目前速度預估約 `X` 天用完，距實際重置還有 `Y` 天；`X < Y` 時告警色。例：`󱐋 0.8d/89d`
- 新增 `_burn_days`（awk）將 actual/sustainable/remaining 換算成天數字串；無近期消耗顯示 `∞`，資料不足顯示 `--/--`
- 同步 README（中英）與測試（改驗 `Xd/Yd` 格式）

## 2026-06-10

### 新增：一次性 Claude Code／Cowork credit（cinder_cove）顯示區塊
- 功能：配額制帳號若有一次性 Claude Code／Cowork credit（`cinder_cove`），statusline 在 spend 區塊左側自動插入 `CR` 區塊，顯示已用百分比、進度條與到期倒數（`↻…`）；此 credit 僅提供百分比，**無金額**；帳號無此 credit 時自動隱藏，無需任何設定
- 訂閱制帳號不受影響
- 資料層：`core/fetch-usage.sh` 在 quota 契約解析時新增 `credit` 物件（包含 `utilization`、`resets_at`，`resets_at` 由 ISO 格式轉換為 epoch；僅在 `cinder_cove.utilization` 為數字時才輸出）
- 顯示層：重用 `rate_7d` 區塊色彩，不需修改 theme 檔案
- 文件：同步更新 `README.md`（英文）與 `docs/README.zh-TW.md`（繁中），新增 credit 欄位說明於區塊表格與 Spend 區塊章節

### 新增：配額制帳號 spend 顯示與帳號類型自動偵測（account_type）
- 功能：偵測到企業版／配額制 Claude 帳號（無個人速率限制）時，statusline 自動將 `rate_5h` / `rate_7d` 區塊替換為本月 spend 用量區塊，格式為 `$used/$limit pct% ↻Xd`
- 新增 `account_type` 設定欄位：
  - `auto`（預設）— 自動偵測帳號類型，有速率限制顯示 5H/7D，無則顯示 spend
  - `subscription` — 強制顯示 5H/7D 速率限制區塊（個人 Pro/Max 方案）
  - `quota` — 強制顯示 spend 區塊（企業版／配額制方案）
- 資料來源：Claude Code 自身使用的 usage 端點；腳本僅以本機 OAuth 憑證查詢**使用者自己的**用量，**不外傳至任何第三方**；查詢失敗時 spend 區塊顯示 `$--`，statusline 永不阻塞
- 結果快取 60 秒，背景刷新，不影響 statusline 渲染速度
- 新增 `core/fetch-usage.sh` 模組，負責呼叫 usage 端點、解析 JSON 回應並正規化輸出
- 文件：同步更新 `README.md`（英文）與 `docs/README.zh-TW.md`（繁中），加入 spend 區塊說明、`account_type` 設定說明及安全性聲明

## 2026-04-22

### 修正：rainbow 模式停用 block 後底色不再連貫
- 問題：rainbow 模式下每個 block 的底色（accent_1/2/3 三色循環）原本是 theme 檔案裡每個 block 各自寫死的 `pl_bg`，當使用者停用中間某個 block 時，剩下的顏色序列會跳色（例：藍紅黃藍紅黃 → 停用其一變藍紅黃紅黃）
- 修正：`statusline.sh` 的 rainbow assembly 改用**當前 enabled blocks 的位置 index 做 3 色循環**（`PL_CYCLE=(accent_1 accent_2 accent_3)`），不看 theme 個別 block 的 pl_bg。不管怎麼增減 blocks，顏色都會是 accent_1 → 2 → 3 → 1 → 2 → 3 … 連續循環
- 影響：theme 檔案中的 `pl_bg` 欄位在 rainbow 模式下不再被讀取（pl_fg 仍沿用作為前景色），theme 作者無需為每個 block 指定配色

## 2026-04-22

### 新增：iTerm2 tab tinting 整合（Step 8）
- 需求：把 claude-cli 的 tab 底色切換搬進 cyberpunk-statusline，讓顏色跟 theme palette 綁定並可在 wizard 自訂
- 新檔：
  - `tab-state.sh` — runtime 腳本，每次 hook 觸發時讀 config.json + theme 解析 palette → hex → RGB，送 iTerm2 OSC escape sequence
  - `_lib_tab_state.sh` — `_install_tab_state_hooks` / `_remove_tab_state_hooks` / `_detect_foreign_tab_state_hooks` 三個共用 helper，供 configure.sh 與 uninstall.sh source
  - `tests/test-tab-state.sh` / `tests/test-lib-tab-state.sh` — 單元測試
- 修改：
  - `configure.sh` — TOTAL_STEPS 7 → 8；新增 `step_tab_state`（非 iTerm2 auto-skip、Enable/Skip、4 × palette 選擇 + swatch preview）；`step_done` 寫 `tab_state` 欄位並依啟用轉態呼叫 install/remove
  - `uninstall.sh` — 偵測既有 tab-state hooks 與 symlink 後呼叫 `_remove_tab_state_hooks`
- 行為：
  - 換 theme 後下次 hook 觸發 tab 底色自動更新（script 每次重讀 config + theme）
  - config.json 沒 `tab_state` 欄位 / `enabled:false` → script 直接 exit 0 靜默
  - 非 iTerm2 終端機 wizard 自動跳過、script 自己也會靜默 exit
  - 偵測到其他來源（例如 claude-cli 那份）的 tab-state hooks 時印警告
- 相容性 notes：
  - 為了 macOS `/bin/bash` 3.2 相容，`tab-state.sh` 原本計畫用的 `declare -A DEFAULTS` 改為 `_default_palette()` case function；`configure.sh` 的 palette swatch 用平行 indexed array 取代 `local -A`

## 2026-04-20

### 新增：time block 支援 `MM/DD hh:mm` 日期＋時間格式
- 需求：status line 沒有顯示時間，希望加上 `MM/DD hh:mm` 二十四小時制
- 修正：
  - `statusline.sh` 的 `cfg_time_format` switch 新增兩個選項：
    - `24h-date` → `date +"%m/%d %H:%M"`（例：`04/20 16:23`）
    - `12h-date` → `date +"%m/%d %-I:%M %p"`（例：`04/20 4:23 PM`）
  - `configure.sh` 的 time-format wizard 步驟新增上述兩個選項與即時 preview
  - `config.json`：`blocks` 結尾補回 `"time"`，`time_format` 改為 `"24h-date"`

## 2026-04-18

### 新增：model block 顯示 effort 等級 + 縮短 1M context 顯示
- 問題：目前 status line model 無法看出 effort 是 low / medium / high；另外 `Opus 4.7 (1M context)` 字串太長，`context` 字樣多餘
- 修正：
  - 從 `~/.claude/settings.json` 讀取 `effortLevel`（low/medium/high），首字母大寫後併入括號一起顯示
  - 1M context 版本：`Opus 4.7 (1M context)` → `Opus 4.7 (1M.High)`（用 `.` 連接 1M 與 effort）
  - 非 1M 版本：`Sonnet 4.6` → `Sonnet 4.6 (High)`
- 備註：Claude Code 目前未將 effort 放入 stdin JSON payload（upstream issue #36187 / #38476），因此改從全域 settings 檔讀取，跟 `/effort` 指令實際寫入的位置一致

## 2026-04-17

### 修復：cost block 無法正確計算 Claude Opus 4.7 用量
- 問題根因：`_refresh_cost` 呼叫 ccusage 時加了 `--offline`，會使用 ccusage 內建（已過期）的定價表，最新版 18.0.10 尚未收錄 `claude-opus-4-7`，把該模型所有用量計為 $0，導致使用者升級 4.7 後金額停在舊值不再成長
- 修正：移除 `--offline`，讓 ccusage 從 LiteLLM 線上定價表抓取（該表更新較快，已有 4.7 的價錢）— 這個修法與使用者直接 `npx ccusage daily` 所看到的金額一致
- 同時保留本地 JSONL 解析作為 fallback（ccusage 不可用時才觸發），並加上 `message.id + requestId` dedupe 與 cache token 定價，避免重複計數與短報

## 2026-04-03

### 新增：preview.sh — 主題預覽與編輯工具
- `./preview.sh` — 列出所有主題的彩色預覽（並行生成）
- `./preview.sh tokyo-night` — 進入互動編輯模式：顯示色票 + 預覽 + 即時修改色彩
- 支援指令：`e <color> <#hex>` 編輯色彩、`a` 套用為當前主題、`q` 離開

### 新增：show_icons 設定 + cost block 移除 icon
- cost block 不再顯示 icon，直接顯示 $XX.XX
- 新增 show_icons 設定（true/false），控制所有 block 是否顯示 icon
- configure wizard Step 1 新增 icon 選擇子步驟（Yes/No + preview）
- config.json 新增 show_icons 欄位

### 文件：README 更新 — 新增 cost block、bar style、time format 說明
- 英文/繁中 README 同步更新
- 新增 Available Blocks 表格（含 cost 說明）
- 設定精靈步驟描述更新（bar style、time format）
- Prerequisites 新增 ccusage（optional）

### 新增：daily cost block — 透過 ccusage 顯示今日花費
- 新增 `cost` block，顯示今日所有 model 的 token 花費（美元）
- 透過 ccusage (`npx ccusage daily --jq`) 取得資料
- 使用背景快取機制（~/.cache/cyberpunk-statusline/daily-cost），每 5 分鐘更新
- 不阻塞 statusline 渲染，首次顯示 `--` 直到快取生成
- 所有 14 個主題 + custom-example 新增 cost symbol（nerd: 󰄉、unicode: $、ascii: [$]）
- configure wizard Step 2 新增 cost block 選項

### 優化：所有步驟的 preview 改為並行生成
- 所有 render_preview 呼叫改為背景 job 並行執行 + wait
- Step 3 spacing (3)、bar width (3)、bar style (6)
- Step 4 prompt style (2)、separator (5)、head (4)、tail (4)
- Step 5 time format (4)
- Step 6 theme (13)
- 原本逐一生成 N 個 preview 需要 N × ~25ms，並行後只需 ~25ms

### 優化：Step 6 theme 預覽改為並行生成
- 13 個主題的 preview 用背景 job 並行生成，大幅減少等待時間
- 生成完成後一次顯示所有主題 + 預覽

### 改善：Step 6 theme 選擇改為列出所有主題預覽
- 進入步驟時一次性預生成全部 13 個主題的 preview
- 每個主題名稱下方直接顯示彩色預覽，一目了然
- 上下鍵移動只切換 cursor highlight，不再每次重新渲染

### 優化：Step 2 blocks 上下鍵移動不再重新渲染 preview
- 原本每次按鍵都呼叫 draw_preview（跑 statusline.sh 子程序），導致 lag
- 改為 preview_dirty flag，只在 Space toggle 變更 block 時才重新渲染

### 修正：所有步驟的 preview 自動套用已選/預設 bar style
- render_preview 的 bar_filled/bar_empty 參數自動 fallback 到 sel_*/cur_* 值
- 首次安裝預設 bar style 為 Square ■□
- 所有步驟的 preview 不再需要手動傳 bar style 參數

### 調整：bar style 預設改為 Square、新增 Circle、Block 移到最後
- 順序：Square ■□（預設）→ Circle ●○（新增）→ Diamond → Star → Parallelogram → Medium Square → Rectangle → Hexagon → Block █░

### 新增：progress bar 樣式選擇步驟（Step 3c）
- configure wizard 新增 bar style 步驟（非 ultra-compact 時顯示）
- 8 種樣式：Default █░、Square ■□、Diamond ◆◇、Star ★☆、Parallelogram ▰▱、Medium Square ◼◻、Rectangle ▮▯、Hexagon ⬢⬡
- 自訂樣式固定 5 個字元寬（每個 = 20%），Default 沿用 bar_width 設定
- config.json 新增 `bar_filled`/`bar_empty` 欄位
- statusline.sh 支援讀取自訂 bar 字元，classic/rainbow 模式皆適用
- configure.sh: 預設 spacing 改為 ultra-compact

### 改善：configure wizard 預設 preview 改為 compact + rainbow
- 首次安裝（無 config）預設：spacing=compact、style=rainbow、separator=""
- 有 config 時從 config.json 讀取 style/head/tail（原本缺少這三個欄位的讀取）
- `_cur_style`/`_cur_head`/`_cur_tail` fallback 改為 rainbow/sharp/sharp

### 修正：configure wizard preview 位置改為緊跟內容下方
- Step 2 (blocks) 和 Step 6 (theme) 的 preview 原本固定在螢幕最底部
- 改為 `draw_preview --row N` 動態計算，放在選項列表正下方

### 改善：替換 context / rate_5h / rate_7d 的 Nerd Font icon
- context: 󰍛（晶片）→ 󰾆（記憶體條）— 更直覺表達「上下文容量」
- rate_5h: 󰕐（沙漏）→ 󰔟（時鐘）— 更像「短期速率」
- rate_7d: 󰔟（日曆鐘）→ 󰃰（日曆）— 更直覺表達「7 天配額」
- 全部 14 個主題 + custom-example 同步更新

### 文件：新增繁體中文版 README
- 新增 `docs/README.zh-TW.md` — 完整繁體中文版安裝與使用說明
- 主 README 加上語言切換連結（English / 繁體中文）

### 重構：捨棄 Claude plugin，改為 p10k 風格安裝
- **安裝方式：** `git clone` → `./install.sh`（自動設定 claude statusLine + 啟動 configure wizard）
- **目錄結構：** flatten `cyberpunk-statusline/` 子目錄到 repo root
- **新增：** `install.sh`（安裝）、`uninstall.sh`（反安裝）
- **移除：** `.claude-plugin/`、`hooks/`、`skills/`（Claude plugin 機制全部刪除）
- **路徑修正：** 所有腳本 `PLUGIN_DIR` → `SCRIPT_DIR`
- **configure.sh：** 刪除 plugin cache 同步邏輯
- **README：** 改為 git clone + install.sh 安裝說明

### 修正：Rainbow colored bg 相容性 + 移除多餘描述
- 加回 legacy separator (/) 的 rainbow 偵測，舊 config 不用改也能繼續 work
- Step 4 選項移除描述文字，只留 Classic / Rainbow 名稱（preview 已足夠說明）
- 程式碼註解 Powerline → Rainbow

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
