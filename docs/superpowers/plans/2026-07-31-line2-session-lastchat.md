# 第二列 session / last_chat 雙欄 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把狀態列的 token / 花費資訊整併成第二列的兩個獨立區塊 `session`（本次對話累計）與 `last_chat`（最後一次 API 呼叫），兩者格式統一為 `<符號> <總token> $<金額>`，並可在 `configure.sh` 中分列開關。

**Architecture:** `config.json` 新增 `blocks_line2` 陣列；statusline.sh 把既有的區塊組裝邏輯抽成可重複呼叫的函式，第一列讀 `blocks`、第二列讀 `blocks_line2`，兩列共用同一套 rainbow / classic 渲染。資料層以單次 transcript 掃描同時算出 session 與 last_chat 的 token 與金額，寫入既有的 mtime-keyed 快取（欄位由 2 個擴充為 5 個）。移除硬編碼的 `turn_line` 區段與其對 repo 外部 Stop hook 的依賴。

**Tech Stack:** Bash 3.2（macOS 內建）、jq、awk。無外部相依。

## Global Constraints

- **token 定義**：`session` 與 `last_chat` 的總 token 一律為 `input_tokens + cache_creation_input_tokens + cache_read_input_tokens + output_tokens`。**含 cache_read**，這推翻 `docs/superpowers/specs/2026-07-30-session-tokens-block-design.md` 的舊定義。
- **去重鍵**：`message.id + "|" + (requestId // "")`，沿用既有慣例，重試請求只計一次。
- **定價表**：沿用 statusline.sh:250-255 既有的 `price($m)` jq 函式與 `startswith` 比對規則，不得新增或改動單價數字：
  - `claude-opus*` → `{i: 15, o: 75, cw: 18.75, cr: 1.50}`
  - `claude-sonnet*` → `{i: 3, o: 15, cw: 3.75, cr: 0.30}`
  - `claude-haiku*` → `{i: 1, o: 5, cw: 1.25, cr: 0.10}`
  - 其他 → 比照 opus
- **金額格式**：`≥ 1` 用兩位小數（`$1.89`），`< 1` 用四位小數（`$0.3442`）。
- **Bash 3.2 相容**：不可使用 `declare -A`、`${var^^}`、`mapfile`/`readarray`。
- **README 雙語同步**：`README.md`（英文）與 `docs/README.zh-TW.md`（繁中）任一變更必須兩份同步（專案規約）。
- **每個 Task 結束後 commit**，commit message 用繁體中文並有足夠細節（全域規約）。
- **測試指令**：`bash tests/test-statusline.sh`（Claude 側）、`bash tests/adapters/codex/test-statusline.sh`（Codex 側）。兩者都必須全綠才算完成。
- **不在本次範圍**：Codex 的 session 金額、Codex 的 last_chat。

---

## File Structure

| 檔案 | 責任 | 動作 |
|---|---|---|
| `statusline.sh` | 資料抓取、格式化、區塊渲染、兩列組裝 | 修改 |
| `config.json` | 預設設定 | 修改 |
| `themes/*.json`（14 個，含 `custom-example/`） | 顏色與符號 | 修改 |
| `configure.sh` | 互動設定精靈 | 修改 |
| `adapters/codex/statusline.sh` | Codex 轉接層 | 修改 |
| `adapters/codex/config.json` | Codex 預設設定 | 修改 |
| `install-codex.sh` | Codex 安裝器預設 blocks | 修改 |
| `tests/test-statusline.sh` | Claude 側測試 | 修改 |
| `tests/adapters/codex/test-statusline.sh` | Codex 側測試 | 修改 |
| `README.md` / `docs/README.zh-TW.md` | 文件 | 修改 |
| `LOG.md` | 變更紀錄 | 修改 |

---

## Task 1: `fmt_price` 金額格式化

**Files:**
- Modify: `statusline.sh`（在 `fmt_tokens` 之後，約第 351 行）
- Test: `tests/test-statusline.sh`

**Interfaces:**
- Produces: `fmt_price <number>` → 印出不含 `$` 的字串，`≥1` 兩位小數、`<1` 四位小數。空字串或非數字輸入印出 `--`。

- [ ] **Step 1: 寫失敗測試**

在 `tests/test-statusline.sh` 中，`test_tokens_number_formatting` 函式之後插入：

```bash
# ── fmt_price ────────────────────────────────────────────────────────────
# 直接 source statusline.sh 會執行整支腳本，因此改用 bash -c 抽出函式定義後求值。
_call_fmt_price() {
  local body
  body=$(awk '/^fmt_price\(\)/,/^}/' "$STATUSLINE")
  bash -c "$body; fmt_price \"\$1\"" _ "$1"
}

test_fmt_price_formatting() {
  local n expected out
  while IFS='|' read -r n expected; do
    out=$(_call_fmt_price "$n")
    check "test_fmt_price_formatting: $n" "$expected" "$out"
  done <<'EOF'
0|0.0000
0.3442|0.3442
0.9999|0.9999
1|1.00
1.894|1.89
89.2|89.20
1234.5|1234.50
EOF
  out=$(_call_fmt_price "")
  check "test_fmt_price_formatting: 空字串降級" "--" "$out"
}
```

並在檔案末端 `main()` 的 `test_tokens_number_formatting` 那一行之後加入：

```bash
  test_fmt_price_formatting
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `bash tests/test-statusline.sh 2>&1 | grep fmt_price`
Expected: FAIL — `awk` 抓不到 `fmt_price()` 定義，輸出為空字串，所有斷言不符。

- [ ] **Step 3: 實作**

在 `statusline.sh` 的 `fmt_tokens()` 函式（結尾的 `}` 在第 351 行附近）之後插入：

```bash
# $1.89 / $0.3442 —— 小額用四位小數，否則兩位小數會全部塌成 $0.00
fmt_price() {
  awk -v v="${1:-}" 'BEGIN{
    if (v == "" || v + 0 != v) { printf "--"; exit }
    if (v >= 1) printf "%.2f", v
    else        printf "%.4f", v
  }'
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `bash tests/test-statusline.sh 2>&1 | grep fmt_price`
Expected: 8 行全部 `✓`

Run: `bash tests/test-statusline.sh`
Expected: `Results: N passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/test-statusline.sh
git commit -m "feat: 新增 fmt_price 金額格式化函式

session 與 last_chat 兩個新區塊都要顯示金額。小額（last_chat 常見
的 \$0.3442）若用兩位小數會全部塌成 \$0.00，因此以 1 為界：大於等
於 1 用兩位小數，小於 1 用四位小數。

非數字或空字串輸入降級為 --，與既有 token 區塊的降級行為一致。

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: transcript 解析改為輸出四個值

**Files:**
- Modify: `statusline.sh:279-341`（session tokens 區段）
- Test: `tests/test-statusline.sh`

**Interfaces:**
- Consumes: `_resolve_transcript()`（既有，不改）
- Produces:
  - 全域變數 `session_tokens`、`session_cost`、`last_tokens`、`last_cost`
  - `_scan_transcript <file>` → 印出 `<session_tokens>|<session_cost>|<last_tokens>|<last_cost>`，四個值以 `|` 分隔。空 transcript 印出 `0|0|0|0`。
  - 環境變數覆寫：`SESSION_TOKENS_OVERRIDE`、`SESSION_COST_OVERRIDE`、`LAST_CHAT_TOKENS_OVERRIDE`、`LAST_CHAT_COST_OVERRIDE`。任一被設定時，整段 transcript 解析被短路，未設定者留空。

**背景：** 既有的 `_count_session_tokens()` 只回傳一個排除 cache_read 的總和。本 task 用 `_scan_transcript()` 取代它，一次掃描產出四個值，並把快取檔格式從 `<mtime>|<total>` 擴充為 `<mtime>|<s_tokens>|<s_cost>|<l_tokens>|<l_cost>`。

- [ ] **Step 1: 寫失敗測試**

`tests/test-statusline.sh` 中把既有的 `test_tokens_excludes_cache_read` **整個函式刪除**（它斷言的是被推翻的舊行為），並把 `main()` 裡呼叫它的那一行也刪除。

接著把既有的 `_tokens_cfg` 改成 blocks 用新名稱：

```bash
_tokens_cfg() {
  printf '{"theme":"terminal-glitch","symbol_set":"ascii","spacing":"normal","style":"classic","separator":"|","blocks":["session"],"bar_width":6,"show_icons":true,"account_type":"subscription"}'
}
```

把既有的 `test_tokens_sums_session_transcript`、`test_tokens_dedupes_retried_request`、`test_tokens_resolves_by_session_id` 三個函式的期望值改成含 cache_read 的新定義：

```bash
test_tokens_sums_session_transcript() {
  local t=$(mktemp)
  # (1000+2000+9999+500) + (4000+8000+9999+1500) = 36998 → "36K"
  # 成本：opus。in 5000*15 + cw 10000*18.75 + cr 19998*1.5 + out 2000*75
  #      = 75000 + 187500 + 29997 + 150000 = 442497 (per 1e6) = $0.442497 → $0.4425
  { _tokens_entry m1 r1 1000 2000 9999 500
    _tokens_entry m2 r2 4000 8000 9999 1500; } > "$t"
  local out=$(_tokens_render "$t")
  rm -f "$t"
  check "test_tokens_sums_session_transcript: 四類 token 全加總" " [#] 36K \$0.4425 " "$out"
}

test_tokens_dedupes_retried_request() {
  local t=$(mktemp)
  # 同一組 message.id|requestId 出現兩次，只能算一次
  # 10000+20000+9999+5000 = 44999 → "44K"
  # opus 成本：10000*15 + 20000*18.75 + 9999*1.5 + 5000*75
  #          = 150000 + 375000 + 14998.5 + 375000 = 914998.5 /1e6 = $0.9149985 → $0.9150
  { _tokens_entry m1 r1 10000 20000 9999 5000
    _tokens_entry m1 r1 10000 20000 9999 5000; } > "$t"
  local out=$(_tokens_render "$t")
  rm -f "$t"
  check "test_tokens_dedupes_retried_request: 重複列只計一次" " [#] 44K \$0.9150 " "$out"
}

test_tokens_resolves_by_session_id() {
  # 不給 transcript_path，改由 session_id 在 $HOME/.claude/projects/*/ 找
  local home=$(mktemp -d) cfg=$(mktemp)
  mkdir -p "$home/.claude/projects/some-project"
  _tokens_entry m1 r1 1000000 500000 9999 234567 \
    > "$home/.claude/projects/some-project/abc-123.jsonl"
  _tokens_cfg > "$cfg"
  local out=$(printf '{"session_id":"abc-123"}' \
    | env HOME="$home" CONFIG_OVERRIDE="$cfg" bash "$STATUSLINE" 2>/dev/null \
    | head -1 | sed 's/\x1b\[[0-9;]*m//g')
  rm -rf "$home"; rm -f "$cfg"
  # 1,744,566 → 無條件捨去到一位小數 → 1.7M
  # opus 成本：1000000*15 + 500000*18.75 + 9999*1.5 + 234567*75
  #          = 15000000 + 9375000 + 14998.5 + 17592525 = 41982523.5 /1e6 → $41.98
  check "test_tokens_resolves_by_session_id: 用 session_id 找到 transcript" " [#] 1.7M \$41.98 " "$out"
}
```

新增三個測試：

```bash
test_session_includes_cache_read() {
  local t=$(mktemp)
  # cache_read 高達 5,000,000；必須被計入
  { _tokens_entry m1 r1 1000 2000 5000000 500; } > "$t"
  local out=$(_tokens_render "$t")
  rm -f "$t"
  # 1000+2000+5000000+500 = 5003500 → 5.0M
  # opus 成本：1000*15 + 2000*18.75 + 5000000*1.5 + 500*75
  #          = 15000 + 37500 + 7500000 + 37500 = 7590000 /1e6 → $7.59
  check "test_session_includes_cache_read: cache_read 計入 token" " [#] 5.0M \$7.59 " "$out"
}

test_session_prices_by_model() {
  local t=$(mktemp)
  # sonnet 單價：in 3 / cw 3.75 / cr 0.30 / out 15
  # 1000*3 + 2000*3.75 + 4000*0.30 + 500*15 = 3000+7500+1200+7500 = 19200 /1e6
  printf '{"type":"assistant","requestId":"r1","message":{"id":"m1","model":"claude-sonnet-5","usage":{"input_tokens":1000,"cache_creation_input_tokens":2000,"cache_read_input_tokens":4000,"output_tokens":500}}}\n' > "$t"
  local out=$(_tokens_render "$t")
  rm -f "$t"
  check "test_session_prices_by_model: sonnet 用 sonnet 單價" " [#] 7K \$0.0192 " "$out"
}

test_session_degraded_without_transcript() {
  local home=$(mktemp -d) cfg=$(mktemp)
  _tokens_cfg > "$cfg"
  local out=$(printf '{"session_id":"no-such-session"}' \
    | env HOME="$home" CONFIG_OVERRIDE="$cfg" bash "$STATUSLINE" 2>/dev/null \
    | head -1 | sed 's/\x1b\[[0-9;]*m//g')
  rm -rf "$home"; rm -f "$cfg"
  check "test_session_degraded_without_transcript: 無 transcript 顯示 --" " [#] -- " "$out"
}
```

刪除既有的 `test_tokens_degraded_without_transcript`（被上面的 `test_session_degraded_without_transcript` 取代），並更新 `main()`：把 `test_tokens_excludes_cache_read` 與 `test_tokens_degraded_without_transcript` 兩行換成：

```bash
  test_session_includes_cache_read
  test_session_prices_by_model
  test_session_degraded_without_transcript
```

`test_tokens_number_formatting` 裡的期望值也要加上金額。把該函式的 heredoc 與斷言改成：

```bash
test_tokens_number_formatting() {
  local cfg=$(mktemp) home=$(mktemp -d)
  _tokens_cfg > "$cfg"
  # 邊界重點：999999 不可進位成 "1000K"，必須維持 999K（跨單位溢位防護）
  local n expected out
  while IFS='|' read -r n expected; do
    out=$(printf '{"session_id":"x"}' \
      | env HOME="$home" CONFIG_OVERRIDE="$cfg" \
            SESSION_TOKENS_OVERRIDE="$n" SESSION_COST_OVERRIDE="1.5" \
            bash "$STATUSLINE" 2>/dev/null \
      | head -1 | sed 's/\x1b\[[0-9;]*m//g')
    check "test_tokens_number_formatting: $n" " [#] $expected \$1.50 " "$out"
  done <<'EOF'
0|0
999|999
1000|1K
999999|999K
1000000|1.0M
12456789|12.4M
EOF
  rm -rf "$home"; rm -f "$cfg"
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `bash tests/test-statusline.sh 2>&1 | grep -E "session_|tokens_"`
Expected: FAIL — 輸出仍是舊的 ` [#] 17K `（無金額），且 `blocks:["session"]` 尚無對應 case，多數斷言不符。

- [ ] **Step 3: 實作**

在 `statusline.sh` 中，把第 305-341 行（從 `_count_session_tokens() {` 到快取寫入的 `fi` 為止）整段替換為：

```bash
# 單次掃描產出四個值：session 累計 token/金額、最後一次呼叫的 token/金額。
# 去重鍵 message.id|requestId 沿用 cost fallback 的慣例，重試不重複計算。
# 定價表與 _refresh_cost 的 price() 一致，用 startswith 讓新 model ID
# 自動繼承家族單價。四類 token 全部計入（含 cache_read）——金額必須含它，
# token 也含才對得起來。
_scan_transcript() {
  grep -h '"type":"assistant"' "$1" 2>/dev/null | "$JQ" -s -r '
    def price($m):
      if   ($m | startswith("claude-opus"))   then {i: 15, o: 75, cw: 18.75, cr: 1.50}
      elif ($m | startswith("claude-sonnet")) then {i: 3,  o: 15, cw: 3.75,  cr: 0.30}
      elif ($m | startswith("claude-haiku"))  then {i: 1,  o: 5,  cw: 1.25,  cr: 0.10}
      else {i: 15, o: 75, cw: 18.75, cr: 1.50} end;
    def tok($u): ($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0)
                 + ($u.cache_read_input_tokens // 0) + ($u.output_tokens // 0);
    def cost($e): $e.message as $msg | $msg.usage as $u | price($msg.model // "") as $p |
      (($u.input_tokens // 0) * $p.i
       + ($u.output_tokens // 0) * $p.o
       + ($u.cache_creation_input_tokens // 0) * $p.cw
       + ($u.cache_read_input_tokens // 0) * $p.cr) / 1000000;
    [ .[] | select(.message.id != null) |
      {k: (.message.id + "|" + (.requestId // "")), e: .}
    ] | group_by(.k) | map(.[0].e) as $msgs |
    ( [ $msgs[] | tok(.message.usage) ] | add // 0 ) as $st |
    ( [ $msgs[] | cost(.) ]             | add // 0 ) as $sc |
    ( if ($msgs | length) > 0 then ($msgs | last) else null end ) as $lastmsg |
    ( if $lastmsg == null then 0 else tok($lastmsg.message.usage) end ) as $lt |
    ( if $lastmsg == null then 0 else cost($lastmsg) end ) as $lc |
    "\($st)|\($sc)|\($lt)|\($lc)"
  ' 2>/dev/null
}

_transcript=""
# Override 短路整段 transcript 解析 —— 供 configure.sh 的即時預覽（樣本資料
# 沒有真實 session）、Codex adapter 與測試使用。
if [ -n "${SESSION_TOKENS_OVERRIDE:-}${SESSION_COST_OVERRIDE:-}${LAST_CHAT_TOKENS_OVERRIDE:-}${LAST_CHAT_COST_OVERRIDE:-}" ]; then
  session_tokens="${SESSION_TOKENS_OVERRIDE:-}"
  session_cost="${SESSION_COST_OVERRIDE:-}"
  last_tokens="${LAST_CHAT_TOKENS_OVERRIDE:-}"
  last_cost="${LAST_CHAT_COST_OVERRIDE:-}"
else
  _transcript=$(_resolve_transcript)
fi
if [ -n "$_transcript" ]; then
  _tokens_cache="$COST_CACHE_DIR/session-tokens-$(basename "$_transcript" .jsonl)"
  _t_mtime=$(stat -f%m "$_transcript" 2>/dev/null || echo 0)
  _c_mtime="" _c_st="" _c_sc="" _c_lt="" _c_lc=""
  # 舊版快取只有兩個欄位，讀進來 _c_lc 會是空的 → 視為 miss 重算。
  [ -f "$_tokens_cache" ] && IFS='|' read -r _c_mtime _c_st _c_sc _c_lt _c_lc < "$_tokens_cache"

  if [ -n "$_c_lc" ] && [ "$_c_mtime" = "$_t_mtime" ]; then
    session_tokens="$_c_st"; session_cost="$_c_sc"
    last_tokens="$_c_lt";    last_cost="$_c_lc"
  else
    _scanned=$(_scan_transcript "$_transcript")
    if [ -n "$_scanned" ]; then
      IFS='|' read -r session_tokens session_cost last_tokens last_cost <<< "$_scanned"
      mkdir -p "$COST_CACHE_DIR"
      printf '%s|%s\n' "$_t_mtime" "$_scanned" > "$_tokens_cache" 2>/dev/null
    fi
  fi
fi
```

同時把第 283 行的：

```bash
session_tokens=""
```

改為：

```bash
session_tokens=""
session_cost=""
last_tokens=""
last_cost=""
```

- [ ] **Step 4: 執行測試確認通過**

此時 `blocks:["session"]` 還沒有對應的渲染 case，測試仍會失敗——這是預期的，Task 3 才會補上。先只驗證資料層：

Run:
```bash
T=$(mktemp)
printf '{"type":"assistant","requestId":"r1","message":{"id":"m1","model":"claude-opus-5","usage":{"input_tokens":1000,"cache_creation_input_tokens":2000,"cache_read_input_tokens":9999,"output_tokens":500}}}\n' > "$T"
bash -c "$(awk '/^_scan_transcript\(\)/,/^}/' statusline.sh); JQ=\$(command -v jq); _scan_transcript \"$T\""
rm -f "$T"
```
Expected: 四個以 `|` 分隔的欄位，開頭為 `13499|0.10499`（token 13499；成本
`1000*15 + 2000*18.75 + 9999*1.5 + 500*75 = 104998.5 /1e6 = 0.1049985`，jq 的浮點
輸出尾數可能略有差異，只需確認前綴與欄位數）。單筆訊息時 last 兩欄與 session 相同。

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/test-statusline.sh
git commit -m "feat: transcript 掃描改為一次產出 session 與 last_chat 四個值

以 _scan_transcript() 取代 _count_session_tokens()，同一次掃描同時
算出本次 session 的累計 token 與金額，以及最後一次 API 呼叫的 token
與金額。第二列的 last_chat 因此不再需要依賴 repo 外部的 Stop hook。

token 定義改為四類全加總（含 cache_read）。cache_read 佔實際花費約
一半，金額既然必須含它，token 也含才對得起來。這推翻 2026-07-30
session-tokens 設計中排除 cache_read 的做法。

金額沿用 _refresh_cost 既有的 price() 定價表，以 startswith 按 model
家族分價，新 model ID 自動繼承。原本 repo 外的 hook 把單價硬編成
Opus，切到 Sonnet 會多算約 5 倍。

快取檔格式由 <mtime>|<total> 擴充為五欄位。讀取時若最後一欄為空
（舊格式殘留）視為 cache miss 重算，不需要手動清快取。

新增 SESSION_COST_OVERRIDE / LAST_CHAT_TOKENS_OVERRIDE /
LAST_CHAT_COST_OVERRIDE 三個環境變數，與既有的
SESSION_TOKENS_OVERRIDE 一起短路 transcript 解析。

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `session` 與 `last_chat` 區塊渲染

**Files:**
- Modify: `statusline.sh`（符號讀取約第 124 行、`block_text_tokens` 約第 536 行、`render_block_tokens` 約第 681 行、兩處 dispatch case 約第 790 與 823 行）
- Test: `tests/test-statusline.sh`

**Interfaces:**
- Consumes: Task 1 的 `fmt_price`、Task 2 的 `session_tokens` / `session_cost` / `last_tokens` / `last_cost`、既有的 `fmt_tokens`
- Produces:
  - `block_text_session` / `render_block_session`
  - `block_text_last_chat` / `render_block_last_chat`
  - 全域符號變數 `S_SESSION`、`S_LAST_CHAT`
  - dispatch case 名稱 `session`、`last_chat`

**降級規則：** token 為空 → 輸出 ` <符號> -- `。token 有值但金額為空（Codex）→ 輸出 ` <符號> 646K `，不含 `$`。

- [ ] **Step 1: 寫失敗測試**

`tests/test-statusline.sh` 新增：

```bash
_last_chat_cfg() {
  printf '{"theme":"terminal-glitch","symbol_set":"ascii","spacing":"normal","style":"classic","separator":"|","blocks":["last_chat"],"bar_width":6,"show_icons":true,"account_type":"subscription"}'
}

test_last_chat_uses_final_message() {
  local t=$(mktemp) cfg=$(mktemp) home=$(mktemp -d)
  # 兩筆訊息，last_chat 只取最後一筆：4000+8000+1000+1500 = 14500 → 14K
  # opus 成本：4000*15 + 1500*75 + 8000*18.75 + 1000*1.5 = 60000+112500+150000+1500
  #          = 324000 /1e6 = $0.324
  { _tokens_entry m1 r1 1000 2000 9999 500
    _tokens_entry m2 r2 4000 8000 1000 1500; } > "$t"
  _last_chat_cfg > "$cfg"
  local out=$(printf '{"session_id":"fixture","transcript_path":"%s"}' "$t" \
    | env HOME="$home" CONFIG_OVERRIDE="$cfg" bash "$STATUSLINE" 2>/dev/null \
    | head -1 | sed 's/\x1b\[[0-9;]*m//g')
  rm -rf "$home"; rm -f "$cfg" "$t"
  check "test_last_chat_uses_final_message: 只取最後一筆訊息" " [L] 14K \$0.3240 " "$out"
}

test_session_without_cost_omits_dollar() {
  # Codex adapter 只餵 token 不餵金額，此時不可印出 $
  local cfg=$(mktemp) home=$(mktemp -d)
  _tokens_cfg > "$cfg"
  local out=$(printf '{"session_id":"x"}' \
    | env HOME="$home" CONFIG_OVERRIDE="$cfg" SESSION_TOKENS_OVERRIDE="123456" \
          bash "$STATUSLINE" 2>/dev/null \
    | head -1 | sed 's/\x1b\[[0-9;]*m//g')
  rm -rf "$home"; rm -f "$cfg"
  check "test_session_without_cost_omits_dollar: 無金額時只印 token" " [#] 123K " "$out"
}
```

`main()` 中在 `test_session_degraded_without_transcript` 之後加入：

```bash
  test_last_chat_uses_final_message
  test_session_without_cost_omits_dollar
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `bash tests/test-statusline.sh 2>&1 | grep -E "session|last_chat"`
Expected: FAIL — dispatch 沒有 `session` / `last_chat` 的 case，輸出為空字串或只有分隔符。

- [ ] **Step 3: 實作**

**3a.** `statusline.sh` 第 124-125 行的：

```bash
S_TOKENS=$(sym tokens)
[ "$S_TOKENS" = "?" ] && S_TOKENS="⇅"
```

改為：

```bash
S_SESSION=$(sym session)
[ "$S_SESSION" = "?" ] && S_SESSION=$(sym tokens)
[ "$S_SESSION" = "?" ] && S_SESSION="⇅"
S_LAST_CHAT=$(sym last_chat)
[ "$S_LAST_CHAT" = "?" ] && S_LAST_CHAT="⌯"
```

**3b.** 第 129 行的 `cfg_show_icons` 清空行，把 `S_TOKENS=""` 換成 `S_SESSION="" S_LAST_CHAT=""`：

```bash
  S_MODEL="" S_CTX="" S_5H="" S_7D="" S_DIR="" S_GIT="" S_TIME="" S_COST="" S_SPEND="" S_CREDIT="" S_BURN="" S_SESSION="" S_LAST_CHAT=""
```

**3c.** 把 `block_text_tokens()`（約第 536-542 行）整個函式替換為：

```bash
# 共用的內文組法：token 為空 → --；金額為空（Codex 無 session 價）→ 只印 token
_usage_text() {
  local symbol="$1" toks="$2" cost="$3"
  if [ -z "$toks" ]; then
    echo -n " ${symbol} -- "
  elif [ -z "$cost" ]; then
    echo -n " ${symbol} $(fmt_tokens "$toks") "
  else
    echo -n " ${symbol} $(fmt_tokens "$toks") \$$(fmt_price "$cost") "
  fi
}

block_text_session()   { _usage_text "$S_SESSION"   "$session_tokens" "$session_cost"; }
block_text_last_chat() { _usage_text "$S_LAST_CHAT" "$last_tokens"    "$last_cost"; }
```

**3d.** 把 `render_block_tokens()`（約第 681-690 行）整個函式替換為：

```bash
_render_usage() {
  local name="$1" symbol="$2" toks="$3" cost="$4"
  local fg=$(hex_to_fg "$(block_color "$name")")
  local bg=$(hex_to_bg "$(block_bg "$name")")
  if [ -z "$toks" ]; then
    local dim_fg=$(hex_to_fg "$C_DIM")
    echo -n "${bg}${dim_fg} ${symbol} -- ${RESET}"
  elif [ -z "$cost" ]; then
    echo -n "${bg}${fg}${BOLD} ${symbol} $(fmt_tokens "$toks") ${RESET}"
  else
    echo -n "${bg}${fg}${BOLD} ${symbol} $(fmt_tokens "$toks") \$$(fmt_price "$cost") ${RESET}"
  fi
}

render_block_session()   { _render_usage session   "$S_SESSION"   "$session_tokens" "$session_cost"; }
render_block_last_chat() { _render_usage last_chat "$S_LAST_CHAT" "$last_tokens"    "$last_cost"; }
```

**3e.** rainbow dispatch（約第 790 行）把 `tokens)    text=$(block_text_tokens) ;;` 換成：

```bash
      session)   text=$(block_text_session) ;;
      last_chat) text=$(block_text_last_chat) ;;
```

**3f.** classic dispatch（約第 823 行）把 `tokens)    output+=$(render_block_tokens) ;;` 換成：

```bash
      session)   output+=$(render_block_session) ;;
      last_chat) output+=$(render_block_last_chat) ;;
```

- [ ] **Step 4: 執行測試確認通過**

Run: `bash tests/test-statusline.sh`
Expected: `Results: N passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/test-statusline.sh
git commit -m "feat: 新增 session 與 last_chat 兩個區塊渲染器

取代原本的 tokens 區塊。兩者格式統一為「符號 總token \$金額」，共用
_usage_text（classic 前的純文字）與 _render_usage（classic 上色）兩
個內部函式，避免兩份幾乎相同的程式碼。

三段降級：
- token 為空（無 transcript）→ 「符號 --」，用 dim 色
- token 有值但金額為空 → 只印 token，不印 \$。Codex adapter 只餵得出
  token，靠這條保持可用
- 兩者皆有 → 完整輸出

符號讀取加了兩層 fallback：session 先找主題的 symbols.session，找不到
退回既有的 symbols.tokens，再找不到用硬編碼 ⇅。舊主題檔因此不會壞掉。

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `blocks_line2` 兩列組裝

**Files:**
- Modify: `statusline.sh:702-850`（組裝區與檔尾輸出）、`config.json`
- Test: `tests/test-statusline.sh`

**Interfaces:**
- Consumes: Task 3 的區塊渲染函式
- Produces:
  - `cfg_blocks_line2` 全域變數
  - `assemble_line <block...>` → 印出整列已上色的字串。接受任意數量的區塊名稱參數。
  - `config.json` 的 `blocks_line2` 欄位

**背景：** 目前組裝邏輯（statusline.sh:702-826）直接寫在頂層並寫入全域 `output`，且 quota 帳號的 spend/credit 替換邏輯混在裡面。本 task 把「渲染一列」抽成函式，quota 替換邏輯只作用於第一列（第二列沒有 rate_5h / rate_7d，不受影響）。

rainbow 的色彩循環（`PL_CYCLE`）以區塊在**該列**中的索引計算，因此第二列從 `accent_1` 重新起算，`session` 拿到青色、`last_chat` 拿到粉紅，兩欄自然有色差。

- [ ] **Step 1: 寫失敗測試**

`tests/test-statusline.sh` 新增：

```bash
test_line2_renders_second_row() {
  local t=$(mktemp) cfg=$(mktemp) home=$(mktemp -d)
  _tokens_entry m1 r1 1000 2000 1000 500 > "$t"
  printf '{"theme":"terminal-glitch","symbol_set":"ascii","spacing":"normal","style":"classic","separator":"|","blocks":["model"],"blocks_line2":["session","last_chat"],"bar_width":6,"show_icons":true,"account_type":"subscription"}' > "$cfg"
  local out=$(printf '{"session_id":"fixture","transcript_path":"%s","model":{"display_name":"Opus 5"}}' "$t" \
    | env HOME="$home" CONFIG_OVERRIDE="$cfg" bash "$STATUSLINE" 2>/dev/null \
    | sed 's/\x1b\[[0-9;]*m//g')
  rm -rf "$home"; rm -f "$cfg" "$t"
  local line2=$(printf '%s' "$out" | sed -n '2p')
  # 4500 tokens → "4K"；成本 1000*15 + 2000*18.75 + 1000*1.5 + 500*75
  #             = 15000 + 37500 + 1500 + 37500 = 91500 /1e6 → $0.0915
  # 只有一筆訊息，故 last_chat 與 session 數值相同
  # SEP 實測為 " | "，與區塊自帶的前後空白相加後是兩個空格（實測驗證過）
  check "test_line2_renders_second_row: 第二列有 session 與 last_chat" " [#] 4K \$0.0915  |  [L] 4K \$0.0915 " "$line2"
}

test_line2_absent_when_empty() {
  local t=$(mktemp) cfg=$(mktemp) home=$(mktemp -d)
  _tokens_entry m1 r1 1000 2000 1000 500 > "$t"
  printf '{"theme":"terminal-glitch","symbol_set":"ascii","spacing":"normal","style":"classic","separator":"|","blocks":["model"],"blocks_line2":[],"bar_width":6,"show_icons":true,"account_type":"subscription"}' > "$cfg"
  local out=$(printf '{"session_id":"fixture","transcript_path":"%s","model":{"display_name":"Opus 5"}}' "$t" \
    | env HOME="$home" CONFIG_OVERRIDE="$cfg" bash "$STATUSLINE" 2>/dev/null \
    | sed 's/\x1b\[[0-9;]*m//g')
  rm -rf "$home"; rm -f "$cfg" "$t"
  local nonempty=$(printf '%s' "$out" | grep -c '[^[:space:]]')
  check "test_line2_absent_when_empty: 空陣列時只有一列" "1" "$nonempty"
}

test_line2_absent_when_missing() {
  # 舊 config 沒有 blocks_line2 欄位，不應憑空多出第二列
  local t=$(mktemp) cfg=$(mktemp) home=$(mktemp -d)
  _tokens_entry m1 r1 1000 2000 1000 500 > "$t"
  printf '{"theme":"terminal-glitch","symbol_set":"ascii","spacing":"normal","style":"classic","separator":"|","blocks":["model"],"bar_width":6,"show_icons":true,"account_type":"subscription"}' > "$cfg"
  local out=$(printf '{"session_id":"fixture","transcript_path":"%s","model":{"display_name":"Opus 5"}}' "$t" \
    | env HOME="$home" CONFIG_OVERRIDE="$cfg" bash "$STATUSLINE" 2>/dev/null \
    | sed 's/\x1b\[[0-9;]*m//g')
  rm -rf "$home"; rm -f "$cfg" "$t"
  local nonempty=$(printf '%s' "$out" | grep -c '[^[:space:]]')
  check "test_line2_absent_when_missing: 欄位缺漏時只有一列" "1" "$nonempty"
}

test_legacy_tokens_maps_to_session() {
  # 舊 config 的 blocks 含 "tokens"，應映射成 session 區塊
  local t=$(mktemp) cfg=$(mktemp) home=$(mktemp -d)
  _tokens_entry m1 r1 1000 2000 1000 500 > "$t"
  printf '{"theme":"terminal-glitch","symbol_set":"ascii","spacing":"normal","style":"classic","separator":"|","blocks":["tokens"],"bar_width":6,"show_icons":true,"account_type":"subscription"}' > "$cfg"
  local out=$(printf '{"session_id":"fixture","transcript_path":"%s"}' "$t" \
    | env HOME="$home" CONFIG_OVERRIDE="$cfg" bash "$STATUSLINE" 2>/dev/null \
    | head -1 | sed 's/\x1b\[[0-9;]*m//g')
  rm -rf "$home"; rm -f "$cfg" "$t"
  check "test_legacy_tokens_maps_to_session: 舊 tokens 名稱仍可用" " [#] 4K \$0.0915 " "$out"
}

test_line2_rainbow_colors_differ() {
  # rainbow 下第二列的兩個區塊必須拿到不同背景色
  local t=$(mktemp) cfg=$(mktemp) home=$(mktemp -d)
  _tokens_entry m1 r1 1000 2000 1000 500 > "$t"
  printf '{"theme":"terminal-glitch","symbol_set":"ascii","spacing":"normal","style":"rainbow","separator":"","head":"sharp","tail":"sharp","blocks":["model"],"blocks_line2":["session","last_chat"],"bar_width":6,"show_icons":true,"account_type":"subscription"}' > "$cfg"
  local line2=$(printf '{"session_id":"fixture","transcript_path":"%s","model":{"display_name":"Opus 5"}}' "$t" \
    | env HOME="$home" CONFIG_OVERRIDE="$cfg" bash "$STATUSLINE" 2>/dev/null \
    | sed -n '2p')
  rm -rf "$home"; rm -f "$cfg" "$t"
  # 抽出所有 48;2;R;G;B 背景色碼，去重後應有 2 種以上
  local n=$(printf '%s' "$line2" | grep -o '48;2;[0-9]*;[0-9]*;[0-9]*' | sort -u | wc -l | tr -d ' ')
  if [ "$n" -ge 2 ]; then
    echo "✓ test_line2_rainbow_colors_differ: 兩區塊背景色不同（$n 種）"; ((PASS++))
  else
    echo "✗ test_line2_rainbow_colors_differ: 應有至少 2 種背景色，實際 $n"; ((FAIL++))
  fi
}
```

`main()` 中在 `test_session_without_cost_omits_dollar` 之後加入：

```bash
  test_line2_renders_second_row
  test_line2_absent_when_empty
  test_line2_absent_when_missing
  test_legacy_tokens_maps_to_session
  test_line2_rainbow_colors_differ
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `bash tests/test-statusline.sh 2>&1 | grep -E "line2|legacy"`
Expected: FAIL — `blocks_line2` 未被讀取，第二列不存在；`tokens` 名稱在 dispatch 中已無 case。

- [ ] **Step 3: 實作**

**4a.** `statusline.sh` 第 75 行之後加入：

```bash
cfg_blocks_line2=$("$JQ" -r '.blocks_line2 // [] | .[]' "$CONFIG")
```

**4b.** 把第 702 行到第 826 行（從 `# ── Assemble ─` 到 classic 組裝的收尾 `fi`）整段替換。新結構如下：

```bash
# ── Assemble ───────────────────────────────────────────────────────────────

# 舊 config 的 "tokens" 映射為 "session"，升級後不會壞掉。
_canon_block() {
  case "$1" in
    tokens) echo "session" ;;
    *)      echo "$1" ;;
  esac
}

# quota 帳號：把 rate_5h/rate_7d 的位置換成單一 spend 區塊，並在其前面
# 插入尚未用光的 credit。只作用於第一列。
apply_quota_substitution() {
  local out=() b
  local _spend_added=false
  for b in "$@"; do
    if [ "$b" = "rate_5h" ] || [ "$b" = "rate_7d" ]; then
      if ! $_spend_added; then out+=("spend"); _spend_added=true; fi
      continue
    fi
    out+=("$b")
  done
  if ! $_spend_added; then
    out=()
    for b in "$@"; do
      out+=("$b")
      [ "$b" = "context" ] && out+=("spend") && _spend_added=true
    done
    $_spend_added || out+=("spend")
  fi
  # one-time credit 區塊：存在且尚未用光（< 100%）時插在第一個 spend 之前
  # （credit → spend）；credit 用光後隱藏，只留 enterprise spend limit。
  if [ -n "$credit_pct" ] && awk -v p="$credit_pct" 'BEGIN{exit !(p < 100)}'; then
    local tmp=() inserted=false
    for b in "${out[@]}"; do
      if [ "$b" = "spend" ] && ! $inserted; then
        tmp+=("credit"); inserted=true
      fi
      tmp+=("$b")
    done
    out=("${tmp[@]}")
  fi
  printf '%s\n' "${out[@]}"
}

# 把一串區塊名稱渲染成一整列（含 rainbow 頭尾 glyph 或 classic 分隔符）。
# rainbow 的色彩循環以區塊在「該列」中的索引計算，因此每列都從 accent_1
# 重新起算 —— 第二列的 session/last_chat 會自然拿到不同顏色。
assemble_line() {
  local block_list=("$@")
  local line=""
  [ ${#block_list[@]} -eq 0 ] && return

  if $PL_MODE; then
    local PL_CYCLE=("$C_ACCENT_1" "$C_ACCENT_2" "$C_ACCENT_3")
    local prev_bg_hex="" idx block cur_bg_hex cur_fg_hex cur_bg cur_fg head_fg arrow_fg text
    for idx in "${!block_list[@]}"; do
      block="${block_list[$idx]}"
      cur_bg_hex="${PL_CYCLE[$((idx % 3))]}"
      cur_fg_hex=$(pl_block_fg "$block")
      cur_bg=$(hex_to_bg "$cur_bg_hex")
      cur_fg=$(hex_to_fg "$cur_fg_hex")

      if [ "$idx" -eq 0 ]; then
        if [ -n "$PL_HEAD_OPEN" ]; then
          head_fg=$(hex_to_fg "$cur_bg_hex")
          line+="${RESET}${head_fg}${PL_HEAD_OPEN}${RESET}"
        fi
      else
        if [ -n "$PL_TAIL_SEP" ]; then
          arrow_fg=$(hex_to_fg "$prev_bg_hex")
          line+="${RESET}${arrow_fg}${cur_bg}${PL_TAIL_SEP}${RESET}"
        fi
      fi

      text=""
      case "$block" in
        model)     text=$(block_text_model) ;;
        context)   text=$(block_text_pct "context" "$S_CTX" "CTX" "$used_pct") ;;
        rate_5h)   text=$(block_text_pct "rate_5h" "$S_5H" "5H" "$five_pct" "$five_reset") ;;
        rate_7d)   text=$(block_text_pct "rate_7d" "$S_7D" "7D" "$week_pct" "$week_reset") ;;
        directory) text=$(block_text_directory) ;;
        git)       text=$(block_text_git) ;;
        time)      text=$(block_text_time) ;;
        cost)      text=$(block_text_cost) ;;
        spend)     text=$(block_text_spend) ;;
        credit)    text=$(block_text_credit) ;;
        burn)      text=$(block_text_burn) ;;
        session)   text=$(block_text_session) ;;
        last_chat) text=$(block_text_last_chat) ;;
      esac
      line+="${cur_bg}${cur_fg}${BOLD}${text}${RESET}"
      prev_bg_hex="$cur_bg_hex"
    done

    if [ -n "$prev_bg_hex" ] && [ -n "$PL_TAIL_SEP" ]; then
      arrow_fg=$(hex_to_fg "$prev_bg_hex")
      line+="${RESET}${arrow_fg}${PL_TAIL_SEP}${RESET}"
    fi
  else
    local first=true block
    for block in "${block_list[@]}"; do
      if $first; then first=false; else line+="$SEP"; fi
      case "$block" in
        model)     line+=$(render_block_model) ;;
        context)   line+=$(render_block_context) ;;
        rate_5h)   line+=$(render_block_rate_5h) ;;
        rate_7d)   line+=$(render_block_rate_7d) ;;
        directory) line+=$(render_block_directory) ;;
        git)       line+=$(render_block_git) ;;
        time)      line+=$(render_block_time) ;;
        cost)      line+=$(render_block_cost) ;;
        spend)     line+=$(render_block_spend) ;;
        credit)    line+=$(render_block_credit) ;;
        burn)      line+=$(render_block_burn) ;;
        session)   line+=$(render_block_session) ;;
        last_chat) line+=$(render_block_last_chat) ;;
      esac
    done
  fi
  printf '%s' "$line"
}

line1_blocks=()
for b in $cfg_blocks; do line1_blocks+=("$(_canon_block "$b")"); done
if [ "$eff_account_type" = "quota" ] && [ ${#line1_blocks[@]} -gt 0 ]; then
  _subbed=()
  while IFS= read -r b; do [ -n "$b" ] && _subbed+=("$b"); done < <(apply_quota_substitution "${line1_blocks[@]}")
  line1_blocks=("${_subbed[@]}")
fi

line2_blocks=()
for b in $cfg_blocks_line2; do line2_blocks+=("$(_canon_block "$b")"); done

output=""
[ ${#line1_blocks[@]} -gt 0 ] && output=$(assemble_line "${line1_blocks[@]}")

line2=""
[ ${#line2_blocks[@]} -gt 0 ] && line2=$(assemble_line "${line2_blocks[@]}")
```

**4c.** 把檔尾的 turn usage 區段（原第 828-850 行，從 `# ── Turn usage (second line) ─` 到 `echo ""`）整段替換為：

```bash
# Ensure output ends with newline so subsequent prompts start on a new line
echo -e "$output"
if [ -n "$line2" ]; then
  echo -e "$line2"
fi
echo ""
```

**4d.** `config.json` 把 `blocks` 中的 `"tokens"` 移除，並新增 `blocks_line2`：

```json
{
  "theme": "terminal-glitch",
  "symbol_set": "nerd",
  "spacing": "ultra-compact",
  "style": "rainbow",
  "separator": "",
  "head": "rounded",
  "tail": "sharp",
  "blocks": ["model", "context", "rate_5h", "rate_7d", "cost"],
  "blocks_line2": ["session", "last_chat"],
  "bar_width": 6,
  "bar_filled": "●",
  "bar_empty": "○",
  "show_icons": true,
  "time_format": "24h",
  "account_type": "auto"
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `bash tests/test-statusline.sh`
Expected: `Results: N passed, 0 failed`

實機檢查（會用到真實 transcript）：

Run: `printf '{"session_id":"x","cwd":"'$PWD'","model":{"display_name":"Opus 5"}}' | bash statusline.sh`
Expected: 兩列輸出，第二列有兩個顏色不同的區塊

- [ ] **Step 5: Commit**

```bash
git add statusline.sh config.json tests/test-statusline.sh
git commit -m "feat: 第二列改由 blocks_line2 陣列驅動

把原本寫死在頂層的組裝邏輯抽成 assemble_line()，接受任意區塊名稱並
回傳整列已上色的字串。第一列讀 blocks、第二列讀 blocks_line2，兩列
共用同一套 rainbow / classic 渲染。開關第二列的欄位就是陣列增刪，順
序也可調。

quota 帳號的 spend/credit 替換邏輯抽成 apply_quota_substitution()，
只作用於第一列 —— 第二列沒有 rate_5h/rate_7d，本來就不受影響。

rainbow 的色彩循環以區塊在「該列」中的索引計算，第二列從 accent_1
重新起算，session 與 last_chat 因此自然拿到不同顏色，不需另外配色。

移除硬編碼的 turn_line 區段。它讀的是 repo 外部 Stop hook
（~/.claude/hooks/show-turn-usage.sh）寫的快取檔，使用者不裝那個
hook 就沒有第二列，且該 hook 把單價硬編成 Opus。改由 last_chat 區塊
從 transcript 直接讀，repo 自此自足。

_canon_block() 把舊 config 的 \"tokens\" 映射為 \"session\"，既有使
用者升級後第一列的 tokens 區塊會變成含金額的 session 區塊，不會消失
或報錯。blocks_line2 缺漏時不補預設值 —— 若補上，第一列映射而來的
session 會與第二列的 session 重複顯示。

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: 主題檔補上 session / last_chat

**Files:**
- Modify: `themes/*.json`（13 個）與 `themes/custom-example/*.json`
- Test: `tests/test-statusline.sh`

**Interfaces:**
- Produces: 每個主題檔的 `symbols.{nerd,unicode,ascii}.session`、`.last_chat`，以及 `blocks.session`、`blocks.last_chat`

- [ ] **Step 1: 寫失敗測試**

`tests/test-statusline.sh` 新增：

```bash
test_themes_have_usage_blocks() {
  local themes_dir="$PROJECT_DIR/themes"
  local missing=""
  while IFS= read -r f; do
    local m
    m=$(jq -r '
      [ (if .symbols.nerd.session    then empty else "symbols.nerd.session"    end),
        (if .symbols.unicode.session then empty else "symbols.unicode.session" end),
        (if .symbols.ascii.session   then empty else "symbols.ascii.session"   end),
        (if .symbols.nerd.last_chat    then empty else "symbols.nerd.last_chat"    end),
        (if .symbols.unicode.last_chat then empty else "symbols.unicode.last_chat" end),
        (if .symbols.ascii.last_chat   then empty else "symbols.ascii.last_chat"   end),
        (if .blocks.session   then empty else "blocks.session"   end),
        (if .blocks.last_chat then empty else "blocks.last_chat" end)
      ] | join(",")' "$f" 2>/dev/null)
    [ -n "$m" ] && missing="$missing $(basename "$f"):$m"
  done < <(find "$themes_dir" -name "*.json" -type f)

  if [ -z "$missing" ]; then
    echo "✓ test_themes_have_usage_blocks: 所有主題都有 session/last_chat 定義"; ((PASS++))
  else
    echo "✗ test_themes_have_usage_blocks: 缺漏 —$missing"; ((FAIL++))
  fi
}
```

`main()` 中在 `test_each_theme` 之後加入：

```bash
  test_themes_have_usage_blocks
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `bash tests/test-statusline.sh 2>&1 | grep themes_have_usage`
Expected: FAIL，列出全部 14 個主題檔的缺漏欄位

- [ ] **Step 3: 實作**

執行這個一次性腳本（跑完即可刪除，不需納入 repo）：

```bash
for f in themes/*.json themes/custom-example/*.json; do
  [ -f "$f" ] || continue
  tmp=$(mktemp)
  jq '
    .symbols.nerd.session      = (.symbols.nerd.tokens    // "󰊖")
  | .symbols.unicode.session   = (.symbols.unicode.tokens // "⇅")
  | .symbols.ascii.session     = (.symbols.ascii.tokens   // "[#]")
  | .symbols.nerd.last_chat    = "󰭹"
  | .symbols.unicode.last_chat = "⌯"
  | .symbols.ascii.last_chat   = "[L]"
  | .blocks.session   = {color: "accent_1", bg: "bg_panel", pl_bg: "accent_1", pl_fg: "bg_primary"}
  | .blocks.last_chat = {color: "accent_2", bg: "bg_panel", pl_bg: "accent_2", pl_fg: "bg_primary"}
  ' "$f" > "$tmp" && mv "$tmp" "$f"
done
```

註：既有的 `symbols.*.tokens` 與 `blocks.tokens` **保留不刪**，作為 Task 3 符號 fallback 與舊自訂主題的後備。

- [ ] **Step 4: 執行測試確認通過**

Run: `bash tests/test-statusline.sh 2>&1 | grep themes_have_usage`
Expected: `✓ test_themes_have_usage_blocks`

Run: `bash tests/test-statusline.sh`
Expected: `Results: N passed, 0 failed`

驗證 JSON 未損壞：

Run: `for f in themes/*.json themes/custom-example/*.json; do jq empty "$f" || echo "BROKEN: $f"; done`
Expected: 無輸出

- [ ] **Step 5: Commit**

```bash
git add themes/
git commit -m "feat(themes): 14 個主題補上 session 與 last_chat 定義

三組符號集（nerd / unicode / ascii）各補 session 與 last_chat。
session 沿用該主題既有的 tokens 符號值，視覺上不變；last_chat 新增
（nerd 󰭹 / unicode ⌯ / ascii [L]）。

顏色 session 用 accent_1、last_chat 用 accent_2，classic 樣式下兩欄
形成明顯色差。rainbow 樣式忽略 pl_bg 改用位置循環，該處已自然成立。

既有的 symbols.*.tokens 與 blocks.tokens 保留不刪，作為符號 fallback
與舊自訂主題的後備。

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: configure.sh 分列選單

**Files:**
- Modify: `configure.sh` —— `cur_blocks` 讀取約第 75 行、`sel_blocks` 初始化約第 95 與 111 行、`render_preview` 約第 277-330 行、`draw_preview` 約第 360-374 行、`step_blocks` 約第 464-575 行、主流程 `2) # Blocks` 分支約第 1101 行、存檔 heredoc 約第 1035 行與其後的完成畫面
- Test: `tests/test-configure.sh`

**Interfaces:**
- Consumes: Task 4 的 `blocks_line2` config 欄位
- Produces:
  - 全域 `cur_blocks_line2`、`sel_blocks_line2`（皆為逗號分隔字串）、`sel_blocks_line2_set`（布林旗標）
  - `step_blocks_line2()` — 回傳碼比照既有步驟：`0` 確認、`1` 上一步、`2` 重新開始
  - `render_preview` 產出的暫存 config 含 `blocks_line2` 欄位

**關鍵：`sel_blocks_line2` 不能用 `${sel_blocks_line2:-$cur_blocks_line2}` 取值。** 第二列允許「全部不選」，
而全部不選時 `sel_blocks_line2` 是空字串，`:-` 會誤退回舊設定，導致使用者關不掉第二列。因此另外用
`sel_blocks_line2_set` 旗標區分「尚未走過此步驟」與「走過且選了零個」。

- [ ] **Step 1: 寫失敗測試**

`tests/test-configure.sh` 沒有 `main()` —— 測試在檔尾的 `# ── Main ─` 區塊逐行呼叫，
每個測試以 `echo "▸ 名稱"` 開頭，並用 `pass "訊息"` / `fail "標籤" "原因"` 兩個輔助函式
記分。以下沿用該慣例。這支測試是**靜態檢查**（grep 原始碼），因為精靈需要 TTY 無法在
CI 中互動執行。

在 `test_startup_checks` 之後、`# ── Main ─` 之前新增：

```bash
# ── Test: second-line block configuration ────────────────────────────────
test_blocks_line2() {
  echo "▸ test_blocks_line2"

  if grep -q 'step_blocks_line2' "$CONFIGURE"; then
    pass "step_blocks_line2 present"
  else
    fail "step_blocks_line2" "not found"
  fi

  if grep -q 'line2_ids=("session" "last_chat")' "$CONFIGURE"; then
    pass "second line offers session and last_chat"
  else
    fail "line2_ids" "expected line2_ids=(\"session\" \"last_chat\")"
  fi

  if grep -q '"blocks_line2"' "$CONFIGURE"; then
    pass "blocks_line2 written to config"
  else
    fail "blocks_line2 field" "not emitted by render_preview or save"
  fi

  # 第二列允許零選取，故不可用 :- 回退 —— 空字串會被誤退回 cur_blocks_line2，
  # 使用者就永遠關不掉第二列
  if grep -q 'sel_blocks_line2_set' "$CONFIGURE"; then
    pass "sel_blocks_line2_set flag present"
  else
    fail "sel_blocks_line2_set" "not found — empty selection would fall back"
  fi

  if grep -q '\${sel_blocks_line2:-' "$CONFIGURE"; then
    fail "sel_blocks_line2 fallback" "must not use :- (breaks empty selection)"
  else
    pass "no :- fallback on sel_blocks_line2"
  fi

  # 第一列的 tokens 已由 session 取代
  if grep -q '"tokens"' "$CONFIGURE"; then
    fail "first line blocks" "still references tokens"
  else
    pass "first line no longer offers tokens"
  fi
}
```

在檔尾 `# ── Main ─` 區塊的 `test_startup_checks` 那一行之後加入：

```bash
test_blocks_line2
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `bash tests/test-configure.sh 2>&1 | sed -n '/test_blocks_line2/,$p'`
Expected: 六項中五項 `✗`（只有「no :- fallback」會誤過，因為該字串本來就還不存在）

- [ ] **Step 3: 實作**

**6a.** `configure.sh` 第 75 行附近讀取現有設定處，在 `cur_blocks=...` 之後加入：

```bash
  cur_blocks_line2=$("$JQ" -r '.blocks_line2 // [] | .[]' "$CONFIG" | tr '\n' ',' | sed 's/,$//')
```

在第 89 行附近（無設定檔時的預設值區段，`cur_blocks="model context ..."` 那行）之後加入：

```bash
  cur_blocks_line2="session,last_chat"
```

在第 95 與 111 行附近 `sel_blocks=""` 的兩處各補兩行：

```bash
sel_blocks_line2=""
sel_blocks_line2_set=false
```

**6b.** `step_blocks`（第 467 行）的 `block_ids` 移除 `tokens`：

```bash
  local block_ids=("model" "context" "rate_5h" "rate_7d" "cost" "directory" "git" "time")
```

同時把第 471 行的說明字串 `"tokens      — Session tokens used (excludes cache reads)"` 那一行**刪除**。
`block_descs` 與 `block_ids` 是一一對應的平行陣列，只刪其一會讓後面全部錯位。

**6c.** `render_preview`（第 277 行起）的既有 `blocks_json` 組裝迴圈（第 290-299 行）之後加入
第二列的 JSON 組裝。第二列不走位置參數 —— `render_preview` 有十餘個呼叫點，且 `draw_preview`
還會再轉一手，加參數要改動所有呼叫點：

```bash
  # 第二列改讀全域，與本函式已在讀 sel_symbols / cur_symbols 的做法一致。
  # 用 sel_blocks_line2_set 而非 :- ，否則「全部不選」會被誤退回 cur_blocks_line2。
  local blocks_line2_src
  if [ "${sel_blocks_line2_set:-false}" = true ]; then
    blocks_line2_src="$sel_blocks_line2"
  else
    blocks_line2_src="$cur_blocks_line2"
  fi
  local blocks_line2_json=""
  local first_l2=true
  local l2b
  IFS=',' read -ra l2_arr <<< "$blocks_line2_src"
  for l2b in "${l2_arr[@]}"; do
    [ -z "$l2b" ] && continue
    if $first_l2; then
      blocks_line2_json="\"$l2b\""
      first_l2=false
    else
      blocks_line2_json="$blocks_line2_json, \"$l2b\""
    fi
  done
```

並在寫出暫存 config 的 heredoc 中，`"blocks": [$blocks_json],` 那一行（第 317 行）之後加入：

```
  "blocks_line2": [$blocks_line2_json],
```

**6d.** `render_preview` 呼叫 `statusline.sh` 的地方（第 326 行附近，目前注入
`SESSION_TOKENS_OVERRIDE`），把注入的環境變數改成四個：

```bash
    SESSION_TOKENS_OVERRIDE="646951" \
    SESSION_COST_OVERRIDE="1.8931" \
    LAST_CHAT_TOKENS_OVERRIDE="163123" \
    LAST_CHAT_COST_OVERRIDE="0.3442" \
```

**6e.** `draw_preview`（第 360-374 行）目前只清一行。預覽現在可能有兩行，殘影會留在下一列。
把函式改為：

```bash
draw_preview() {
  local preview_row
  if [ "$1" = "--row" ]; then
    preview_row="$2"
    shift 2
  else
    preview_row=$((TERM_LINES - 4))
  fi
  tput cup "$preview_row" 0
  printf '\033[K\033[2mPreview:\033[0m\n'
  # 預覽可能有兩行（blocks_line2），先把兩列都清乾淨再畫，否則關掉第二列後會留殘影
  tput cup $((preview_row + 1)) 0
  printf '\033[K'
  tput cup $((preview_row + 2)) 0
  printf '\033[K'
  tput cup $((preview_row + 1)) 0
  render_preview "$@"
  printf '\033[K'
}
```

**6f.** 在 `step_blocks` 函式結尾的 `}` 之後新增第二列選單。它是 `step_blocks` 的變體，
沿用同一套 `draw_header` / `draw_footer` / `read_key` / `draw_preview` 與 0/1/2 回傳碼。
兩處差異：初始勾選狀態依現有設定而非全選；**不強制至少選一個**（全部不選就是關掉第二列）：

```bash
# 第二列的區塊選單。與 step_blocks 同屬精靈第 2 步，共用步驟編號。
step_blocks_line2() {
  draw_header 2 $TOTAL_STEPS "Which blocks on the second line? (Space to toggle)"

  local line2_ids=("session" "last_chat")
  local line2_descs=(
    "session     — This session's cumulative tokens + cost"
    "last_chat   — Last API call's tokens + cost"
  )

  # 依現有設定決定初始勾選，而非像第一列那樣全部預設開啟
  local existing
  if [ "${sel_blocks_line2_set:-false}" = true ]; then
    existing="$sel_blocks_line2"
  else
    existing="$cur_blocks_line2"
  fi
  local states=() i b found
  for i in "${!line2_ids[@]}"; do
    found="0"
    for b in $(echo "$existing" | tr ',' ' '); do
      [ "$b" = "${line2_ids[$i]}" ] && found="1"
    done
    states+=("$found")
  done

  # 進入此步驟即視為已設定，之後 render_preview 一律採用 sel_blocks_line2
  sel_blocks_line2_set=true

  _line2_commit() {
    sel_blocks_line2=""
    local first=true j
    for j in "${!line2_ids[@]}"; do
      if [ "${states[$j]}" = "1" ]; then
        if $first; then
          sel_blocks_line2="${line2_ids[$j]}"
          first=false
        else
          sel_blocks_line2="$sel_blocks_line2,${line2_ids[$j]}"
        fi
      fi
    done
  }
  _line2_commit

  draw_footer "j/k move · Space toggle · Enter confirm · b back · r restart · q quit"

  local cursor=0
  local count=${#line2_descs[@]}
  local preview_dirty=true

  while true; do
    for i in "${!line2_descs[@]}"; do
      tput cup $((5 + i)) 0
      local check_mark
      if [ "${states[$i]}" = "1" ]; then
        check_mark="\033[32m✔\033[0m"
      else
        check_mark="\033[2m✗\033[0m"
      fi
      if [ "$i" -eq "$cursor" ]; then
        printf '\033[K \033[1;36m❯\033[0m'"${check_mark}"' \033[1m%s\033[0m' "${line2_descs[$i]}"
      else
        printf '\033[K  '"${check_mark}"' \033[2m%s\033[0m' "${line2_descs[$i]}"
      fi
    done

    if $preview_dirty; then
      _line2_commit
      draw_preview --row $((5 + count + 1)) "$DEFAULT_THEME" "${sel_symbols:-$cur_symbols}" \
        "${sel_spacing:-$cur_spacing}" "${sel_separator:-$cur_separator}" \
        "${sel_blocks:-$(echo "$cur_blocks" | tr ' ' '\n' | tr '\n' ',' | sed 's/,$//')}" \
        "${sel_bar_width:-$cur_bar_width}" "${sel_time_format:-$cur_time_format}"
      preview_dirty=false
    fi

    read_key
    case "$KEY" in
      up)    (( cursor > 0 )) && (( cursor-- )) ;;
      down)  (( cursor < count - 1 )) && (( cursor++ )) ;;
      space)
        if [ "${states[$cursor]}" = "1" ]; then
          states[$cursor]="0"
        else
          states[$cursor]="1"
        fi
        preview_dirty=true
        ;;
      enter)
        # 第一列有「至少選一個」的檢查，這裡刻意沒有 —— 全部不選就是關掉第二列
        _line2_commit
        return 0
        ;;
      r) return 2 ;;
      b) return 1 ;;
      q) cleanup; exit 0 ;;
    esac
  done
}
```

**6g.** 主流程（第 1101 行附近）的 `2) # Blocks` 分支，把兩個步驟串起來 —— 比照第 3 步
（`step_spacing` → `step_bar_width` → `step_bar_style`）的既有做法。`step_blocks_line2`
回傳 1（上一步）時退回 `step_blocks` 重跑，因此 `current_step` 維持 2：

```bash
    2) # Blocks (line 1 + line 2)
      step_blocks
      rc=$?
      if [ $rc -eq 2 ]; then
        restart_wizard
      elif [ $rc -eq 0 ]; then
        step_blocks_line2
        rc=$?
        if [ $rc -eq 2 ]; then
          restart_wizard
        elif [ $rc -eq 0 ]; then
          current_step=3
        fi
        # rc=1（上一步）→ current_step 維持 2，迴圈重跑 step_blocks
      elif [ $rc -eq 1 ]; then
        current_step=1
      fi
      ;;
```

`TOTAL_STEPS` **維持 7**，其他步驟的 `draw_header` 編號都不用改 —— 同一 case 內串接的
子步驟共用步驟編號，這是本檔案既有的慣例（第 3 步的三個子步驟都寫 `draw_header 3`）。

**6h.** 存檔處（第 1035 行的 heredoc）在 `"blocks": [$blocks_json],` 之後加入
`"blocks_line2": [$blocks_line2_save],`，並在該函式內、heredoc 之前組出 `blocks_line2_save`：

```bash
  local blocks_line2_src_save
  if [ "${sel_blocks_line2_set:-false}" = true ]; then
    blocks_line2_src_save="$sel_blocks_line2"
  else
    blocks_line2_src_save="$cur_blocks_line2"
  fi
  local blocks_line2_save=""
  local first_l2s=true
  local l2sb
  IFS=',' read -ra l2s_arr <<< "$blocks_line2_src_save"
  for l2sb in "${l2s_arr[@]}"; do
    [ -z "$l2sb" ] && continue
    if $first_l2s; then
      blocks_line2_save="\"$l2sb\""
      first_l2s=false
    else
      blocks_line2_save="$blocks_line2_save, \"$l2sb\""
    fi
  done
```

同時把該函式結尾的完成畫面（第 1050 行附近的 `echo -e "\033[2mTheme:      \033[0m $sel_theme"`
那一段）加一行，讓使用者看得到第二列的結果：

```bash
  echo -e "\033[2mLine 2:     \033[0m ${blocks_line2_src_save:-<none>}"
```

- [ ] **Step 4: 執行測試確認通過**

Run: `bash tests/test-configure.sh`
Expected: `Results: N passed, 0 failed`

Run: `bash -n configure.sh`
Expected: 無輸出（語法正確）

手動走一次精靈，確認四件事：

Run: `bash configure.sh`
Expected:
1. 第 2 步選完第一列後，緊接著出現第二列選單（session / last_chat 兩項）
2. 勾選狀態反映現有 `config.json` 的 `blocks_line2`，不是全部預設開啟
3. 把兩項都取消勾選後，預覽只剩一列且**沒有殘影**，存檔後 `config.json` 的
   `blocks_line2` 是 `[]`
4. 在第二列選單按 `b` 會退回第一列選單，不會跳到第 1 步

Run: `jq '.blocks, .blocks_line2' config.json`
Expected: 第一列不含 `tokens`，第二列反映剛才的勾選

- [ ] **Step 5: Commit**

```bash
git add configure.sh tests/test-configure.sh
git commit -m "feat(configure): 區塊選單拆成第一列與第二列兩步

新增 step_blocks_line2，沿用既有的 draw_header / draw_footer /
read_key / draw_preview 與 0/1/2 回傳碼，串在主流程第 2 步之後，比照
第 3 步串接三個子步驟的做法。TOTAL_STEPS 維持 7 —— 同一 case 內的子
步驟共用步驟編號是本檔案既有慣例。

與第一列的兩處差異：初始勾選狀態依現有設定而非全部預設開啟；不強制
至少選一個，因為全部不選正是關掉第二列的方法。

也因為允許零選取，取值不能用 \${sel_blocks_line2:-\$cur_blocks_line2}
—— 空字串會被 :- 誤退回舊設定，使用者就關不掉第二列。改用
sel_blocks_line2_set 旗標區分「尚未走過此步驟」與「走過且選了零個」。

第一列的 block_ids 移除 tokens（已由 session 取代），block_descs 的
對應說明一併移除 —— 兩者是平行陣列，只刪其一會全部錯位。

render_preview 有十餘個呼叫點、draw_preview 還會再轉一手，因此第二列
不加位置參數，改讀全域，與該函式已在讀 sel_symbols 的做法一致。預覽
假資料補上三個新的 override 環境變數。

draw_preview 原本只清一行，預覽現在可能有兩行，關掉第二列後會留殘
影，故改為畫之前先清兩列。

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Codex adapter 對齊

**Files:**
- Modify: `adapters/codex/statusline.sh`（`codex_session_tokens` 約第 197-219 行、`fallback_config` 約第 252 行）、`adapters/codex/config.json`、`install-codex.sh:116`
- Test: `tests/adapters/codex/test-statusline.sh`

**Interfaces:**
- Consumes: Task 3 的 `block_text_session` 無金額降級行為
- Produces: Codex 的 `blocks` 陣列含 `session`（**第一列**，不使用 `blocks_line2`）

**背景：** `render_with_claude_style` 以 `awk 'NF { print; exit }'` 只取第一行輸出（Codex 的 `tui.status_line` 是單行），因此 Codex 完全不使用 `blocks_line2`；`session` 留在第一列。Codex 沒有 session 金額來源，`SESSION_COST_OVERRIDE` 不設，區塊自動降級成只顯示 token。

- [ ] **Step 1: 寫失敗測試**

`tests/adapters/codex/test-statusline.sh` 沒有 `main()`，測試是在檔尾逐行呼叫的；輔助函式是
`check_contains`（子字串比對）與 `_render_tokens`（跑整個 adapter）。以下改動全部沿用該慣例。

**先改 `_tokens_only_config`（第 182-184 行）**，blocks 換成新名稱：

```bash
_tokens_only_config() {
  printf '{"theme":"terminal-glitch","symbol_set":"ascii","spacing":"normal","style":"classic","separator":"|","blocks":["session"],"bar_width":6,"show_icons":true,"account_type":"subscription"}' > "$1"
}
```

**新增直接呼叫函式的輔助工具。** 既有兩個測試都靠 `_render_tokens` 的顯示字串斷言，但
`fmt_tokens` 會把 2,350,000 與 2,390,000 都印成 `2.3M`，「reasoning 是否重複計算」就再也
分辨不出來。因此改為直接呼叫函式、斷言精確整數。在 `_render_tokens` 之後加入：

```bash
# 抽出 codex_session_tokens 的函式定義單獨執行，斷言精確 token 數
# （經 fmt_tokens 格式化後會失去分辨力）
_codex_tokens_fn() {
  bash -c "$(awk '/^codex_session_tokens\(\)/,/^}/' "$RENDERER"); codex_session_tokens \"\$1\"" _ "$1"
}

check_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "✓ $label"; ((PASS++))
  else
    echo "✗ $label — expected: $expected, got: $actual"; ((FAIL++))
  fi
}
```

**改寫既有的 `test_session_tokens_from_real_fixture`**（第 203-208 行）。真實 fixture 是
`input_tokens 73866 / cached_input_tokens 56832 / output_tokens 1378`、無 `cache_write`：

```bash
test_session_tokens_from_real_fixture() {
  # 不再扣除 cached：73866 + 0(缺 cache_write，走 // 0) + 1378 = 75244 → 75K
  local out
  out=$(_render_tokens "$SCRIPT_DIR/fixtures/real-token-count-session.jsonl")
  check_contains "session tokens includes cached input" "75K" "$out"
}
```

**改寫既有的 `test_session_tokens_counts_cache_write_not_reasoning`**（第 210-228 行）整個函式：

```bash
test_session_tokens_counts_cache_write_not_reasoning() {
  # 2,000,000 + 250,000 + 100,000 = 2,350,000（cached 不再相減）
  # reasoning_output_tokens(40,000) 已含在 output_tokens 內，重複相加會變 2,390,000
  # 兩者經 fmt_tokens 都會印成 2.3M，故此處直接斷言整數
  local roll
  roll=$(mktemp)
  cat > "$roll" <<'JSON'
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":2000000,"cached_input_tokens":1500000,"cache_write_input_tokens":250000,"output_tokens":100000,"reasoning_output_tokens":40000,"total_tokens":2100000},"last_token_usage":{"total_tokens":51200},"model_context_window":258400}}}
JSON
  local out
  out=$(_codex_tokens_fn "$roll")
  rm -f "$roll"
  check_eq "session tokens = input + cache_write + output, no reasoning" "2350000" "$out"
}
```

**新增兩個測試：**

```bash
test_codex_tokens_includes_cached() {
  local f
  f=$(mktemp)
  # input_tokens 已內含 cached_input_tokens；不再相減
  # 100000 + 5000 + 20000 = 125000（若仍相減會得 45000）
  printf '{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100000,"cached_input_tokens":80000,"cache_write_input_tokens":5000,"output_tokens":20000}}}}\n' > "$f"
  local out
  out=$(_codex_tokens_fn "$f")
  rm -f "$f"
  check_eq "session tokens does not subtract cached_input_tokens" "125000" "$out"
}

test_codex_config_uses_session_block() {
  local bad=""
  grep -q '"session"' "$PROJECT_DIR/adapters/codex/config.json" || bad="config.json 缺 session"
  grep -q '"tokens"'  "$PROJECT_DIR/adapters/codex/config.json" && bad="$bad; config.json 仍含 tokens"
  grep -q '"session"' "$PROJECT_DIR/adapters/codex/statusline.sh" || bad="$bad; fallback_config 缺 session"
  grep -q '"session"' "$PROJECT_DIR/install-codex.sh" || bad="$bad; install-codex.sh 缺 session"
  if [ -z "$bad" ]; then
    echo "✓ codex blocks use session instead of tokens"; ((PASS++))
  else
    echo "✗ codex blocks not migrated — $bad"; ((FAIL++))
  fi
}
```

**改既有的 `test_session_tokens_degraded_without_token_count`**（第 230-234 行）—— 降級字串不變
（`[#] --`），但 ascii 的 session 符號來自主題的 `symbols.ascii.session`，Task 5 已設為與
`tokens` 相同的 `[#]`，故此測試不需改動。確認它仍通過即可。

在檔尾的測試呼叫清單中，`test_session_tokens_counts_cache_write_not_reasoning` 那一行之後加入：

```bash
test_codex_tokens_includes_cached
test_codex_config_uses_session_block
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `bash tests/adapters/codex/test-statusline.sh 2>&1 | grep -E "cached|session block|reasoning"`
Expected: FAIL —— `codex_session_tokens` 仍在相減（得 45000 / 850000），且 config 仍是 `tokens`

- [ ] **Step 3: 實作**

**7a.** `adapters/codex/statusline.sh` 把 `codex_session_tokens()` 的註解與 awk 段落改為：

```bash
# Session-cumulative tokens, including cache reads — mirrors the Claude side's
# input + cache_creation + cache_read + output. Codex's total_token_usage already
# accumulates over the session, so no summing or dedupe is needed here.
#
# Field semantics verified against a real rollout:
#   total_tokens == input_tokens + output_tokens
# so input_tokens already CONTAINS cached_input_tokens — we no longer subtract it,
# because the Claude side now counts cache reads too. reasoning_output_tokens is
# already inside output_tokens (adding it separately would double-count).
codex_session_tokens() {
  local file="$1"
  [ -n "$file" ] && [ -f "$file" ] || return 0

  jq -r '
    select(type == "object" and .type == "event_msg" and .payload.type == "token_count")
    | .payload.info.total_token_usage
    | [
        (.input_tokens // 0),
        (.cache_write_input_tokens // 0),
        (.output_tokens // 0)
      ]
    | @tsv
  ' "$file" 2>/dev/null | tail -1 | awk '
    NF == 3 { printf "%d", $1 + $2 + $3 }
  '
  return 0
}
```

**7b.** `fallback_config()` 的 blocks 把 `"tokens"` 換成 `"session"`：

```
  "blocks": ["model", "context", "session", "rate_5h", "rate_7d", "cost", "burn", "git", "time"],
```

**7c.** `adapters/codex/config.json` 的 `blocks` 陣列把 `"tokens"` 換成 `"session"`。

**7d.** `install-codex.sh:116` 把 `"tokens"` 換成 `"session"`：

```
    blocks: ["model", "context", "session", "rate_5h", "rate_7d", "cost", "burn", "git", "time"],
```

**7e.** `render_with_claude_style` 中的 `awk 'NF { print; exit }'` **維持不動**，`SESSION_COST_OVERRIDE` **不新增**——Codex 沒有 session 金額來源，區塊靠 Task 3 的降級規則只印 token。

- [ ] **Step 4: 執行測試確認通過**

Run: `bash tests/adapters/codex/test-statusline.sh`
Expected: `Results: N passed, 0 failed`

Run: `bash tests/test-statusline.sh`
Expected: `Results: N passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add adapters/codex/ install-codex.sh tests/adapters/codex/test-statusline.sh
git commit -m "feat(codex): 對齊新的 session 區塊與含快取的 token 定義

codex_session_tokens 原本刻意扣除 cached_input_tokens，以對齊 Claude
側「排除 cache_read」的舊定義。Claude 側已改為含快取讀取，此處也不
再相減，兩邊定義重新一致。

blocks 陣列把 tokens 換成 session（config.json、fallback_config、
install-codex.sh 三處同步）。session 留在第一列，不使用 blocks_line2
—— render_with_claude_style 以 awk 只取第一行輸出，因為 Codex 的
tui.status_line 是單行。

不注入 SESSION_COST_OVERRIDE：Codex 沒有 session 層級的金額來源
（ccusage codex 給的是日總額）。session 區塊靠既有的降級規則只顯示
token、不顯示 \$，last_chat 則不會出現。

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: 文件同步

**Files:**
- Modify: `README.md`、`docs/README.zh-TW.md`、`LOG.md`

**Interfaces:**
- Consumes: 前七個 task 的全部行為

- [ ] **Step 1: 更新英文 README**

`README.md` 第 82 行把 tokens 那列替換為兩列：

```markdown
| session | Cumulative tokens and cost for the current session (e.g. `646K $1.89`) |
| last_chat | Tokens and cost of the most recent API call (e.g. `163K $0.3442`) |
```

第 93-100 行的 tokens 說明段落整段替換為：

```markdown
The **session** and **last_chat** blocks live on the second line by default. Both
count tokens the same way:

```
input_tokens + cache_creation_input_tokens + cache_read_input_tokens + output_tokens
```

`cache_read_input_tokens` **is included**. Every turn re-reads the whole context, so
this number grows roughly with `turns × context size` — it answers "how many billed
tokens has this session run through", not "how much context am I using right now"
(that's the `context` block). Cache reads account for roughly half the actual spend,
so excluding them would leave the token count and the dollar figure unable to
corroborate each other.

Cost is priced per model family (Opus / Sonnet / Haiku) from the message's own
`model` field, so switching models mid-session is priced correctly.

Configure which blocks appear on each line with `blocks` and `blocks_line2`:

```json
"blocks":       ["model", "context", "rate_5h", "rate_7d", "cost"],
"blocks_line2": ["session", "last_chat"]
```

An empty or absent `blocks_line2` means no second line. Upgrading from an older
version: a `"tokens"` entry in `blocks` is treated as `"session"`, but you'll need to
re-run `configure.sh` to get the second line.
```

- [ ] **Step 2: 更新繁中 README**

`docs/README.zh-TW.md` 第 77 行把 tokens 那列替換為兩列：

```markdown
| session | 本次 session 的累計 token 與花費（例如 `646K $1.89`） |
| last_chat | 最後一次 API 呼叫的 token 與花費（例如 `163K $0.3442`） |
```

第 88-94 行的 tokens 說明段落整段替換為：

```markdown
**session** 與 **last_chat** 兩個區塊預設放在第二列，token 的計算方式相同：

```
input_tokens + cache_creation_input_tokens + cache_read_input_tokens + output_tokens
```

`cache_read_input_tokens` **有計入**。每一輪都會重讀整個 context，所以這個數字大致隨
「輪數 × context 大小」成長 —— 它回答的是「這個 session 累計跑了多少計費 token」，而不
是「我現在佔用多少 context」（後者由 `context` 區塊負責）。快取讀取約佔實際花費的一半，
若把它排除，token 數與金額就無法互相印證。

金額依訊息自身的 `model` 欄位按家族（Opus / Sonnet / Haiku）分價，session 中途換模型也
能算對。

以 `blocks` 與 `blocks_line2` 設定各列要顯示哪些區塊：

```json
"blocks":       ["model", "context", "rate_5h", "rate_7d", "cost"],
"blocks_line2": ["session", "last_chat"]
```

`blocks_line2` 為空或缺漏就不顯示第二列。從舊版升級：`blocks` 中的 `"tokens"` 會被視為
`"session"`，但要重跑 `configure.sh` 才會有第二列。
```

- [ ] **Step 3: 更新 LOG.md**

在 `# Changelog` 之後、`## 2026-07-30` 之前插入：

```markdown
## 2026-07-31

### 重構：第二列改為 session + last_chat 兩個獨立區塊

- **需求**：第一列的 `tokens` 沒有金額；第二列是硬編碼的 `Last Chat cache:161,065 in:622 out:1,212 $0.3442`，四個數字擠在一起、無法開關、無法調色。使用者要兩者都簡化成「總 token + 金額」、分成不同顏色的獨立欄位、並可在 configure 開關
- **token 定義改變**：改為 `input + cache_creation + cache_read + output`，**含 cache_read**，推翻 2026-07-30 tokens 區塊「排除 cache_read」的設計。理由是 cache_read 佔實際花費約一半（實測某 session：cache_read $0.91 / 總額 $1.89），金額既然必須含它，token 也含才對得起來。代價是數字隨「輪數 × context 大小」近似平方成長，但此欄位語意本就是「累計計費量」而非「當前 context 佔用」（後者由 `context` 區塊負責）
- **statusline.sh 資料層**：`_count_session_tokens()` 換成 `_scan_transcript()`，單次掃描產出 `session_tokens|session_cost|last_tokens|last_cost` 四個值。定價沿用 `_refresh_cost` 既有的 `price()` 表按 model 家族分價
  - 快取檔 `session-tokens-<session_id>` 格式由 `<mtime>|<total>` 擴充為五欄位；讀取時最後一欄為空即視為舊格式 cache miss 重算，使用者不需手動清快取
  - 新增 `SESSION_COST_OVERRIDE`、`LAST_CHAT_TOKENS_OVERRIDE`、`LAST_CHAT_COST_OVERRIDE` 三個環境變數
- **statusline.sh 渲染層**：新增 `fmt_price()`（`≥1` 兩位小數、`<1` 四位小數，避免 `$0.3442` 塌成 `$0.00`）、`block_text_session` / `block_text_last_chat` / `render_block_session` / `render_block_last_chat`，共用 `_usage_text` 與 `_render_usage` 兩個內部函式
  - 三段降級：無 token → `--`（dim 色）；有 token 無金額 → 只印 token（Codex 靠這條）；兩者皆有 → 完整輸出
- **statusline.sh 組裝層**：頂層的組裝邏輯抽成 `assemble_line()`，第一列讀 `blocks`、第二列讀 `blocks_line2`，共用 rainbow / classic 渲染。quota 帳號的 spend/credit 替換抽成 `apply_quota_substitution()`，只作用於第一列
  - rainbow 的 `PL_CYCLE` 以區塊在**該列**中的索引計算，第二列從 `accent_1` 重新起算，兩欄自然有色差，不需另外配色
  - `_canon_block()` 把舊 config 的 `"tokens"` 映射為 `"session"`。`blocks_line2` 缺漏時**不補預設值** —— 若補上，第一列映射而來的 session 會與第二列重複
- **移除外部 hook 依賴**：刪除硬編碼的 `turn_line` 區段。它讀的是 repo 外部 `~/.claude/hooks/show-turn-usage.sh`（Stop hook）寫的快取檔，使用者不裝該 hook 就沒有第二列，且該 hook 把單價硬編成 Opus（切到 Sonnet 會多算約 5 倍）。改由 `last_chat` 從 transcript 直接讀，repo 自此自足
- **主題**：14 個主題檔補上 `symbols.{nerd,unicode,ascii}.{session,last_chat}` 與 `blocks.{session,last_chat}`。session 沿用該主題既有的 tokens 符號值，last_chat 新增（nerd `󰭹` / unicode `⌯` / ascii `[L]`）。舊的 `symbols.*.tokens` 與 `blocks.tokens` 保留作 fallback
- **configure.sh**：區塊選單拆成第一列與第二列兩步，新增 `step_blocks_line2`。`render_preview` 有十餘個呼叫點，第二列因此不加位置參數，改讀全域 `sel_blocks_line2` / `cur_blocks_line2`
- **adapters/codex**：`codex_session_tokens` 不再扣除 `cached_input_tokens`，與 Claude 側新定義一致。blocks 把 `tokens` 換成 `session`，**留在第一列** —— `render_with_claude_style` 以 `awk 'NF { print; exit }'` 只取第一行（Codex 的 `tui.status_line` 是單行），故 Codex 不使用 `blocks_line2`。不注入 `SESSION_COST_OVERRIDE`（Codex 沒有 session 層級金額來源），session 區塊降級成只顯示 token
- **設計文件**：`docs/superpowers/specs/2026-07-31-line2-session-lastchat-design.md`
```

- [ ] **Step 4: 驗證**

Run: `bash tests/test-statusline.sh && bash tests/test-configure.sh && bash tests/adapters/codex/test-statusline.sh`
Expected: 三份測試皆 `Results: N passed, 0 failed`

確認兩份 README 的區塊表格內容一致（欄位名稱與數量）：

Run: `grep -c '^| ' README.md docs/README.zh-TW.md`
Expected: 兩者的表格列數差異與變更前相同（此次兩邊都是 -1 +2）

- [ ] **Step 5: Commit**

```bash
git add README.md docs/README.zh-TW.md LOG.md
git commit -m "docs: 同步 session/last_chat 雙欄的說明與變更紀錄

兩份 README（英文與繁中）的區塊表格把 tokens 一列換成 session 與
last_chat 兩列，說明段落改寫 token 定義為含 cache_read，並補上
blocks_line2 的設定範例與升級注意事項。

LOG.md 記錄本次重構的完整決策脈絡：為何 token 定義改為含 cache_read
並推翻前一份設計、為何移除對 repo 外部 Stop hook 的依賴、為何
blocks_line2 缺漏時不補預設值、以及 Codex 為何不使用 blocks_line2。

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review 紀錄

**Spec 覆蓋檢查：**

| Spec 段落 | 對應 Task |
|---|---|
| 顯示格式（`fmt_price`） | Task 1 |
| 資料層（單次掃描、快取擴充、override） | Task 2 |
| 渲染層（四個區塊函式、dispatch case、三段降級） | Task 3 |
| 渲染層（兩列組裝、移除 turn_line） | Task 4 |
| 設定（`blocks_line2`、`tokens` 向後相容、缺漏不補預設） | Task 4 |
| 主題（14 檔案的顏色與符號、rainbow 位置循環） | Task 5 |
| configure.sh（分列選單、預覽假資料、零選取） | Task 6 |
| Codex adapter（含快取的 token、blocks 遷移、不設金額 override） | Task 7 |
| 測試（格式邊界、解析、快取、渲染、相容、主題完整性） | 各 Task 的 Step 1 |
| 文件（雙語 README + LOG） | Task 8 |

**寫完後對照原始碼查出並修正的問題：**

1. **測試期望值算錯四處** —— `test_tokens_dedupes_retried_request`（$0.9900 → $0.9150）、
   `test_tokens_resolves_by_session_id`（$44.90 → $41.98）、`test_session_includes_cache_read`
   （$7.55 → $7.59）、`test_line2_renders_second_row` 與 `test_legacy_tokens_maps_to_session`
   （$0.0805 → $0.0915）。每處都補上算式註解。
2. **classic 分隔符的空白數** —— 實測 `SEP` 是 `" | "`，與區塊自帶的前後空白相加後是
   `"  |  "`（各兩個空格），`test_line2_renders_second_row` 的期望字串已依實測修正。
3. **Task 2 Step 4 的驗證期望值** —— 原本寫死一個 jq 浮點輸出，改為只驗證前綴與欄位數，
   避免因浮點尾數差異而誤判。
4. **Task 6 的選單函式完全不符既有慣例** —— 原本自己發明了一套 `tput ed` + `read -rsn1`
   的鍵盤處理。改為沿用檔案既有的 `draw_header` / `draw_footer` / `read_key` / `$KEY` /
   `draw_preview` 與 0/1/2 回傳碼。
5. **`TOTAL_STEPS` 不需要加一** —— 原本要求把後續所有 `draw_header` 編號往後推。實際查證
   後發現同一 case 內串接的子步驟共用步驟編號是既有慣例（第 3 步的三個子步驟都寫
   `draw_header 3`），故 `step_blocks_line2` 用 `draw_header 2`，其他步驟一律不動。
6. **零選取會被 `:-` 吃掉** —— 第二列允許全部不選（那就是關掉第二列的方法），但
   `${sel_blocks_line2:-$cur_blocks_line2}` 會把空字串誤退回舊設定，使用者永遠關不掉。
   改用 `sel_blocks_line2_set` 旗標，並加測試防止 `:-` 寫法回流。
7. **`draw_preview` 只清一行** —— 預覽現在可能有兩行，關掉第二列後會留殘影。Task 6 補上
   6e 修正。
8. **Codex 的 reasoning 重複計算測試會失去分辨力** —— 改成含快取後，2,350,000 與
   2,390,000 經 `fmt_tokens` 都印成 `2.3M`，原本靠顯示字串的斷言再也分不出來。改為直接
   呼叫 `codex_session_tokens` 斷言精確整數，並新增 `check_eq` 與 `_codex_tokens_fn` 兩個
   輔助函式。
9. **兩支測試檔的記分慣例不同** —— `tests/test-configure.sh` 用 `pass` / `fail` 並以
   `echo "▸ 名稱"` 開頭且無 `main()`；`tests/adapters/codex/test-statusline.sh` 用
   `check_contains` 且在檔尾逐行呼叫。Task 6 與 Task 7 的測試已各自改為對應慣例。
10. **Codex 的 `_tokens_only_config` 也要改** —— 它的 blocks 寫死 `["tokens"]`，不改的話
    Task 7 的既有測試會全部落到 `_canon_block` 的相容路徑上，測不到真正的遷移。

**型別 / 命名一致性檢查：**

- `session_tokens` / `session_cost` / `last_tokens` / `last_cost` —— Task 2 定義，Task 3 使用
- `_usage_text` / `_render_usage` —— Task 3 定義並在同一 task 內使用
- `assemble_line` / `apply_quota_substitution` / `_canon_block` —— Task 4 定義並使用
- `sel_blocks_line2` / `cur_blocks_line2` / `sel_blocks_line2_set` —— Task 6 定義，並在同一
  task 內的 `render_preview`、`draw_preview` 呼叫端、`step_blocks_line2`、存檔處一致使用
- `line2_ids` —— Task 6 的程式碼與其測試的 grep 字串一致
- `S_SESSION` / `S_LAST_CHAT` —— Task 3 定義並使用
- `_codex_tokens_fn` / `check_eq` —— Task 7 定義並在同一 task 內使用
- 四個 override 環境變數（`SESSION_TOKENS_OVERRIDE`、`SESSION_COST_OVERRIDE`、
  `LAST_CHAT_TOKENS_OVERRIDE`、`LAST_CHAT_COST_OVERRIDE`）在 Task 2、Task 6、Task 7 中拼寫一致

**已知的執行順序限制：** Task 2 的 Step 4 只驗證資料層，因為 `session` 區塊的 dispatch case
要到 Task 3 才存在。Task 2 與 Task 3 之間測試不會全綠，這在 Task 2 的 Step 4 已明確標註。
