# Changelog

## 2026-08-01

### 修正：patched Codex 安裝器缺少 git／cargo 前置檢查，會編到一半才死

- **問題**：承上一則文件修正——`adapters/codex/install-patched.sh` 直接呼叫 `git clone` 與 `cargo build`，卻只檢查 `codex` binary 是否存在。缺 `cargo` 的機器會先 clone 完整份 Codex 原始碼、套完 patch，才在 `cargo build` 那行以 `command not found` 死掉，留下一個沒用的 source cache
- **改動**：在印出 plan 之前收集 `MISSING_TOOLS`（`git`、`cargo`），並在 dry-run 分支之後、`clone` 之前硬性擋下。錯誤訊息會指名缺哪個工具並附上對應提示（cargo → https://rustup.rs、git → 套件管理器）。plan 區塊也多印一行 `requires: git, cargo (Rust toolchain)`
- **dry-run 刻意不失敗**：dry-run 的用途是「告訴我會發生什麼」，所以缺工具時印出同一份警告後仍 exit 0。這樣使用者可以先跑 `--dry-run` 確認環境，而不是被擋在門外
- **新增 5 個測試**（`tests/adapters/codex/test-install-patched.sh` 從 13 → 23 個斷言）：
  - `test_missing_cargo_aborts_before_touching_anything`：驗 exit 1、訊息指名 cargo 與 rustup、且**沒有**跑過 git、沒有 source cache、沒有產出 binary
  - `test_dry_run_warns_about_missing_cargo_without_failing`：驗 exit 0 且仍印警告
  - `test_plan_lists_required_tools`：驗 plan 有列出需求
  - **測試手法**：「cargo 不存在」必須是 fixture 的性質而非開發機的性質，否則有裝 Rust 的機器根本測不到。作法是造一個只含 `dirname` 符號連結與假 `git` 的 `PATH`，完全排除系統路徑。連帶要把 `bash` 先用 `command -v` 解析成絕對路徑再呼叫，否則連 `bash` 都找不到（第一版就踩到，6 個測試以 status 127 失敗）
  - **突變測試**：把 preflight 區塊整段移除後重跑，3 個斷言如期轉紅（且失敗狀態碼是 127 —— 正是這次要消滅的「跑到一半才死」）
- **測試**：全套 276 passed / 0 failed
- **兩份 README 同步更新**：把「沒有前置檢查、會在執行到一半失敗」改寫為現在的行為，並補上「想先驗環境就跑 `./adapters/codex/install-patched.sh --dry-run`」
- **順帶發現、未修**：`install-codex.sh --patched --dry-run` 只印出 `would run: … --dry-run` 與 `delegates: …`，**並不會真的執行**子安裝器的 dry-run，所以它跑不到新的前置檢查。措辭有誤導（寫著 delegates 卻沒 delegate），但屬既有行為、不在這次範圍內，因此 README 改為指向真正會跑檢查的 `adapters/codex/install-patched.sh --dry-run`

### 文件：補齊 Codex 安裝／解除安裝的三個致命缺口

- **起因**：使用者要在另一台電腦安裝，問「`../cyberpunk-statusline-marketplace` 是給 Claude 用的嗎、Codex 怎麼辦」。順帶釐清那個本地目錄已是廢棄的舊 clone——GitHub 上該 repo 早已改名為 `claude-cyberpunk-statusline`（舊網址只是 redirect，兩邊 `git ls-remote` 的 HEAD 都是 `98a0530`），而主 repo 在 `7a3a088` 就清掉了 marketplace/plugin 結構。兩份 README 都沒有 marketplace 殘留，但 Codex 那段有真缺口
- **缺口一：`--patched` 完全沒寫前置需求**（最嚴重）。`adapters/codex/install-patched.sh` 實際會 clone Codex 原始碼（釘在 `rust-v0.142.5`）、套 patch、跑 `cargo build --release`，也就是需要 **git + Rust toolchain**，而腳本裡**沒有 `command -v cargo` 前置檢查**，缺 cargo 會在執行到一半才以 `command not found` 死掉。README 原文只寫「請明確指定 patched binary 路徑」，一個字都沒提。連帶補上：產物是 `~/.local/bin/codex-cyberpunk` 而**不覆蓋**原本的 `codex`、會詢問是否往 `~/.zshrc` 加 alias（僅 zsh）、以及 `--theme` / `--official` / `--patched` / `--alias` / `--no-alias` / `--dry-run` 這些從未被記錄的選項
- **缺口二：解除安裝章節漏掉 Codex**。`uninstall.sh` 只清 Claude Code 的 `statusLine`，完全不碰 `~/.codex/config.toml` 也不刪 `codex-cyberpunk`，但 README 只給那一行指令，讀起來像「跑一個就乾淨」。改成 Claude／Codex 兩小節，並明確標出 `adapters/codex/uninstall-patched.sh` **也還原不了**的兩樣東西：official 模式寫進 config.toml 的 `tui.status_line` items、以及 `.zshrc` 的 alias（讀 uninstall-patched.sh 原始碼確認它只移除指向本專案的 `status_line_command` 與那支 binary）
- **缺口三：環境需求只列 Claude Code**，但文件有一半在講 Codex。補上 Codex CLI（選用），並在清單下方獨立說明 patched 模式的 git + cargo 需求
- **結構修正**：原本「Install Codex」沒有編號、夾在 `2.` 與 `3.` 之間，看起來像 Claude 安裝的子步驟——改為 `3. Install for Codex (optional)`，重新啟動順延為 `4.` 並補上 Codex；patched 內容降為 `####` 子節並連到 `docs/codex-patched-footer.md`（該文件先前沒有任何地方連結得到）
- **繁中版另外修兩處**：補上缺漏的語言切換連結（英文版第 3 行有，繁中版沒有，兩邊不對稱）；修正 `--patched` 那句的誤譯——原文 "opt into the patched-binary **path** explicitly" 的 path 指的是「路線／做法」，被譯成「請明確指定 patched binary 路徑」，會讓人以為要傳一個檔案路徑參數
- **小修**：`model` 區塊範例從 `Opus 4.6` 更新為 `Opus 5`（兩份）
- **驗證**：兩份 README 標題數皆為 22 且逐節對齊；錨點連結依 GitHub slug 規則檢查過（繁中版 `#3-安裝-codex選用`，全形括號會被 slugger 去除）；全套測試維持全綠

### 功能：定價每日自動更新，內建表降級為 fallback 並加上對帳測試

- **動機**：承下一則的定價修正——問題不是「價格漂移」而是「一開始就填錯且一個月沒人發現」。使用者要求用極低成本的方式定期自動校正
- **來源調查**（三個候選，兩個死路）：
  - Anthropic Models API `/v1/models/claude-opus-5` → 實測回傳 `capabilities`、`max_input_tokens` 等，**沒有任何價格欄位**
  - 官方 `platform.claude.com/docs/en/pricing.md` → **HTTP 404**
  - **LiteLLM 的 `model_prices_and_context_window.json`** → 可用，且回傳的 Opus 5 數字（in 5 / out 25 / cr 0.5 / cw 6.25 / cw-1h 10）與手動修正後的表**逐項吻合**，等於獨立驗證。專案的 daily cost 主路徑 `ccusage` 抓的本來就是這份，改用它反而讓兩條成本路徑對齊
- **新增 `core/fetch-pricing.sh`**：抓上游 → 篩出 Anthropic 的 `claude-*` → 換算成每 1M token 的 `{i, o, cw5, cw1h, cr}`。上游 1.67MB，抽完只剩 **1603 bytes / 23 個模型**
  - **sanity bound**：input 必須 > 0 且 ≤ $1000/1M；cache write 不得超過 input 的 2.5 倍。實測擋下 `claude-3-haiku-20240307`——上游把它的 1h cache write 標成 $6（input 只有 $0.25，24 倍），明顯是壞資料。悄悄採用錯價比用已知過期的內建值更糟，所以寧可濾掉
  - 任何失敗都 exit≠0 且不輸出，讓呼叫端的 `>tmp && mv` 保住舊快取
  - **踩到的坑**：初版把 1.67MB payload 讀進 shell 變數再做 `${raw//[[:space:]]/}` 檢查空白——bash 對這種大小的字串做全域替換會退化成病態慢，實測**掛住超過兩分鐘**。改成全程走暫存檔、由 jq 直接讀檔，總耗時降到 939ms。（`core/fetch-usage.sh` 用同樣寫法沒事，因為它的回應只有幾百 bytes）
- **statusline.sh 接線**：
  - `PRICING_CACHE`（24h TTL）+ `PRICING_ATTEMPT`（1h 重試下限，避免持續失敗時每個 prompt 都 spawn 一次 curl）
  - 背景 refresh 沿用既有 `USAGE_CACHE` 的 `&` + `disown` 模式，渲染路徑只讀那份 1.6KB 快取
  - `price()` 改成先查 `$PRICES`，查不到才落回改名為 `builtin()` 的內建表；新增 `norm()` 在上游缺 cache write／cache read 欄位時用官方倍率補（5m ×1.25、1h ×2、cr ×0.1）
  - `PRICING_CACHE_OVERRIDE` 供測試注入，且設了就不觸發背景抓取
- **實測驗證**（四條路徑）：注入 10 倍價格表 → `$15.15`（恰為 `$1.51` 的 10 倍，證明 `$PRICES` 真的生效）；缺 cw/cr → `norm()` 補值後與內建表同值；壞掉的快取 → 退回內建表；空表 `{}` → 退回內建表。冷啟動（無快取）不阻塞，背景 3 秒內寫入快取
- **新增 `test_builtin_pricing_matches_upstream`**：拿 `builtin()` 跟上游對帳。門檻設「差距達 2 倍才失敗」而非要求相等——上游會反映促銷價（Sonnet 5 到 2026-08-31 是 $2/$10，相對標準價 $3/$15 為 1.5 倍），內建表刻意保守放長期標準價；要抓的是「整個世代過時」這種量級錯誤
  - **這個測試第一版是假綠的**：寫成 `jq -cn "$JQ_PRICE_FN" 'builtin(...)'`，jq 把第二個參數當**檔名**而非 filter，於是每次都失敗回空字串，比對變成空對空而恆真。是突變測試（把內建表改回 $15/$75，測試卻照樣通過）才抓出來。改成 `eval` 出變數後 `jq -cn "$JQ_PRICE_FN builtin(\"$m\")"`，並補上「抽不到值就算失敗」的防呆。重跑突變測試確認會紅，且報出的正是那次 bug 的內容
  - 測試框架新增 `skip()` 與 `SKIP` 計數；離線時（實測用無效 URL）乾淨跳過而非失敗，且在結果行顯示 `1 skipped`，避免永久跳過被藏起來
- **修好自己造成的測試副作用**：17 個測試用 `home=$(mktemp -d)`，那會讓 `COST_CACHE_DIR` 指向空目錄，於是**每一個都以為快取過期、各自 spawn 一次 1.67MB 背景下載**，整套從秒級變成 >120s 還狂敲上游。在測試檔頂端 `export PRICING_CACHE_OVERRIDE=/dev/null`：非空字串停掉背景抓取，而 `-s /dev/null` 為假讓 `PRICING_JSON` 維持 `{}`，剛好強制所有斷言走內建表——正是它們要驗的東西。整套降回 56s
- **未做（刻意）**：使用者原本提議「每個模型記最後更新時間、切換模型時判斷是否超過 24h」。一次下載就拿到全部 23 個模型，per-model 時間戳沒有好處；而且「切換模型」當觸發點不可靠——可能一週不切（永不更新）也可能一小時切二十次。單一檔案 mtime + 24h TTL 更簡單可靠
- **已知限制**：`session-tokens-*` 快取以 transcript mtime 為鍵，若價格更新但 transcript 沒動，會短暫沿用舊金額。實際使用中 transcript 每輪都變，影響可忽略
- **測試**：全綠——test-statusline 71/0、test-configure 21/0、codex adapter 五支 82/0、core 三支 44/0、tab-state 48 pass

### 修正：定價表用的是 Opus 4.x 舊費率，金額高估約 2.6 倍

- **現象**：使用者質疑「一個 session 花了 $4.63」不合理。查 transcript 後確認 **token 數是對的**（29 次 API 呼叫、cache_read 佔 96%，見 2026-07-31 的設計說明），但**金額算錯**
- **根因一：Opus 單價過時**。`JQ_PRICE_FN` 沿用 Opus 4.1 時代的 `{i:15, o:75, cw:18.75, cr:1.50}`。Opus 4.6 之後（含本機在用的 `claude-opus-5` 與 `claude-opus-4-8`）已降為 `{i:5, o:25, cr:0.50}`，整整 3 倍價差。1M context 沒有長文脈溢價，所以不需要按 context 大小分級
- **根因二：cache write 沒分 TTL**。cache write 單價是 input 的 1.25 倍（5 分鐘 TTL）或 **2 倍**（1 小時 TTL），舊表只有單一 `cw` 值。實測 Claude Code 現在**一律用 1h TTL**（transcript 的 `usage.cache_creation.ephemeral_1h_input_tokens` 全額、`ephemeral_5m_input_tokens` 為 0），所以舊表在 Opus 上同時犯了「用錯家族單價」和「用錯 TTL 倍率」兩個錯
- **改動**：
  - `JQ_PRICE_FN` 的每個家族改成 `{i, o, cw5, cw1h, cr}` 五個欄位；新增 Fable/Mythos（$10/$50）；用 `test("^claude-opus-(5|4-8|4-7|4-6)")` 區分現代 Opus（$5/$25）與舊 Opus（維持 $15/$75）；unknown model 的 fallback 從舊 Opus 改為現代 Opus 費率
  - 新增共用的 `usd($u; $p)` jq 函式，依 `usage.cache_creation` 的 5m/1h 分項各自計價；分項欄位缺席（舊 transcript）才退回用 1h 單價估全部。`_refresh_cost` 與 `_scan_transcript` 兩處各自 4 行的算式收斂成一次呼叫
- **實測驗證**：拿本 session 的 transcript 快照（29 次呼叫、1,567,092 tokens）對帳——舊費率 $3.99、新費率 $1.51，statusline 輸出與手算逐項一致
- **連動修好的測試基礎設施問題**：`tests/test-statusline.sh` 兩處用 `awk "/^JQ_PRICE_FN=/,/end;'$/"` 抽取定價函式，終止條件寫死「以 `end;'` 結尾的那行」。新增的 `usd()` 定義在 `end;` 之後，被攔腰截斷成未閉合的字串，兩個測試因此輸出 `run /cyberpunk-statusline configure` 這種毫不相干的訊息。改成 `/;'$/`（收尾單引號那行），之後再改 jq 內容都不會再壞
- **新增迴歸測試** `test_cache_write_ttl_priced_separately`：同樣 100K cache write，全 5m 應為 $0.62、全 1h 應為 $1.00、缺分項退回 1h。跑突變測試（把 `cw5` 改成等於 `cw1h`）確認第一條斷言會紅，偵測有效
- **文件**：雙語 README 補上 cache write 依 TTL 分價的說明，並言明「這個金額是**等值 API 成本**，Pro／Max 訂閱制不按 token 計費，它是用量的量尺不是帳單」——使用者這次的疑問正是由此而來
- **測試**：全綠——test-statusline 70/0、test-configure 21/0、codex adapter 五支 82/0、core 三支 44/0、tab-state 48 pass

## 2026-07-31

### 調整：金額一律顯示到小數點後兩位

- **需求**：`fmt_price()` 原本對 `<1` 的金額印四位小數，實機上第二列出現 `$0.0000`、`$0.0000` 這種「一排零」的畫面，小數位數比狀態列其他數值（`%.0f` 百分比、`%.1fM` token、`%.1f` burn rate）都多，看起來雜訊很重。使用者要求全站統一最多兩位小數
- **改動**：`statusline.sh` 的 `fmt_price()` 移除 `<1` 的四位小數分支，一律 `printf "%.2f"`。無效輸入（空字串 / 非數字 / nan / inf）仍降級為 `--`，行為不變
- **取捨**：小額會塌成 `$0.00`（例如 `$0.0000015`）。這是刻意接受的——四位小數本來就是為了讓極小額不歸零，但實際上「這一輪幾乎沒花錢」用 `$0.00` 表達已經夠準確，反而比四位小數更好讀
- **連動更新**：`tests/test-statusline.sh` 八處 `fmt_price` 期望值與五處渲染斷言（`$0.4425`→`$0.44`、`$0.9150`→`$0.91`、`$0.0192`→`$0.02`、`$0.3240`→`$0.32`、`$0.0915`→`$0.09`）；README 雙語版的 `last_chat` 範例由 `163K $0.3442` 改為 `163K $0.34`
- **驗證**：全套測試綠燈——test-statusline 67/0、test-configure 21/0、codex adapter 五支共 82/0、core 三支共 44/0、tab-state 48 pass

### 重構：第二列改為 session + last_chat 兩個獨立區塊

- **需求**：第一列的 `tokens` 沒有金額；第二列是硬編碼的 `Last Chat cache:161,065 in:622 out:1,212 $0.3442`，四個數字擠在一起、無法開關、無法調色。使用者要兩者都簡化成「總 token + 金額」、分成不同顏色的獨立欄位、並可在 configure 開關
- **token 定義改變**：改為 `input + cache_creation + cache_read + output`，**含 cache_read**，推翻 2026-07-30 tokens 區塊「排除 cache_read」的設計。理由是 cache_read 佔實際花費約一半（實測某 session：cache_read $0.91 / 總額 $1.89），金額既然必須含它，token 也含才對得起來。代價是數字隨「輪數 × context 大小」近似平方成長，但此欄位語意本就是「累計計費量」而非「當前 context 佔用」（後者由 `context` 區塊負責）
- **statusline.sh 資料層**：`_count_session_tokens()` 換成 `_scan_transcript()`，單次掃描產出 `session_tokens|session_cost|last_tokens|last_cost` 四個值。定價沿用 `_refresh_cost` 既有的 `price()` 表按 model 家族分價
  - 快取檔 `session-tokens-<session_id>` 格式由 `<mtime>|<total>` 擴充為五欄位；讀取時最後一欄為空即視為舊格式 cache miss 重算，使用者不需手動清快取
  - 新增 `SESSION_COST_OVERRIDE`、`LAST_CHAT_TOKENS_OVERRIDE`、`LAST_CHAT_COST_OVERRIDE` 三個環境變數
  - **修正 `last_chat` 取錯訊息的嚴重 bug**：原本的去重邏輯是 `group_by(.k) | map(.[0]) | ... | last`，但 `group_by` 會依分組鍵（`message.id|requestId`）做**字典序排序**，導致這裡的 `last` 取到的是**去重鍵字典序最大**的那筆訊息，而不是 transcript 檔案中實際最後一次 API 呼叫。拿 40 份真實 transcript 實測，33 份的 `last_chat` 是錯的，其中一份差了近 4 倍（真正最後一次呼叫是 503,090 tokens，錯誤版本回報 167,705）。修法是在去重前先用 `to_entries` 記下每筆訊息在檔案中的原始索引，去重後改 `sort_by(.i)` 依檔案順序排序，再取最後一筆，如此 `last` 才等於「檔案裡最後一次呼叫」。新增迴歸測試 `test_scan_last_chat_uses_file_order`，fixture 刻意讓字典序與檔案順序相反（`m9` 排文件最前但字典序最大、`m1` 排文件最後但字典序最小）以固定住這個行為。**教訓**：Task 2 當初用單一訊息的 fixture 驗證資料層，那種案例下 `session` 與 `last_chat` 必然相等，天生就測不出這個 bug——之後任何牽涉「取最後一筆」邏輯的測試，至少要準備兩筆且刻意讓排序鍵與檔案順序相反的樣本
- **statusline.sh 渲染層**：新增 `fmt_price()`（`≥1` 兩位小數、`<1` 四位小數，避免 `$0.3442` 塌成 `$0.00`）、`block_text_session` / `block_text_last_chat` / `render_block_session` / `render_block_last_chat`，共用 `_usage_text` 與 `_render_usage` 兩個內部函式
  - 三段降級：無 token → `--`（dim 色）；有 token 無金額 → 只印 token（Codex 靠這條）；兩者皆有 → 完整輸出
- **statusline.sh 組裝層**：頂層的組裝邏輯抽成 `assemble_line()`，第一列讀 `blocks`、第二列讀 `blocks_line2`，共用 rainbow / classic 渲染。quota 帳號的 spend/credit 替換抽成 `apply_quota_substitution()`，只作用於第一列
  - rainbow 的 `PL_CYCLE` 以區塊在**該列**中的索引計算，第二列從 `accent_1` 重新起算，兩欄自然有色差，不需另外配色
  - `_canon_block()` 把舊 config 的 `"tokens"` 映射為 `"session"`。`blocks_line2` 缺漏時**不補預設值** —— 若補上，第一列映射而來的 session 會與第二列重複
- **移除外部 hook 依賴**：刪除硬編碼的 `turn_line` 區段。它讀的是 repo 外部 `~/.claude/hooks/show-turn-usage.sh`（Stop hook）寫的快取檔，使用者不裝該 hook 就沒有第二列，且該 hook 把單價硬編成 Opus（切到 Sonnet 會多算約 5 倍）。改由 `last_chat` 從 transcript 直接讀，repo 自此自足
- **主題**：14 個主題檔（含 `custom-example`）補上 `symbols.{nerd,unicode,ascii}.{session,last_chat}` 與 `blocks.{session,last_chat}`。session 沿用該主題既有的 tokens 符號值，last_chat 新增（nerd `󰭹` / unicode `⌯` / ascii `[L]`）。`symbols.*.tokens` 仍是活的 fallback ——`sym session` 找不到時會退回 `sym tokens`，讓沒補上 `symbols.*.session` 的自訂主題不會壞掉；但 `blocks.tokens` 其實已經摸不到了，`_canon_block` 在 dispatch 前就把 `"tokens"` 改寫成 `"session"`，`block_color`/`block_bg` 從未真的被叫成 `tokens`，主題檔裡若還留著 `blocks.tokens` 純粹是死設定
- **configure.sh**：區塊選單拆成第一列與第二列兩步，新增 `step_blocks_line2`。`render_preview` 有十餘個呼叫點，第二列因此不加位置參數，改讀全域 `sel_blocks_line2` / `cur_blocks_line2`
- **adapters/codex**：`codex_session_tokens` 不再扣除 `cached_input_tokens`，與 Claude 側新定義一致。blocks 把 `tokens` 換成 `session`，**留在第一列** —— `render_with_claude_style` 以 `awk 'NF { print; exit }'` 只取第一行（Codex 的 `tui.status_line` 是單行），故 Codex 不使用 `blocks_line2`。不注入 `SESSION_COST_OVERRIDE`（Codex 沒有 session 層級金額來源），session 區塊降級成只顯示 token
- **設計文件**：`docs/superpowers/specs/2026-07-31-line2-session-lastchat-design.md`

## 2026-07-30

### 新增：tokens 區塊（本次 session 累計 token）

- **需求**：狀態列有 `context`（CTX %）與 `cost`（今日 $），但沒有欄位回答「這場對話到目前為止燒掉多少 token」
- **統計範圍**：本次 session 累計，非跨 session 日總量（日維度已由 cost 以金額呈現）
- **token 組成**：`input_tokens + cache_creation_input_tokens + output_tokens`，**刻意排除 `cache_read_input_tokens`** — 每輪都重讀整個 context，計入後會膨脹到數千萬並主導整個數字。代價是與 `ccusage` 的 `totalTokens` 定義不一致，兩份 README 皆明確標註
- **顯示格式**：`842` / `840K` / `12.4M`，一律無條件捨去，避免 999,999 被進位成 `1000K` 這種跨單位溢位
- **statusline.sh**：新增 `S_TOKENS`、`fmt_tokens()`、`_resolve_transcript()`、`_count_session_tokens()`、`render_block_tokens()`、`block_text_tokens()`，classic 與 rainbow 兩處 dispatch 各補一個 case
  - transcript 解析順序：stdin 的 `.transcript_path` → 退路以 `.session_id` glob `~/.claude/projects/*/`。需要退路是因為 `session_id` 確認存在於 statusline schema，`transcript_path` 未實測確認；用 glob 精準比對 session id，不從 cwd 推導目錄 slug（slug 會把 `/` 與 `.` 都轉成 `-`，不可靠）
  - 去重鍵沿用 cost fallback 的 `message.id|requestId`，重試的 request 不會重複計算
  - 快取採 **mtime 比對**而非固定 TTL：`~/.cache/cyberpunk-statusline/session-tokens-<session_id>` 存 `<mtime>|<total>`，transcript 未變動就零成本重用。實測最大的 1.8MB session 全掃約 18ms
  - 新增 `SESSION_TOKENS_OVERRIDE` 環境變數（沿用 `USAGE_CACHE_OVERRIDE` 慣例），供 configure.sh 預覽與 Codex adapter 注入
- **adapters/codex/statusline.sh**：新增 `codex_session_tokens()`，取最後一筆 `token_count` 事件的 `payload.info.total_token_usage`，公式 `input - cached + cache_write + output`
  - 依實測 rollout 驗證：`total_tokens == input + output`，故 `input_tokens` 已內含 `cached_input_tokens`（需相減）；`reasoning_output_tokens` 已內含於 `output_tokens`（不可另加）
  - 透過 `SESSION_TOKENS_OVERRIDE` 注入主渲染器，完整重用格式化與配色邏輯
- **主題**：14 個主題檔（含 `custom-example`）補上 `symbols.{nerd,unicode,ascii}.tokens` 與 `blocks.tokens` 色彩；`sym` 另有硬編碼 fallback `⇅`，自訂主題不會壞掉
- **接線**：`config.json`、`configure.sh` 的 `block_ids` 與說明、`adapters/codex/config.json`、`install-codex.sh` 的預設 blocks
- **清理**：移除死碼 `render_block_turn_usage()` / `block_text_turn_usage()` — 兩處 dispatch 都沒有對應 case，且其讀取的 `/tmp/claude-turn-usage.txt` 在 repo 內找不到任何 writer。**檔案尾端的第二行渲染器未動** — 那段讀的是 `$COST_CACHE_DIR/turn-usage-<md5>.txt`，由 repo 外的 `~/.claude/hooks/show-turn-usage.sh`（Stop hook）寫入，是獨立且活著的功能，顯示上一輪明細，與 tokens 的 session 累計語義不重疊
- **測試**：`tests/test-statusline.sh` +11（加總、排除 cache_read、去重、session_id 退路、無 transcript 降級、6 個格式邊界）；`tests/adapters/codex/test-statusline.sh` +4（真實 fixture 公式、cache_write 計入、reasoning 不重複計、無 token_count 降級）。合計 41 + 24 全通過
- **文件同步**：`README.md` 與 `docs/README.zh-TW.md` 的區塊表格與說明段落；設計文件 `docs/superpowers/specs/2026-07-30-session-tokens-block-design.md`

## 2026-06-21

### 調整：credit 用光（100%）時隱藏 credit 區塊

- **需求**：非訂閱制（quota）帳號同時擁有一次性 credit 與 enterprise spend limit 時，狀態列會並列 `CR`（credit）與 spend 兩個區塊。當 credit 已用光（100%），其倒數（如 `↻78d`）已無意義，使用者希望此時隱藏 credit、只留 enterprise limit
- **statusline.sh**：credit 區塊插入條件由「`credit_pct` 非空」改為「非空且 `< 100`」（以 awk 做浮點比較）；同步將 burn 指標挑選邏輯改為相同門檻 — credit 用光後 burn 改追蹤 spend，避免顯示固定 100% 的無意義速率
- **測試**：新增 `test_credit_exhausted_hidden`（utilization=100 時不出現 `CR`、仍保留 spend）；既有 `test_credit_block_quota` / `test_credit_absent_hidden` 不受影響，全數通過
- **文件同步**：`README.md`（英文）與 `docs/README.zh-TW.md`（繁中）的 credit 區塊說明補上「用光後隱藏」行為

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

### 調整：burn 顯示改為「實際 〈關係符〉 健康」

- 顯示格式定為 `actual <op> sustainable`（例 `87.6 > 0.8`）：目前每日速度對比「剛好撐到重置」的每日速度，關係符 `>`/`<`/`=` 直接表達關係，`>` 代表太快並轉告警色；數字取一位小數，資料不足顯示 `--`
- 新增 `_burn_fmt`（awk；注意 function 須定義於 BEGIN 之外）產生顯示字串
- 同步 README（中英）與測試（改驗 `actual <op> sustainable` 格式）

### 修正：單點離群讀數被誤判為 reset 導致速率爆量

- 現象：history 混入一筆瞬間異常的低 utilization（如 28 之間夾一筆 8），reset 偵測把它當成重置 → 視窗只剩數秒 → actual 算出數萬 %/day
- 修正：utilization 是累積量、視窗內只增不減，故 reset 偵測忽略「下降後下一筆又彈回到跌前水準」的 V 形單點離群；無下一筆或下一筆仍低於跌前才算真重置
- 補回歸測試 `outlier dip ignored`

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
