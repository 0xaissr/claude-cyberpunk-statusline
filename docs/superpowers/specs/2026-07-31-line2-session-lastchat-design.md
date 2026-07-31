# 第二列重構：session 與 last_chat 兩欄

日期：2026-07-31

## 背景

目前狀態列的 token / 花費資訊散在兩處，語意不一致：

- **第一列** 有一個 `tokens` 區塊，顯示本次 session 累計 token，但**刻意排除 cache_read**，且沒有金額。
- **第二列** 是硬編碼的一行 `Last Chat cache:161,065 in:622 out:1,212 $0.3442`，四個數字擠在一起、無法開關、無法調色。它的資料來自 repo **外部**的 `~/.claude/hooks/show-turn-usage.sh`（Stop hook），該 hook 把單價寫死成 Opus。

使用者要的是：把 session 移到第二列並補上金額，把 last chat 簡化成同樣的「總 token + 金額」，兩者分成不同顏色的獨立欄位，並且能在 configure 裡開關。

## 目標

1. 第二列由兩個獨立區塊組成：`session` 與 `last_chat`，各自有顏色與符號。
2. 兩者格式統一為 `<符號> <總token> $<金額>`。
3. 第一列不再有 `tokens` 區塊。
4. `configure.sh` 能分別開關第一列與第二列的區塊。

## 非目標

- **不**為 Codex adapter 補上 last_chat 或 session 金額。Codex 沒有 last_chat 的資料來源，也沒有現成的 GPT 分模型價目表。Codex 的 session 區塊優雅降級成只顯示 token。
- **不**改動第一列既有的 model / context / rate_5h / rate_7d / cost 區塊。

## 決策紀錄

### token 一律含 cache_read

`session` 與 `last_chat` 的「總 token」都是 `input + cache_creation + cache_read + output`。

之所以要含 cache_read，是因為它佔實際花費的一半左右。以撰寫本文件時的 session 為例：

| 項目 | token | 單價 (Opus) | 金額 |
|---|---|---|---|
| input | 25 | $15/M | $0.00 |
| cache_creation | 36,947 | $18.75/M | $0.69 |
| cache_read | 606,102 | $1.50/M | $0.91 |
| output | 3,877 | $75/M | $0.29 |
| | | | **≈ $1.89** |

金額必須含 cache_read，所以 token 也含，兩個數字才互相印證得起來。

代價是這個數字會隨輪數近似平方成長（每輪重讀當時的整個 context）。上例中當前 context 只有 63K，但 17 輪累加的 cache_read 已達 606K。這是刻意接受的：此欄位的語意是「這個 session 累計跑了多少計費 token」，不是「當前佔用多少 context」（後者由第一列的 `context` 區塊負責）。

此決策**推翻**了 `docs/superpowers/specs/2026-07-30-session-tokens-block-design.md` 中「排除 cache_read」的設計。

### 第二列採用獨立的 blocks 陣列

`config.json` 新增 `blocks_line2`，結構與 `blocks` 相同，重用既有的 rainbow / classic 渲染管線。開關即是從陣列增刪，順序也可調，未來要往第二列加別的區塊不需改架構。

被否決的替代方案：

- 兩個布林旗標 `show_session` / `show_last_chat` — 順序寫死，加區塊要再加旗標，且無法共用渲染程式碼。
- 單一 `blocks` 陣列加換行標記 — configure 的選單 UI 要處理分行符號，難做且容易讓使用者困惑。

### last_chat 改由 statusline 直接讀 transcript

不再依賴 repo 外部的 `~/.claude/hooks/show-turn-usage.sh`。理由：

- repo 自足，少一個安裝步驟（目前使用者得自行安裝該 hook 才會有第二列）。
- 定價正確：該 hook 硬編 Opus 單價，切到 Sonnet 會多算約 5 倍。
- 與 session 同源，兩欄數字保證用同一套邏輯算出。

statusline 已經為了 session 而掃 transcript，同一次掃描順便取出最後一筆 assistant 訊息即可，不增加 I/O。

舊 hook 留在原地無害，statusline 只是不再讀它的快取檔 `turn-usage-<md5>.txt`。

## 設計

### 顯示格式

```
列1  ⬡ Opus 5 (1M.High)  ◈ 18%  ⏳ 29% ↻4h14m  ⏰ 15% ↻6d6h  $ $89.20
列2  ⇅ 646K $1.89   ⌯ 163K $0.3442
     └─ session ─┘   └─ last_chat ─┘
```

token 沿用既有的 `fmt_tokens`（無條件捨去，`646K` / `45.2M`）。

金額新增 `fmt_price`：`≥ 1` 用兩位小數（`$1.89`），`< 1` 用四位小數（`$0.3442`）。小額若也用兩位小數會全部塌成 `$0.00`。

### 資料層

單一函式一次掃 transcript，輸出 session 與 last_chat 兩組數字：

- **去重**：沿用既有的 `message.id|requestId` 分組，重試的請求不重複計算。
- **session**：所有去重後訊息的四類 token 相加；金額用既有的 `price($m)` jq 函式按 `message.model` 分價（`startswith` 比對，新 model ID 自動繼承家族定價）。
- **last_chat**：去重後的最後一筆訊息，同樣算出四類 token 總和與金額。

快取沿用現有的 mtime-keyed 檔案 `$COST_CACHE_DIR/session-tokens-<session-id>`，格式由 `mtime|total` 擴充為：

```
mtime|session_tokens|session_cost|last_tokens|last_cost
```

讀取時若欄位數不符（舊格式殘留），視為 cache miss 重算。

### 渲染層

新增與既有區塊同形的四個函式：

- `block_text_session` / `render_block_session`
- `block_text_last_chat` / `render_block_last_chat`

並在 rainbow 與 classic 兩處 dispatch 的 `case` 加上對應分支。

主流程改為：讀 `blocks` 組出第一列、讀 `blocks_line2` 組出第二列，兩列走同一段組裝程式碼（抽成接受區塊陣列的函式）。`blocks_line2` 為空陣列或整個欄位缺漏時，都不輸出第二列，也不輸出多餘空行。

移除硬編碼的 `turn_line` 區段（statusline.sh:828-847）。

### 設定

`config.json` 預設值：

```jsonc
"blocks":       ["model", "context", "rate_5h", "rate_7d", "cost"],
"blocks_line2": ["session", "last_chat"]
```

**向後相容**：舊 config 的 `blocks` 陣列若含 `"tokens"`，在讀取時映射為 `"session"`。既有使用者升級後第一列的 tokens 區塊會直接變成含金額的 session 區塊，不會消失或報錯。

舊 config 沒有 `blocks_line2` 欄位，因此升級後預設不顯示第二列 —— 原本靠外部 hook 顯示的 Last Chat 會消失，需重跑 `configure.sh` 才會取得新版第二列。這是刻意的：若對缺漏欄位補上預設值 `["session", "last_chat"]`，第一列映射而來的 session 會與第二列的 session 重複顯示。

### 主題

14 個 theme 檔各需補上：

- `blocks.session`、`blocks.last_chat` 的 `color` / `bg` / `pl_bg` / `pl_fg`。建議 `session` → `accent_1`、`last_chat` → `accent_2`，兩欄在第二列形成明顯色差。
- `symbols.{nerd,unicode,ascii}.session` 與 `.last_chat`。`session` 沿用現有 `tokens` 的符號值；`last_chat` 新增（nerd `󰭹` / unicode `⌯` / ascii `[L]`）。

保留各 theme 既有的 `symbols.*.tokens` 與 `blocks.tokens`，作為向後相容映射的後備。

### configure.sh

`step_blocks` 拆成兩段選單：第一列可選 `model / context / rate_5h / rate_7d / cost / directory / git / time`，第二列可選 `session / last_chat`。選取結果分別存入 `sel_blocks` 與 `sel_blocks_line2`。

`render_preview` 目前用第 5 個位置參數接 `blocks_csv`，且有十餘個呼叫點。第二列**不再加位置參數**，改由 `render_preview` 讀全域的 `sel_blocks_line2` / `cur_blocks_line2`（與它已經在讀 `sel_symbols` 的做法一致），避免全部呼叫點都要改。

預覽需要餵假資料：現有的 `SESSION_TOKENS_OVERRIDE` 之外，新增 `SESSION_COST_OVERRIDE`、`LAST_CHAT_TOKENS_OVERRIDE`、`LAST_CHAT_COST_OVERRIDE`，全部短路掉 transcript 解析。

### Codex adapter

`adapters/codex/statusline.sh` 目前餵 `SESSION_TOKENS_OVERRIDE` 給主 statusline。改動：

- 其預設 config 的 `blocks` 移除 `tokens`，`blocks_line2` 設為 `["session"]`。
- 不設 `SESSION_COST_OVERRIDE`；`block_text_session` 在金額為空時只輸出 token，不輸出 `$`。
- `blocks_line2` 不含 `last_chat`，該欄位不會出現。
- `codex_session_tokens` 目前刻意扣除 `cached_input_tokens`，改為**不扣除**，與 Claude 側「含快取讀取」的定義一致。

## 測試

- `fmt_price` 的分界：`0.9999` → `$0.9999`、`1.0` → `$1.00`、`0` → `$0.0000`。
- transcript 解析：多輪、含重試（同 message.id 不同 requestId）、混合 model（Opus + Sonnet 各段用各自單價）、空檔、單筆。
- 快取：mtime 未變讀快取、mtime 變更重算、舊格式（兩欄位）視為 miss。
- 渲染：rainbow 與 classic 兩種樣式下第二列的頭尾 glyph 與色彩轉場正確；`blocks_line2` 為空時不輸出第二列也不輸出多餘空行。
- 向後相容：`blocks` 含 `"tokens"` 的舊 config 能正常渲染成 session 區塊。
- 主題完整性：14 個 theme 都有 `session` / `last_chat` 的顏色與三組符號。

## 文件

README.md 與 docs/README.zh-TW.md 需同步更新區塊清單與設定範例（專案規約要求兩版本同步）。
