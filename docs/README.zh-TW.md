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
| spend | 企業版／配額制帳號的本月 spend 用量（自動取代速率限制區塊） |
| credit | 配額制帳號的一次性 Claude Code／Cowork credit 用量（顯示於 spend 左側，存在時才出現） |
| cost | 今日跨 session 花費 |
| directory | 工作目錄 |
| git | Git 分支 |
| time | 目前時間 |

**cost 區塊**會顯示今日所有 Claude 模型與 session 的總花費。若有安裝 [ccusage](https://github.com/ryoppippi/ccusage) 會使用其精確統計，否則自動以內建 JSONL 計算。資料每 5 分鐘在背景更新快取。

#### 企業版／配額制帳號：Spend 區塊

當 statusline 偵測到**企業版或配額制 Claude 帳號**（即無個人速率限制）時，`rate_5h` 與 `rate_7d` 區塊會自動替換為 **spend 區塊**，顯示本月用量：

```
$122/$500 24% ↻21d0h
```

- **`$used/$limit`** — 本月已用金額／配額上限
- **`pct%`** — 配額使用百分比
- **`↻…`** — 距配額重置（下月 1 日）的倒數

若 `account_type` 強制設為 `quota` 但無法取得用量資料，spend 區塊顯示 `$--`；在預設的 `auto` 模式下，取得失敗會被視為未知帳號而保留速率限制區塊。兩種情況下 statusline 都永不阻塞。

資料取自 Claude Code 自身使用的 usage 端點，腳本僅讀取本機 OAuth 憑證來查詢**使用者自己的**用量，**不會外傳至任何第三方**。結果快取 60 秒並在背景刷新。

#### 一次性 Credit 區塊

配額制帳號若擁有**一次性 Claude Code／Cowork credit**（`cinder_cove` 欄位 — 即網頁介面中顯示的「Claude Code and Cowork credit / Included credit」），會在 **spend 區塊左側**顯示 `CR` 區塊：

```
CR ████░ 8% ↻89d  $122/$500 ████░ 24% ↻21d
```

- **`pct%`** — 一次性 credit 已用百分比（此 credit 類型僅提供百分比，**不提供金額**）
- **進度條** — 與 `rate_5h` / `rate_7d` 相同樣式
- **`↻…`** — 距 credit 到期的倒數

帳號**無此 credit 時自動隱藏**，無需任何設定。此區塊僅適用於配額制帳號，訂閱制帳號不受影響。

#### `account_type` 設定

你可以在 `config.json` 中以 `account_type` 選項覆蓋自動偵測行為：

| 值 | 行為 |
|---|---|
| `auto`（預設） | 自動偵測帳號類型；企業版／配額制帳號顯示 spend 區塊，否則顯示速率限制區塊 |
| `subscription` | 強制顯示 `rate_5h` / `rate_7d` 區塊（個人 Pro/Max 方案） |
| `quota` | 強制顯示 spend 區塊（企業版／配額制方案） |

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
