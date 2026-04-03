# cyberpunk-statusline

可自訂主題的賽博龐克風格狀態列，專為 Claude Code 打造，附帶 p10k 風格的設定精靈。

顯示模型名稱、上下文用量、速率限制、目錄路徑、Git 分支與時間 — 全部以真彩色主題呈現在終端機中。

## 環境需求

- **Claude Code** CLI 或桌面版
- **jq** — `brew install jq`（macOS）/ `apt install jq`（Linux）
- **Nerd Font**（選用，建議安裝）— 用於圖示顯示。[下載連結](https://www.nerdfonts.com/)

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
3. **間距** — 超緊湊、緊湊、一般
4. **提示風格** — 經典風格（分隔線）或彩虹風格（色彩背景）
5. **分隔線 / 頭尾形狀** — 自訂區段外觀
6. **進度條寬度** — 調整上下文/速率區塊的進度條大小
7. **主題** — 從 13 種內建主題中選擇，支援即時預覽

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
