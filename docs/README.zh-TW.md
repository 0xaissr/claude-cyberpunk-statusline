# cyberpunk-statusline

[English](../README.md) | [繁體中文](README.zh-TW.md)

可自訂主題的賽博龐克風格狀態列，支援 Claude Code 與 Codex，附帶 p10k 風格的設定流程。

顯示模型名稱、上下文用量、速率限制、每日花費、目錄路徑、Git 分支與時間 — 全部以真彩色主題呈現在終端機中。

![overview](overview.png)

## 環境需求

- **Claude Code** CLI 或桌面版 — Claude 安裝器需要
- **Codex** CLI（選用）— Codex 安裝器需要
- **jq** — `brew install jq`（macOS）/ `apt install jq`（Linux）
- **Nerd Font**（選用，建議安裝）— 用於圖示顯示。[下載連結](https://www.nerdfonts.com/)
- **ccusage**（選用）— 更精確的每日花費統計。`npm i -g ccusage`

patched Codex 模式（`./install-codex.sh --patched`）還額外需要 **git** 與 **Rust
toolchain**（`cargo`），因為它會從原始碼編譯 Codex — 詳見
[安裝 Codex](#3-安裝-codex選用)。

## 安裝

### 1. 複製倉庫

```bash
git clone https://github.com/0xaissr/claude-cyberpunk-statusline.git ~/claude-cyberpunk-statusline
```

### 2. 安裝 Claude Code

```bash
cd ~/claude-cyberpunk-statusline && ./install-claude.sh
```

安裝程式會：
- 檢查環境需求（jq）
- 設定 Claude Code 的 statusLine 設定
- 啟動設定精靈（首次安裝時）

### 3. 安裝 Codex（選用）

Codex 使用獨立安裝器，因此可以和 Claude 使用不同主題：

```bash
cd ~/claude-cyberpunk-statusline && ./install-codex.sh
```

它會引導選擇 Codex 主題，並設定 Codex 官方支援的內建 `tui.status_line` items。預設不會編譯 patched Codex binary。官方 Codex 目前不支援 command-rendered cyberpunk status line，所以這個模式給你的是 Codex 自己的狀態項目，不是 cyberpunk footer。

可用選項：`--theme THEME`、`--official` / `--patched`、`--alias` / `--no-alias`、`--dry-run`。

#### Patched binary（完整 cyberpunk footer）

```bash
cd ~/claude-cyberpunk-statusline && ./install-codex.sh --patched
```

這是實驗性質、僅限 Codex 的路線。執行前先了解它會做什麼：

- **需要 `git` 與 Rust toolchain（`cargo`）。** 腳本沒有前置檢查，缺少 `cargo` 會在執行到一半時以 `command not found` 失敗。
- 會 clone `rust-v0.142.5` 的 Codex 原始碼、套用
  `adapters/codex/patches/status-line-command.patch`，然後跑一次完整的
  `cargo build --release`。首次編譯很久，並會佔用數 GB 磁碟空間。
- 產物安裝為 **`~/.local/bin/codex-cyberpunk`**，原本的 `codex` binary 不會被覆蓋。
- 會詢問是否把 `alias codex="$HOME/.local/bin/codex-cyberpunk"` 加進 `~/.zshrc`
  （僅限 zsh）。用 `--alias` 強制加入，用 `--no-alias` 跳過。

細節請見 [docs/codex-patched-footer.md](codex-patched-footer.md)。

### 4. 重新啟動

重新啟動 Claude Code（或 Codex）即可看到狀態列。

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
| model | 模型名稱（例如 Opus 5） |
| context | 上下文視窗用量 % |
| session | 本次 session 的累計 token 與花費（例如 `646K $1.89`） |
| last_chat | 最後一次 API 呼叫的 token 與花費（例如 `163K $0.34`） |
| rate_5h | 5 小時速率限制 % |
| rate_7d | 7 天速率限制 % |
| spend | 企業版／配額制帳號的本月 spend 用量（自動取代速率限制區塊） |
| credit | 配額制帳號的一次性 Claude Code／Cowork credit 用量（顯示於 spend 左側，存在時才出現） |
| cost | 今日跨 session 花費 |
| burn | 單日消耗速率，格式 `實際 〈關係符〉 健康`（例 `87.6 > 0.8`）——目前每日速度（%/day）對比「剛好撐到重置」的每日速度。關係符（`>`/`<`/`=`）直接表達兩者關係；`>` 代表會提早用完並轉為告警色。歷史資料不足時顯示 `--`。資料來自每次 render 的使用率歷史記錄（`~/.cache/cyberpunk-statusline/usage-history.jsonl`，依 (metric, 數值) 去重、保留 30 天；單點離群下降會被忽略，避免把瞬間的異常讀數誤判為重置）。初期因資料少，數字會偏高且跳動，隨資料累積會趨於穩定。 |
| directory | 工作目錄 |
| git | Git 分支 |
| time | 目前時間 |

**session** 與 **last_chat** 兩個區塊預設放在第二列，token 的計算方式相同：

```
input_tokens + cache_creation_input_tokens + cache_read_input_tokens + output_tokens
```

`cache_read_input_tokens` **有計入**。每一輪都會重讀整個 context，所以這個數字大致隨
「輪數 × context 大小」成長 —— 它回答的是「這個 session 累計跑了多少計費 token」，而不
是「我現在佔用多少 context」（後者由 `context` 區塊負責）。快取讀取約佔實際花費的一半，
若把它排除，token 數與金額就無法互相印證。

金額依訊息自身的 `model` 欄位計價，session 中途換模型也能算對。cache write 依
`usage.cache_creation` 的 TTL 分項計價——5 分鐘是 input 單價的 1.25 倍、1 小時是 2 倍。

單價每天自動更新一次。`core/fetch-pricing.sh` 會抓 LiteLLM 維護的價格表（`ccusage`
讀的也是同一份，所以兩條成本路徑不會打架），快取在
`~/.cache/cyberpunk-statusline/pricing.json`。Anthropic 沒有提供機器可讀的價格來源
——`/v1/models` 只回傳能力不含單價——所以第三方表是唯一選擇。下載在背景執行、渲染
路徑只讀那份小快取，網路慢或斷線都不會卡住提示字元；任何失敗都會退回內建的家族分價表
（Fable / Opus / Sonnet / Haiku）。另有一個測試拿內建表跟上游對帳，避免這個 fallback
悄悄過期。

這個金額是**等值 API 成本**。Pro／Max 訂閱制並非按 token 計費，所以它是用量的量尺，
不是帳單。

以 `blocks` 與 `blocks_line2` 設定各列要顯示哪些區塊：

```json
"blocks":       ["model", "context", "rate_5h", "rate_7d", "cost"],
"blocks_line2": ["session", "last_chat"]
```

`blocks_line2` 為空或缺漏就不顯示第二列。從舊版升級：`blocks` 中的 `"tokens"` 會被視為
`"session"`，但要重跑 `configure.sh` 才會有第二列。由於現在會把 cache read 算進去，
你原本習慣看到的數字會大幅跳升——常常是十倍以上（實測有一份 transcript 從 164,018
跳到 6,182,840，約 38 倍）——這是預期行為，不是 bug。這個功能已經不再讀寫舊版
`~/.claude/hooks/show-turn-usage.sh` 這個 Stop hook 產生的快取檔，如果你還裝著這個
hook，可以直接刪掉。

在 Codex 上 `session` 的行為不同：它會留在第一列（Codex 的 status line 本來就只有一
列，沒有第二列可以搬過去）、只顯示 token 數不顯示 `$` 金額（Codex 沒有 session 層級
的花費來源），而且 `last_chat` 在 Codex 上完全不存在。

數字格式為 `842` / `840K` / `12.4M`，一律無條件捨去，因此不會出現跨單位溢位的怪值。數值取自 session transcript，並以 transcript 的 mtime 作為快取失效依據，所以閒置時重新 render 完全不耗成本。找不到 transcript 時顯示 `--`。

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

帳號**無此 credit 時自動隱藏**；當 credit **用光（達 100%）時也會隱藏**，此時只保留 enterprise spend limit 區塊，burn 區塊亦改為追蹤 spend。皆無需任何設定。此區塊僅適用於配額制帳號，訂閱制帳號不受影響。

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

### Claude Code

```bash
cd ~/claude-cyberpunk-statusline && ./uninstall.sh
```

這只會清掉 Claude Code 的 `statusLine` 設定，**不會**動到任何 Codex 的東西。

### Codex

```bash
cd ~/claude-cyberpunk-statusline && ./adapters/codex/uninstall-patched.sh
```

這會刪除 `~/.local/bin/codex-cyberpunk`，並移除 `~/.codex/config.toml` 裡的
`status_line_command` — 但僅限於該設定指向本專案時。加上 `--dry-run` 可以先看它會動到什麼。

有兩樣東西它不會還原，如果你有用到請自行手動移除：

- official 模式寫進 `~/.codex/config.toml` 的 `tui.status_line` items
- `~/.zshrc` 裡的 `alias codex="$HOME/.local/bin/codex-cyberpunk"`

兩邊都解除後，就可以安全刪除 clone 下來的目錄。

## 授權條款

MIT
