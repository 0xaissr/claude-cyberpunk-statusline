# cyberpunk-statusline

可自訂主題的賽博龐克風格狀態列，專為 Claude Code 打造，附帶 p10k 風格的設定精靈。

顯示模型名稱、上下文用量、速率限制、每日花費、目錄路徑、Git 分支與時間 — 全部以真彩色主題呈現在終端機中。

![overview](overview.png)

## 環境需求

- **Claude Code** CLI 或桌面版
- **jq** — `brew install jq`（macOS）/ `apt install jq`（Linux）
- **Nerd Font**（選用，建議安裝）— 用於圖示顯示。[下載連結](https://www.nerdfonts.com/)
- **ccusage**（選用）— 更精確的每日花費統計。`npm i -g ccusage`

## 安裝

### 1. 複製倉庫

```bash
git clone https://github.com/0xaissr/claude-cyberpunk-statusline.git ~/claude-cyberpunk-statusline
```

### 2. 執行安裝

```bash
cd ~/claude-cyberpunk-statusline && ./install.sh
```

安裝程式會：
- 檢查環境需求（jq）
- 設定 Claude Code 的 statusLine 設定
- 啟動設定精靈（首次安裝時）

### 3. 重新啟動

重新啟動 Claude Code 即可看到狀態列。

### 重新設定

```bash
cd ~/claude-cyberpunk-statusline && ./configure.sh
```

設定精靈會引導你完成以下設定：

1. **字型偵測** — Nerd Font / Unicode / ASCII
2. **區塊選擇** — 選擇要顯示的資訊區塊
3. **間距與進度條樣式** — 超緊湊、緊湊、一般 + 進度條形狀（■□、●○、◆◇ 等）
4. **提示風格** — 彩虹風格（色彩背景）或經典風格（分隔線）
5. **分隔線 / 頭尾形狀** — 自訂區段外觀
6. **時間格式** — 24 小時制 / 12 小時制 / 無秒數
7. **主題** — 從 13 種內建主題中選擇，支援即時預覽

### 可用區塊

| 區塊 | 說明 |
|---|---|
| model | 模型名稱（例如 Opus 4.6） |
| context | 上下文視窗用量 % |
| rate_5h | 5 小時速率限制 % |
| rate_7d | 7 天速率限制 % |
| cost | 今日跨 session 花費 |
| directory | 工作目錄 |
| git | Git 分支 |
| time | 目前時間 |

**cost 區塊**會顯示今日所有 Claude 模型與 session 的總花費。若有安裝 [ccusage](https://github.com/ryoppippi/ccusage) 會使用其精確統計，否則自動以內建 JSONL 計算。資料每 5 分鐘在背景更新快取。

### iTerm2 Tab Tinting（選用）

cyberpunk-statusline 可依 Claude Code session 狀態（running / waiting / idle /
error）改變 iTerm2 tab 底色。顏色從當前 theme palette 取得，換 theme 自動重染。

在 configure wizard 的 Step 8 啟用 — 只有 `$TERM_PROGRAM` 是 `iTerm.app` 時才會
出現。選擇 Enable 會在 `~/.claude/settings.json` 寫入 6 個 hooks
（SessionStart / UserPromptSubmit / PreToolUse / Notification / Stop / SessionEnd）
並在 `~/.claude/scripts/tab-state.sh` 建 symlink。所有修改前會先產生
settings.json 的時間戳備份。

| State   | 預設 palette | 觸發時機                     |
|---------|--------------|------------------------------|
| running | accent_1     | UserPromptSubmit、PreToolUse |
| waiting | warning      | Notification（附 attention） |
| idle    | accent_3     | SessionStart、Stop           |
| error   | alert        | （保留欄位，目前不自動觸發） |

**Plugin 使用者：** 升級 cyberpunk-statusline 版本後請重跑
`/cyberpunk-statusline configure`，讓 symlink 指向新版 plugin cache 目錄。

要停用時重跑 configure 並在 Step 8 選 Skip — hooks 會自動移除。
`./uninstall.sh` 也會一併清除。

### 預覽與編輯主題

```bash
# 預覽所有主題
cd ~/claude-cyberpunk-statusline && ./configure-theme.sh

# 編輯特定主題（互動式色彩編輯器 + 即時預覽）
cd ~/claude-cyberpunk-statusline && ./configure-theme.sh tokyo-night
```

### 更新

```bash
cd ~/claude-cyberpunk-statusline && git pull
```

## 主題一覽

| 主題 | |
|---|---|
| blade-runner | catppuccin-mocha |
| dracula | gruvbox-dark |
| midnight-phantom | neon-classic |
| nord | one-dark |
| retrowave-chrome | rose-pine |
| synthwave-sunset | terminal-glitch |
| tokyo-night | |

你也可以建立自訂主題 — 參考 `themes/custom-example/` 目錄。

## 解除安裝

```bash
cd ~/claude-cyberpunk-statusline && ./uninstall.sh
```

## 授權條款

MIT
