# 設計：`tokens` 區塊（本次 session 累計 token）

日期：2026-07-30

## 目標

statusline 目前有 `context`（CTX 百分比）與 `cost`（今日花費金額），但沒有任何欄位
告訴使用者「這場對話到目前為止燒掉多少 token」。新增一個 `tokens` 區塊補上這個缺口。

## 範圍決策

| 決策 | 選擇 | 理由 |
|---|---|---|
| 統計範圍 | 本次 session 累計 | 使用者關心的是「這場對話」的用量，而非跨 session 的日總量（後者已由 `cost` 區塊以金額形式呈現） |
| 是否含 cache read | **不含** | cache read 每輪重讀整個 context，累加後會膨脹到數十 M，數字被單一因子主導、對比意義低。`input + cache_creation + output` 反映「這場對話實際新增了多少內容」，量級落在 K～M，可讀性佳 |
| 平台 | Claude 與 Codex 都做 | 兩邊資料來源都已存在且成本低 |

**已知取捨**：不含 cache read 的定義與 `ccusage` 的 `totalTokens` 不一致。這是刻意的，
文件需明確說明公式，避免使用者拿去對帳。

## 顯示格式

區塊內容為 `⇅ 840K`（nerd symbol set 使用 `󰊖`）。

數字格式化規則：

| 條件 | 輸出 | 範例 |
|---|---|---|
| `< 1000` | 原樣整數 | `842` |
| `< 1000000` | 千位 + `K`，無小數 | `840K` |
| `>= 1000000` | 百萬位 + `M`，一位小數 | `12.4M` |

取不到資料時顯示 dim 的 `⇅ --`，沿用 `cost` / `burn` / `spend` 既有的降級慣例。
statusline 任何情況下都不得阻塞或報錯。

## 資料來源

### Claude 端

transcript JSONL 路徑解析順序：

1. stdin 的 `.transcript_path`
2. 退路：glob `~/.claude/projects/*/${session_id}.jsonl`

需要退路的原因：`session_id` 已確認存在於 statusline 的 stdin schema
（見 `tests/sample-input.json`），但 `transcript_path` 未實測確認。用 glob 精準比對
session id，不從 cwd 推導目錄 slug——slug 的轉換規則（`/` 與 `.` 都轉 `-`）不可靠。

計算方式：篩 `"type":"assistant"` 的列，依 `message.id + "|" + requestId` 去重
（與 `_refresh_cost` 的本地 fallback 使用同一套去重鍵），加總：

```
input_tokens + cache_creation_input_tokens + output_tokens
```

Sidechain（subagent）產生的列同樣計入——它們確實消耗了這個 session 的 token。

實測樣本結構（`~/.claude/projects/.../<session>.jsonl`）：

```json
{"message": {"id": "msg_...", "model": "claude-opus-5",
  "usage": {"input_tokens": 2, "cache_creation_input_tokens": 2336,
            "cache_read_input_tokens": 61949, "output_tokens": 958}},
 "requestId": "req_..."}
```

### Codex 端

取 rollout JSONL 中最後一筆 `payload.type == "token_count"` 事件的
`payload.info.total_token_usage`，走現有的 `read_latest_usage_field` 機制新增
一個 `session_tokens` 欄位。

公式：

```
input_tokens - cached_input_tokens + cache_write_input_tokens + output_tokens
```

實測驗證（rollout-2026-07-29T16-11-48）：

```json
{"input_tokens": 113320489, "cached_input_tokens": 108433664,
 "cache_write_input_tokens": 0, "output_tokens": 238231,
 "reasoning_output_tokens": 69418, "total_tokens": 113558720}
```

- `total_tokens == input_tokens + output_tokens`，故 `input_tokens` 已內含
  `cached_input_tokens`，需相減才能得到非快取的輸入量
- `reasoning_output_tokens` 已包含在 `output_tokens` 內，不可另外相加

Codex 端的 `total_token_usage` 本身就是 session 累計，不需自行加總或去重。

## 效能

Claude 端每次 render 都要掃 session JSONL。實測最大的 1.8MB session 全掃約 18ms。

快取策略採 **mtime 比對**而非固定 TTL：

- 快取檔 `$COST_CACHE_DIR/session-tokens-<session_id>`，內容為 `<mtime>|<total>`
- transcript 的 mtime 與快取記錄相同時直接用快取值，零計算成本
- mtime 改變才重算

選 mtime 而非固定秒數 TTL 的理由：transcript 只在對話推進時變動，mtime 是精確的
失效訊號，既不會顯示過期數字，也不會在 idle 時反覆重算。

Codex 端只讀最後一筆 `token_count` 事件，沿用該 adapter 既有的 footer 快取機制。

## 接線點

| 檔案 | 變更 |
|---|---|
| `statusline.sh` | `S_TOKENS`（`sym tokens`，fallback `󰊖`）、加入 `show_icons=false` 的清空清單、`render_block_tokens`、`block_text_tokens`（rainbow 模式）、classic 與 rainbow 兩處 dispatch case |
| `config.json` | `blocks` 陣列可選 `tokens` |
| `configure.sh` | `block_ids` 陣列與區塊說明文字 |
| `themes/*.json`（15 檔） | 補 `symbols.{nerd,unicode,ascii}.tokens` 與 `blocks.tokens` 色彩 |
| `adapters/codex/statusline.sh` | `session_tokens` 欄位與區塊渲染 |
| `adapters/codex/config.json` | blocks 預設值 |
| `README.md` + `docs/README.zh-TW.md` | 區塊表格新增一列，說明計算公式與「不含 cache read」 |
| `tests/test-statusline.sh` | 假 transcript → 斷言格式化輸出 |
| `tests/adapters/codex/` | 假 rollout → 斷言公式正確 |

theme 檔理論上可不改（`block_color` fallback 到 `accent_1`、`block_bg` fallback 到
`bg_panel`、`sym` 有硬編碼 fallback），但 15 個主題都補齊才能維持視覺一致。

## 順帶清理

`statusline.sh` 的 `render_block_turn_usage` 與 `block_text_turn_usage` 是死碼：classic
與 rainbow 兩處 dispatch 都沒有對應的 case，且它們讀取的 `/tmp/claude-turn-usage.txt`
在整個 repo 找不到任何 writer。新區塊上線後移除。

**不要連帶刪掉檔案尾端的第二行渲染器。** 那段（`# ── Turn usage (second line) ──`）是
獨立且活著的功能：它讀的是 `$COST_CACHE_DIR/turn-usage-<md5>.txt`（不同的路徑），由
repo 外的 `~/.claude/hooks/show-turn-usage.sh`（Stop hook）寫入，輸出 `Last Chat
cache:… in:… out:… $…` 這一行。

兩者語義不重疊，可並存：第二行是**上一輪**的明細，`tokens` 區塊是**整場 session** 的
累計量。

## 非目標

- 不提供跨 session / 今日總 token 的統計（`cost` 區塊已覆蓋日維度的用量感知）
- 不拆開顯示 input / output 兩個數字（statusline 寬度已吃緊，目前預設就有 6 個區塊）
- 不改動 `context` 區塊現有的百分比呈現
