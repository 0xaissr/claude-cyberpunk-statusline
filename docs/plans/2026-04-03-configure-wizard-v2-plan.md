# Configure Wizard v2 計畫：借鑑 Powerlevel10k 設定體驗

## 設計哲學

借鑑 p10k 核心原則：**讓使用者看到實際渲染結果來做決定**，而非讓使用者猜測技術選項的含義。

## 目前流程 vs 新流程

### 目前（v1）：5 步，方向鍵導覽

1. Symbol Set（直接選 nerd/unicode/ascii）
2. Blocks（勾選要顯示的區塊）
3. Spacing（normal/compact/ultra-compact）
4. Separator（│ / · 空格 ›）
5. Theme（從 13 個主題中選）

### 新設計（v2）：7 步，混合輸入模式

1. **字型能力偵測**（y/n 問答，自動推斷 symbol set）
2. **Blocks**（數字選擇 + 嵌入式 preview，使用預設主題）
3. **Spacing + bar_width**（數字選擇 + 嵌入式 preview）
4. **Separator**（數字選擇 + 嵌入式 preview）
5. **Time format**（條件觸發：僅當 time block 啟用）
6. **Theme**（方向鍵導覽 + 即時 preview，最後的「大揭曉」）
7. **確認儲存**

**Preview 策略：** Step 2-5 使用預設主題 `terminal-glitch` 渲染嵌入式 preview，Step 6 才讓使用者挑選主題並即時切換 preview，這樣每個步驟都有完整 preview 而不會因 13 個主題而爆版面。

## 輸入模式設計（混合方案）

### y/n 模式（Step 1 字型偵測）
```
    Does this look like a hexagon icon?

              ---> ⬡ <---

  (y)  Yes.
  (n)  No.

  (r)  Restart from the beginning.
  (q)  Quit and do nothing.

  Choice [ynrq]: _
```

### 數字選擇 + 嵌入式 preview（Step 2-5）
```
  Step 3/7 — Spacing mode:

  (1)  Normal — symbol + label + bar + %
       ⬡ Opus 4.6 │ ◈ CTX ██████░░░░ 58% │ ⚡ 5H ████████░░ 76%

  (2)  Compact — symbol + bar + %
       ⬡ Opus 4.6 │ ◈ ██████░░░░ 58% │ ⚡ ████████░░ 76%

  (3)  Ultra Compact — symbol + % only
       ⬡ Opus 4.6 │ ◈ 58% │ ⚡ 76%

  (r)  Restart from the beginning.
  (q)  Quit and do nothing.

  Choice [123rq]: _
```

### 方向鍵模式（Step 6 Theme，保持 v1 做法）
- 13 個主題太多不適合數字選擇
- 游標移動即時更新底部 preview
- 保留 j/k、數字跳轉、b 返回

## 各步驟詳細設計

### Step 1: 字型能力偵測（3 個 y/n 問題）

取代原本「直接選 nerd/unicode/ascii」的方式，改為視覺驗證：

**Q1: Nerd Font 測試**
```
    Does this look like a brain circuit icon?
              ---> 󰚩 <---
    (y/n/r/q)
```
- Yes → 繼續 Q2（Nerd Font 間距測試）
- No → 跳到 Q3（Unicode 測試）

**Q2: Nerd Font 間距測試**（僅 Q1=y 時）
```
    Do all these icons fit between the crosses?
              ---> X󰚩X󰍛XX󰔟X <---
    (y/n/r/q)
```
- Yes → `sel_symbols=nerd`，跳到 Step 2
- No → 降級到 unicode，跳到 Q3

**Q3: Unicode 測試**
```
    Do these three symbols display correctly?
              ---> ⬡  ◈  ⚡ <---
    (y/n/r/q)
```
- Yes → `sel_symbols=unicode`
- No → `sel_symbols=ascii`

### Step 2: Blocks 選擇

使用 toggle 模式（空格鍵切換），每個 block 附帶說明。保持 v1 的 checkbox 風格但加上嵌入式 preview：

```
  Step 2/7 — Which blocks to show? (Space to toggle)

  ❯ ✔ model       — Model name (e.g., Opus 4.6)
    ✔ context     — Context window usage %
    ✔ rate_5h     — 5-hour rate limit %
    ✔ rate_7d     — 7-day rate limit %
    ✗ directory   — Working directory
    ✗ git         — Git branch
    ✗ time        — Current time

  Preview:
  ⬡ Opus 4.6 │ ◈ 58% │ ⚡ 76% │ ⟳ 33%

  j/k move · Space toggle · Enter confirm · r restart · q quit
```

此步驟保持方向鍵（因為 toggle 需要游標位置），但加上 `r` 鍵支援。

### Step 3: Spacing + bar_width

數字選擇 + 嵌入式 preview：

```
  Step 3/7 — Spacing mode:

  (1)  Normal        — symbol + label + bar + %
       ⬡ Opus 4.6 │ ◈ CTX ██████░░░░ 58% │ ⚡ 5H ████████░░ 76%

  (2)  Compact       — symbol + bar + %
       ⬡ Opus 4.6 │ ◈ ██████░░░░ 58% │ ⚡ ████████░░ 76%

  (3)  Ultra Compact — symbol + % only
       ⬡ Opus 4.6 │ ◈ 58% │ ⚡ 76%

  (r)  Restart.  (q)  Quit.

  Choice [123rq]: _
```

**子步驟 3b: bar_width**（僅 spacing=normal 或 compact 時觸發）：

```
  Step 3b/7 — Progress bar width:

  (1)  Short   ██░░░░ 58%
  (2)  Medium  ██████░░░░ 58%
  (3)  Long    ████████████████░░░░░░░░░░ 58%

  (r)  Restart.  (q)  Quit.

  Choice [123rq]: _
```

### Step 4: Separator

數字選擇 + 嵌入式 preview：

```
  Step 4/7 — Block separator:

  (1)  Pipe   ⬡ Opus 4.6 │ ◈ 58% │ ⚡ 76%
  (2)  Slash  ⬡ Opus 4.6 / ◈ 58% / ⚡ 76%
  (3)  Dot    ⬡ Opus 4.6 · ◈ 58% · ⚡ 76%
  (4)  Space  ⬡ Opus 4.6   ◈ 58%   ⚡ 76%
  (5)  Arrow  ⬡ Opus 4.6 › ◈ 58% › ⚡ 76%

  (r)  Restart.  (q)  Quit.

  Choice [12345rq]: _
```

### Step 5: Time format（條件式）

僅當 Step 2 中啟用了 `time` block 時顯示：

```
  Step 5/7 — Time format:

  (1)  24-hour          ◷ 16:23:42
  (2)  12-hour          ◷ 04:23:42 PM
  (3)  24-hour (short)  ◷ 16:23
  (4)  12-hour (short)  ◷ 4:23 PM

  (r)  Restart.  (q)  Quit.

  Choice [1234rq]: _
```

### Step 6: Theme（方向鍵導覽）

保持 v1 做法：分組列表 + 游標即時 preview。這是最後一步設定，也是「大揭曉」— 使用者看到之前所有選擇搭配不同主題的完整效果。

### Step 7: 確認儲存

顯示完整摘要 + 最終 preview，寫入 config.json 並同步 plugin cache。

## 全域導覽

每個步驟都支援：
- `r` — Restart from the beginning（清除所有 sel_* 變數，回到 Step 1）
- `q` — Quit and do nothing
- `b` — Back to previous step（方向鍵模式的步驟）

## 修改檔案

| 檔案 | 變更 |
|------|------|
| `scripts/configure.sh` | 重構為 v2 wizard：字型偵測、混合輸入模式、嵌入式 preview、restart、bar_width、time_format、新步驟順序 |
| `scripts/statusline.sh` | 讀取 `time_format` 設定，支援 4 種時間格式 |
| `config.json` | 新增 `time_format` 欄位 |

## 實作步驟

### Phase 1: 基礎架構
1. 新增 `ask_yn()` 和 `ask_choice()` 輸入函式（p10k 風格的打字選擇）
2. 新增全域 `r` restart 機制（清除 sel_* 變數 + current_step=1）
3. 調整 main wizard loop 為新的 7 步順序

### Phase 2: 字型偵測
4. 實作 `step_font_detect()` — 3 個 y/n 視覺驗證問題
5. 根據回答自動設定 `sel_symbols`

### Phase 3: 嵌入式 preview 步驟
6. 改寫 `step_blocks()` — 保持 checkbox toggle，加上嵌入式 preview
7. 改寫 `step_spacing()` — 數字選擇 + 每個選項嵌入 preview（使用預設主題）
8. 新增 `step_bar_width()` — 條件觸發，數字選擇 + 嵌入式 preview
9. 改寫 `step_separator()` — 數字選擇 + 每個選項嵌入 preview
10. 新增 `step_time_format()` — 條件觸發，數字選擇 + 嵌入式 preview

### Phase 4: Theme + 收尾
11. 調整 `step_theme()` 為最後一步（保持方向鍵模式不變）
12. 更新 `step_done()` — 包含 time_format 和 bar_width 的寫入與 plugin cache 同步

### Phase 5: statusline.sh 支援
13. statusline.sh 讀取 `time_format` 設定（預設 `24h`）
14. 根據值使用不同 `date` 格式字串
15. config.json 向下相容處理

## 驗證方式

1. `bash scripts/configure.sh` 走完新流程
2. 字型偵測：nerd font terminal → 自動選 nerd；普通 terminal → 自動選 unicode/ascii
3. `r` 鍵在任何步驟都能重頭開始
4. bar_width 子步驟只在 normal/compact spacing 時出現
5. time_format 步驟只在 time block 啟用時出現
6. 嵌入式 preview 在每個選項下方正確渲染
7. config.json 包含所有新欄位（time_format、bar_width）
8. statusline.sh 正確讀取 time_format 並渲染
9. plugin cache 同步正常
