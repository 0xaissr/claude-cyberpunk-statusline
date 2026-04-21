# iTerm2 Tab-State Integration — Design

- **Date**: 2026-04-21
- **Status**: Approved (awaiting user spec review)
- **Related**: absorbs functionality from sibling repo `claude-cli` (`scripts/tab-state.sh` + `install.sh`)

## 1. Motivation

`claude-cli` 目前提供一個獨立工具：透過 Claude Code hooks 改變 iTerm2 tab 底色，讓使用者一眼看出 session 狀態（running / waiting / idle / error）。這套工具的顏色是 hard-coded RGB，跟 `cyberpunk-statusline` 的 theme 系統完全沒關係。

目標：

1. **統一安裝** — 安裝 cyberpunk-statusline 的使用者可以在 `configure.sh` wizard 裡一併啟用 tab tinting，不用另外跑 claude-cli 的 installer。
2. **顏色跟 theme 綁定** — tab 底色不再 hard-code，而是從當前 cyberpunk theme 的 palette（`accent_1` / `warning` / `alert` / …）解析出來；換 theme → tab 顏色自動跟著換。
3. **使用者可自訂 mapping** — 允許使用者在 wizard 裡為每個 state 指定要用哪個 palette 名。

## 2. Scope

### In scope
- 新增 `tab-state.sh` 到 repo 根目錄，接 `running|waiting|idle|error|clear` 五個狀態並吐 iTerm2 escape sequence。
- 新增 `config.json` 的 `tab_state` section（啟用開關 + 4 state → palette 名）。
- `configure.sh` 新增 Step 8「iTerm2 tab tinting」，含 enable 開關與 per-state palette 選擇（含 live swatch preview）。
- `configure.sh` 的 apply 階段接手 `~/.claude/settings.json` hooks 的 merge 與 teardown（含 backup）。
- `uninstall.sh` 對稱移除 hooks 與 symlink。
- 新增 `tests/tab-state.test.sh`。
- 同步更新 `README.md` / `docs/README.zh-TW.md` / `LOG.md`。

### Out of scope (v1)
- 任意 hex 色輸入（只允許 palette 名）。
- iTerm2 以外終端機（Terminal.app / Ghostty / WezTerm 各自需要不同 API）。
- Tab 標題 / badge 文字客製。
- 每 Claude project 獨立 palette。
- 動畫 / 漸層底色。
- 修改 `claude-cli`（使用者自行決定是否卸載那邊的版本）。

## 3. Architecture

### 3.1 Data flow

```
┌─ Claude Code hook (e.g. UserPromptSubmit) ─┐
│                                             │
▼                                             │
~/.claude/settings.json                        │
  hooks.UserPromptSubmit[].hooks[].command  ──┘
    = "~/.claude/scripts/tab-state.sh running"
                │
                ▼
~/.claude/scripts/tab-state.sh (symlink)
                │
                ▼
<repo>/tab-state.sh
    1. [[ $TERM_PROGRAM != iTerm.app ]] → exit 0
    2. readlink -f $0 → 推回 repo 根 → 讀 config.json
    3. 讀 tab_state.enabled；false → exit 0
    4. 讀 tab_state.<state> 取 palette 名
    5. 讀 themes/<theme>.json 的 colors.<palette> 取 hex
    6. hex → 3 個 0–255 RGB，printf escape sequence → /dev/tty
    7. waiting 多送 RequestAttention=yes
```

### 3.2 Ownership boundary

- **`configure.sh`** 獨佔 `tab_state` 設定與 `~/.claude/settings.json` hooks 生命週期。`install.sh` 不需要知道 tab_state（不管 standalone 還是 plugin 流程最終都會走 configure.sh）。
- **`tab-state.sh`** 純資料流：每次觸發都即時讀 config + theme，沒有快取、沒有狀態。主題換了下次 hook 就生效。
- **`uninstall.sh`** 呼叫同一份 teardown 函式，該函式抽到獨立 helper 檔 `_lib_tab_state.sh`，由 configure.sh 與 uninstall.sh 共同 source（詳見 §8.3）。

### 3.3 Standalone vs plugin 安裝路徑

| 情境 | `$REPO_DIR` 怎麼算 | tab-state.sh 位置 |
|---|---|---|
| Standalone repo | `readlink -f $0` → repo 根 | `<repo>/tab-state.sh` |
| Plugin cache | `readlink -f $0` → `~/.claude/plugins/cache/.../1.0.0/` | 該版本目錄下 |

configure.sh 使用 `$SCRIPT_DIR`（自身所在目錄）作為 symlink source，兩種情境都 work。**Plugin 升版本會產生新的 version 目錄，symlink 會指向舊版；使用者重跑 `/cyberpunk-statusline configure` 時 wizard 會自動重建 symlink**。README 明寫此提醒。

## 4. Config schema

`config.json` 新增 section：

```json
{
  "tab_state": {
    "enabled": false,
    "running": "accent_1",
    "waiting": "warning",
    "idle":    "accent_3",
    "error":   "alert"
  }
}
```

- `enabled: false` 是預設值；沒有 `tab_state` 區塊 → 視為 disabled。
- 每個 state 的值必須是當前 theme `colors.*` 的合法 key，wizard 限制使用者只能從以下 **6 個** palette 名挑選（排除 `bg_primary` / `bg_panel` 以免跟 iTerm 底色重疊）：
  - `accent_1` / `accent_2` / `accent_3` / `warning` / `alert` / `dim`
- 預設 mapping：`running → accent_1`、`waiting → warning`、`idle → accent_3`、`error → alert`。

## 5. `tab-state.sh` 實作規格

### 5.1 CLI 合約

```
tab-state.sh <state>
```

合法 `<state>`：`running`、`waiting`、`idle`、`error`、`clear`。

Exit code：
- `0`：成功（或刻意靜默退出，例如非 iTerm2）
- `1`：無效 state 參數（stderr 寫 usage）

### 5.2 邏輯骨架

```bash
#!/usr/bin/env bash
[[ "$TERM_PROGRAM" != "iTerm.app" ]] && exit 0

# 解析 symlink chain 回到 repo 根（不依賴 GNU readlink -f / greadlink）
SCRIPT_SRC="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SRC" ]; do
  _DIR="$(cd -P "$(dirname "$SCRIPT_SRC")" && pwd)"
  SCRIPT_SRC="$(readlink "$SCRIPT_SRC")"
  [[ "$SCRIPT_SRC" != /* ]] && SCRIPT_SRC="$_DIR/$SCRIPT_SRC"
done
REPO_DIR="${CYBERPUNK_STATUSLINE_REPO_DIR:-$(cd -P "$(dirname "$SCRIPT_SRC")" && pwd)}"
CONFIG="$REPO_DIR/config.json"
JQ=$(command -v jq || echo /opt/homebrew/bin/jq)

declare -A DEFAULTS=(
  [running]=accent_1 [waiting]=warning [idle]=accent_3 [error]=alert
)

: "${TAB_STATE_OUT:=/dev/tty}"
[[ -w "$TAB_STATE_OUT" ]] || exit 0

state="${1-}"
case "$state" in
  running|waiting|idle|error)
    [[ -f "$CONFIG" ]] || exit 0
    enabled=$("$JQ" -r '.tab_state.enabled // false' "$CONFIG" 2>/dev/null)
    [[ "$enabled" != "true" ]] && exit 0
    palette=$("$JQ" -r --arg s "$state" '.tab_state[$s] // empty' "$CONFIG")
    palette="${palette:-${DEFAULTS[$state]}}"
    theme=$("$JQ" -r '.theme // "terminal-glitch"' "$CONFIG")
    hex=$("$JQ" -r --arg k "$palette" '.colors[$k] // empty' "$REPO_DIR/themes/$theme.json" 2>/dev/null)
    [[ -z "$hex" ]] && exit 0
    r=$((16#${hex:1:2})); g=$((16#${hex:3:2})); b=$((16#${hex:5:2}))
    printf '\e]6;1;bg;red;brightness;%d\a'   "$r" > "$TAB_STATE_OUT"
    printf '\e]6;1;bg;green;brightness;%d\a' "$g" > "$TAB_STATE_OUT"
    printf '\e]6;1;bg;blue;brightness;%d\a'  "$b" > "$TAB_STATE_OUT"
    [[ "$state" == "waiting" ]] && printf '\e]1337;RequestAttention=yes\a' > "$TAB_STATE_OUT"
    ;;
  clear)
    printf '\e]6;1;bg;*;default\a' > "$TAB_STATE_OUT"
    ;;
  *)
    echo "usage: $0 {running|waiting|idle|error|clear}" >&2
    exit 1
    ;;
esac
```

### 5.3 Error handling 矩陣

| 情境 | 行為 |
|---|---|
| 非 iTerm2 (`$TERM_PROGRAM`) | exit 0 靜默 |
| `config.json` 不存在 | exit 0 靜默 |
| `tab_state.enabled != true` | exit 0 靜默 |
| `tab_state.<state>` 缺值 | 用內建 DEFAULTS fallback |
| theme 檔不存在或無對應 palette key | exit 0 靜默 |
| `/dev/tty` 不可寫（headless） | exit 0 靜默 |
| 無效 state 參數 | stderr 寫 usage，exit 1 |

**原則**：hook 錯誤絕不阻塞 Claude Code。只有給開發者誤用 CLI 時才會失敗退出。

## 6. Hooks 管理

### 6.1 啟用（enable）

configure.sh apply 階段，當 `tab_state.enabled` 從 false → true：

1. `mkdir -p ~/.claude/scripts`
2. `ln -sfn "$SCRIPT_DIR/tab-state.sh" ~/.claude/scripts/tab-state.sh`
3. `cp ~/.claude/settings.json ~/.claude/settings.json.bak.$(date +%Y%m%d-%H%M%S)`
4. 透過 `jq -s` 把以下 6 個 entries append 進 `hooks.*`（不覆寫既有同 event hooks）：

   | Event | State |
   |---|---|
   | SessionStart | idle |
   | UserPromptSubmit | running |
   | PreToolUse (matcher `*`) | running |
   | Notification | waiting |
   | Stop | idle |
   | SessionEnd | clear |

5. `jq empty <新檔>` 驗證合法後覆蓋 settings.json。

### 6.2 停用（disable / uninstall）

當 `tab_state.enabled` 從 true → false，或 `uninstall.sh`：

1. 用 jq filter 掃 `hooks.*[].hooks[]`，移除所有 `command` 含 `tab-state.sh` 的 entry。
2. 若某 event `hooks` 陣列變空，連 event key 一起刪。
3. backup 後寫回 settings.json。
4. `rm -f ~/.claude/scripts/tab-state.sh`（只刪 symlink；若 `~/.claude/scripts/` 空則 `rmdir` 嘗試性清理）。

### 6.3 Pre-enable 偵測

啟用前 wizard 會掃 settings.json 是否已有 `command` 含 `tab-state.sh` 但路徑不是我們的（例如 claude-cli 那份），若有：印警告，讓使用者繼續或中止。不強制移除對方，尊重使用者選擇。

## 7. Wizard Step 8 UX

### 7.1 位置與前置

- 排在 Step 8 of 8（最後），**必須在 theme 選完之後**——因為 palette swatch 要用當前 theme 的色。
- 進入時若 `$TERM_PROGRAM != iTerm.app` → 印 "Detected: $TERM_PROGRAM. Tab tinting is iTerm2-only — skipping." 後自動跳過（寫 `enabled: false`）。

### 7.2 Step 8.1 — Enable / Skip

```
────── Step 8 of 8: iTerm2 tab tinting ──────

 Claude Code hooks will tint your iTerm2 tab background
 based on session state. Requires editing
 ~/.claude/settings.json (backup created automatically).

 ▸ 1. Enable
   2. Skip (default)
```

選 Skip → `enabled: false`，wizard 結束。選 Enable → 進 Step 8.2。

### 7.3 Step 8.2 — Per-state palette 選擇

依序 4 個 state：`running` → `waiting` → `idle` → `error`。每個 state 一個 `ask_choice`，選項為 6 個 palette（排除 bg 色），每個選項右邊印 ANSI swatch + hex：

```
 Running (UserPromptSubmit / PreToolUse):
 ▸ accent_1   ████  #00F5FF   ← default
   accent_2   ████  #FF2DD1
   accent_3   ████  #9D4EDD
   warning    ████  #FFB800
   alert      ████  #FF4444
   dim        ████  #666666
```

預設 highlight（每個 state 的第一次進入預設選項）：
- running → `accent_1`
- waiting → `warning`
- idle → `accent_3`
- error → `alert`

### 7.4 Step 8.3 — Apply summary

wizard 結束時印：
```
✓ tab_state enabled (4 states mapped)
✓ ~/.claude/scripts/tab-state.sh symlinked
✓ ~/.claude/settings.json backed up → settings.json.bak.20260421-153022
✓ 6 hooks merged
```

## 8. 實作結構

### 8.1 新檔
- `tab-state.sh` — §5 規格（runtime 腳本）
- `_lib_tab_state.sh` — install / remove hooks helpers（§6 邏輯），由 configure.sh 與 uninstall.sh 共同 source
- `tests/tab-state.test.sh` — §9 規格

### 8.2 修改
- `config.json` — 新增 `tab_state` section（預設 disabled）
- `configure.sh` — 新增：
  - `source "$SCRIPT_DIR/_lib_tab_state.sh"` 載入共用 helpers
  - `step_tab_state()` wizard function（含 8.0 偵測、8.1 enable、8.2 per-state、8.3 summary）
  - apply 階段呼叫 `_install_tab_state_hooks` / `_remove_tab_state_hooks`（來自 lib）
  - main flow 的 `TOTAL_STEPS` 從 7 改為 8，step dispatch 加入 tab_state 分支
- `_lib_tab_state.sh`（新檔）— 提供 `_install_tab_state_hooks()`、`_remove_tab_state_hooks()`、`_detect_foreign_tab_state_hooks()` 三個可重用函式
- `uninstall.sh` — source `_lib_tab_state.sh` 後，若偵測 tab_state 已啟用，呼叫 `_remove_tab_state_hooks`
- `README.md` / `docs/README.zh-TW.md` — 加一節說明功能、plugin 升版需重跑 configure
- `LOG.md` — 新增 changelog 條目

### 8.3 Helper 函式擺哪？

選項：
- **A.** 全部放 `configure.sh` 裡（簡單、一檔搞定）
- **B.** 抽到 `_lib_tab_state.sh`，由 configure.sh / uninstall.sh 各自 source（DRY）

**推薦 B**。uninstall.sh 不需要拉整個 configure.sh，抽 helper 到獨立檔更乾淨。命名採底線前綴表示 internal。

## 9. Testing

### 9.1 `tests/tab-state.test.sh`

移植 claude-cli 的 5 個煙霧測試 + 新增：

1. **RGB resolution from config + theme**：產生暫存 `config.json`（`tab_state.running = accent_1`）+ 暫存 theme JSON（`accent_1 = #28783C`） → 跑 `tab-state.sh running` 後驗證輸出包含 `red;brightness;40`、`green;brightness;120`、`blue;brightness;60`。
2. **`enabled: false`** → 無輸出、exit 0。
3. **`config.json` 不存在** → 無輸出、exit 0。
4. **palette 名 typo** → 無輸出、exit 0。
5. **換 theme** → 同一個 palette 名（`accent_1`）在兩份不同 theme fixture 下解出不同 RGB。
6. **`clear` 仍工作**（即使 config 有問題也能 reset）。
7. **非 iTerm2** → 無輸出。
8. **無效 state** → 非 0 exit。

### 9.2 測試鉤子
- `TAB_STATE_OUT=/dev/stdout` 把 escape sequence 導到 stdout 供 grep 驗證（沿用 claude-cli）。
- `CYBERPUNK_STATUSLINE_REPO_DIR=<fixture 目錄>` override repo 根路徑，讓測試用暫存的 config.json / themes/ 做隔離測試（已在 §5.2 script 骨架預留 env fallback）。

### 9.3 手動驗收
- 開新 iTerm2 tab → 跑 `claude` → SessionStart 觸發 idle (藍)；送訊息 → UserPromptSubmit 綠；等待回應中 → 視 Notification 觸發 → 底色正確。
- 切 theme 後再次觸發任一 hook → tab 色跟著換。
- `/cyberpunk-statusline configure` 選 Skip → settings.json 沒 hooks，無任何 tint。
- `./uninstall.sh` → settings.json 恢復到 backup 前狀態或至少 hooks 清乾淨。

## 10. 已知風險 / trade-offs

| 風險 | 嚴重度 | 緩解 |
|---|---|---|
| 跟 claude-cli 雙裝會 hooks 疊加 | 中 | Step 8 pre-enable 偵測並警告 |
| Plugin 升版 symlink 指舊目錄 | 低 | README 提醒升版後重跑 configure |
| 每 hook fork bash + jq 兩次（3 ms 級） | 可忽略 | 不優化；必要時 v2 再談 |
| 使用者手改 `~/.claude/settings.json` 導致 merge 失敗 | 中 | backup 永遠先寫；`jq empty` 驗證合法才覆蓋 |
| config.json 不存在時 script 需 graceful exit | 低 | §5.3 error matrix 已涵蓋 |

## 11. Rollout 檢查清單

- [ ] `tab-state.sh` 實作 + 所有 error handling path
- [ ] `tests/tab-state.test.sh` 全部通過
- [ ] `config.json` schema 更新
- [ ] `configure.sh` Step 8 實作（含 swatch preview）
- [ ] `_lib_tab_state.sh` helper（install / remove hooks）
- [ ] `uninstall.sh` 對稱支援
- [ ] README 中英雙版新增章節
- [ ] LOG.md 寫新條目
- [ ] 在真實 iTerm2 session 手動驗收（idle / running / waiting / clear）
- [ ] Commit 按現有慣例（繁中 commit message、Co-Authored-By）
