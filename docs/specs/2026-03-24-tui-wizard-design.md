# TUI Configure Wizard — 設計規格

## 概述

為 cyberpunk-statusline 建立一個類似 Powerlevel10k 的互動式 TUI 設定精靈。使用純 Bash 實作，零外部依賴。全螢幕逐步引導，搭配即時渲染預覽，讓使用者在選擇過程中直接看到最終效果。

## 核心設計決策

| 決策 | 選擇 | 理由 |
|------|------|------|
| 技術 | 純 Bash + ANSI escape codes | 零依賴，跟 p10k 一樣，任何有 bash 的環境都能跑 |
| 佈局 | 全螢幕逐步 | 每步清屏，沉浸感最強，不受終端歷史干擾 |
| 預覽 | 即時渲染（呼叫 statusline.sh） | 100% 真實效果，使用者看到什麼就得到什麼 |
| 步驟數 | 5 步 | 從原本 7 步精簡，合併符號測試+選擇、移除顏色自訂 |
| 區塊排序 | 不支援（固定順序） | 開發量大使用頻率低，進階使用者可手動編輯 config.json |

## 入口點

```bash
# 獨立腳本，放在 scripts/configure.sh
bash scripts/configure.sh
```

同時保留現有的 `/cyberpunk-statusline configure` skill 作為備用（對話式設定）。

## 5 步流程

### Step 1 — 符號測試 + 選擇

- 顯示三組符號：Nerd Font / Unicode / ASCII
- 使用者用 ↑↓ 鍵移動高亮，Enter 確認
- 選擇後直接決定 `symbol_set` 值
- 顯示名稱到 config 值的對應：

| 顯示名稱 | config.json 值 |
|----------|---------------|
| Nerd Font | `nerd` |
| Unicode | `unicode` |
| ASCII | `ascii` |

```
╔══════════════════════════════════════════╗
║   CYBERPUNK STATUSLINE CONFIGURATOR     ║
╚══════════════════════════════════════════╝

Step 1/5 — Which symbols display correctly?

   A) Nerd Font:  󰚩 󰍛  󰔟
 ❯ B) Unicode:   ⬡ ◈ ⚡ ⟳ ⌁ ⎇ ◷
   C) ASCII:     [M] [C] [!] [~] [D] [G] [T]

↑↓ move · Enter select · q quit
```

### Step 2 — 主題選擇（即時預覽）

- 列出 12 個內建主題，分 Cyberpunk / Classic 兩組（排除 `custom-example` 等目錄型主題）
- 移動游標時，底部呼叫 `statusline.sh` 即時渲染當前高亮主題的預覽
- 預覽使用假資料（model=Opus 4.6, context=58%, 5h=76%, 7d=33% 等）

```
Step 2/5 — Choose your theme:

── Cyberpunk ──
   Terminal Glitch — 駭客終端
 ❯ Neon Classic — Night City 霓虹
   Synthwave Sunset — 復古合成波
   Blade Runner Signal — 銀翼殺手控制室
   Retrowave Chrome — Tron 街機風
── Classic ──
   Dracula
   Tokyo Night
   ...

Preview:
 ⬡ Opus 4.6 │ ◈ CTX ██████░░░░ 58% │ ⚡ 5H ████████░░ 76% │ ⌁ ~/project │ ⎇ main │ ◷ 14:32

↑↓ move · Enter select · q quit
```

**即時渲染機制：**
- 產生一個臨時 config.json，設定當前高亮的主題
- 將假資料 JSON pipe 給 statusline.sh
- 用 `CONFIG_OVERRIDE` 環境變數指定臨時 config
- 將輸出渲染到預覽區域

### Step 3 — 區塊勾選

- 列出 7 個區塊，預設全部勾選
- ↑↓ 移動游標，空白鍵切換 ✔/✗
- Enter 確認
- 順序固定為：model, context, rate_5h, rate_7d, directory, git, time
- 底部即時預覽（只顯示勾選的區塊）

```
Step 3/5 — Which blocks to show? (Space to toggle)

 ✔ model       — Model name (e.g., Opus 4.6)
❯✔ context     — Context window usage %
 ✔ rate_5h     — 5-hour rate limit %
 ✔ rate_7d     — 7-day rate limit %
 ✗ directory   — Working directory
 ✔ git         — Git branch
 ✔ time        — Current time

Preview:
 ⬡ Opus 4.6 │ ◈ CTX ██████░░░░ 58% │ ⚡ 76% │ ⟳ 33% │ ⎇ main │ ◷ 14:32

↑↓ move · Space toggle · Enter confirm · q quit
```

### Step 4 — 間距模式（即時預覽）

- 三個選項：Normal / Compact / Ultra Compact
- 移動游標時即時預覽差異

```
Step 4/5 — Spacing mode:

 ❯ Normal        — symbol + label + bar + %
   Compact       — symbol + bar + %
   Ultra Compact — symbol + % only

Preview:
 ⬡ Opus 4.6 │ ◈ CTX ██████░░░░ 58% │ ⚡ 5H ████████░░ 76%

↑↓ move · Enter select · q quit
```

### Step 5 — 分隔符（即時預覽）

- 五個選項：Pipe │ / Slash / / Dot · / Space / Arrow ›
- 移動游標時即時預覽差異

```
Step 5/5 — Separator style:

 ❯ Pipe  │
   Slash /
   Dot   ·
   Space
   Arrow ›

Preview:
 ⬡ Opus 4.6 │ ◈ CTX ██████░░░░ 58% │ ⚡ 5H ████████░░ 76%

↑↓ move · Enter select · q quit
```

### 完成畫面

```
╔══════════════════════════════════════════╗
║   ✔ Configuration saved!                ║
╚══════════════════════════════════════════╝

Theme:     Neon Classic
Symbols:   Unicode
Blocks:    6/7 enabled
Spacing:   Normal
Separator: Pipe │

 ⬡ Opus 4.6 │ ◈ CTX ██████░░░░ 58% │ ⚡ 5H ████████░░ 76% │ ...

Your status line will update on the next refresh.
Run 'cyberpunk-statusline configure' anytime to reconfigure.
```

## 技術架構

### 檔案結構

```
scripts/
├── configure.sh      # TUI wizard 主腳本（新增）
└── statusline.sh     # 現有渲染引擎（不修改）
```

### Bash TUI 實作要點

**終端控制：**
- `tput smcup` / `tput rmcup` — 進入/退出 alternate screen（清屏不影響歷史）
- `tput civis` / `tput cnorm` — 隱藏/顯示游標
- `tput cup $row $col` — 游標定位
- `tput clear` — 清屏
- trap EXIT 確保恢復終端狀態

**鍵盤輸入：**
- `read -rsn1` 讀取單個按鍵
- 偵測 escape sequence（`\e[A` = ↑, `\e[B` = ↓）
- Enter = 確認, Space = 切換, q = 退出

**即時預覽渲染：**
```bash
# 產生臨時 config，覆蓋主題設定
tmp_config=$(mktemp)
jq --arg theme "$selected_theme" '.theme = $theme' config.json > "$tmp_config"

# 呼叫 statusline.sh 渲染預覽
preview=$(CONFIG_OVERRIDE="$tmp_config" bash scripts/statusline.sh <<< "$SAMPLE_DATA")

# 輸出到預覽區域
tput cup $PREVIEW_ROW 0
echo -e "$preview"
```

**畫面更新：**
- 只重繪變動的區域（游標位置、預覽），不要每次按鍵都清屏
- 用 `tput cup` 定位到變動行，覆寫內容
- 確保沒有閃爍感

### 假資料（預覽用）

```json
{
  "session_id": "preview",
  "model": { "id": "claude-opus-4-6", "display_name": "Opus 4.6 (1M context)" },
  "workspace": { "current_dir": "/Users/you/project" },
  "context_window": { "used_percentage": 58, "remaining_percentage": 42 },
  "rate_limits": {
    "five_hour": { "used_percentage": 76, "resets_at": 9999999999 },
    "seven_day": { "used_percentage": 33, "resets_at": 9999999999 }
  }
}
```

選擇有代表性的數值：58%（正常）、76%（接近警告）、33%（低），讓使用者能看到不同顏色閾值的效果。

### 相依性

- **jq**：statusline.sh 本身就需要 jq，所以 wizard 也必須有 jq。啟動時檢查，未安裝則顯示錯誤訊息並退出
- **bash 3.2+**：不使用 associative arrays，確保 macOS 預設 bash 也能執行
- **statusline.sh**：現有渲染引擎，透過 `CONFIG_OVERRIDE` 環境變數傳入臨時設定
- **tput**：終端控制，所有 Unix 系統都有

### 啟動檢查

```bash
# 1. 確認是互動式終端
[ -t 0 ] || { echo "Error: configure requires an interactive terminal"; exit 1; }

# 2. 確認 jq 已安裝
command -v jq &>/dev/null || { echo "Error: jq is required. Install with: brew install jq"; exit 1; }

# 3. 確認終端大小足夠（最小 60x20）
cols=$(tput cols); lines=$(tput lines)
(( cols >= 60 && lines >= 20 )) || { echo "Error: terminal too small (need 60x20, got ${cols}x${lines})"; exit 1; }
```

### 導航

- ↑↓ 移動游標
- Enter 確認
- Space 切換（僅 Step 3 區塊勾選）
- **b 返回上一步**（Step 1 不可返回）
- q 退出

### 既有設定預載

啟動時讀取現有 config.json，將各步驟的游標預設到使用者目前的選擇。例如使用者目前是 `terminal-glitch` 主題，Step 2 的游標就預設停在 Terminal Glitch。

### 最終設定寫入

使用 heredoc 寫入，不依賴 jq：

```bash
cat > "$CONFIG_PATH" <<EOF
{
  "theme": "$selected_theme",
  "symbol_set": "$selected_symbols",
  "spacing": "$selected_spacing",
  "separator": "$selected_separator",
  "blocks": [$blocks_json],
  "bar_width": 10
}
EOF
```

`$blocks_json` 由勾選的區塊產生，例如 `"model", "context", "rate_5h"`。

### 輸出

寫入 `config.json` 到 plugin 目錄，格式與現有相同：

```json
{
  "theme": "neon-classic",
  "symbol_set": "unicode",
  "spacing": "normal",
  "separator": "│",
  "blocks": ["model", "context", "rate_5h", "rate_7d", "git", "time"],
  "bar_width": 10
}
```

## 不在範圍內

- 顏色自訂（手動編輯主題 JSON）
- 區塊排序（手動編輯 config.json）
- 自動偵測 Nerd Font（需要使用者目視確認）
- Windows 支援（Claude Code 主要在 macOS/Linux）
