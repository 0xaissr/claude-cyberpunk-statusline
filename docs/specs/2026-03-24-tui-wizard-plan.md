# TUI Configure Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Powerlevel10k-style interactive TUI wizard (`scripts/configure.sh`) that guides users through 5 configuration steps with live statusline preview.

**Architecture:** Single bash script using ANSI escape codes and `tput` for full-screen TUI. Each wizard step renders a selection menu; steps 2-5 call `statusline.sh` with `CONFIG_OVERRIDE` for live preview. Reusable TUI primitives (menu, checkbox, draw) are defined as functions at the top, then each step composes them.

**Tech Stack:** Bash 3.2+, tput, jq (already required by statusline.sh)

**Spec:** `docs/specs/2026-03-24-tui-wizard-design.md`

---

## File Structure

```
scripts/
├── configure.sh      # NEW — TUI wizard main script (~400-500 lines)
└── statusline.sh     # EXISTING — no changes, used for live preview
tests/
├── test-statusline.sh    # EXISTING — no changes
└── test-configure.sh     # NEW — automated tests for configure.sh
```

`configure.sh` is one file because the TUI primitives (menu, checkbox, draw) are tightly coupled to the wizard flow. Splitting into multiple files would add `source` complexity for no real benefit.

---

## Task 1: Scaffold + Startup Checks

**Files:**
- Create: `scripts/configure.sh`
- Create: `tests/test-configure.sh`

This task creates the script skeleton with startup validation (TTY, jq, terminal size), alternate screen management, and cleanup trap.

- [ ] **Step 1: Create configure.sh with startup checks and alternate screen**

```bash
#!/usr/bin/env bash
# ╔══════════════════════════════════════════╗
# ║  cyberpunk-statusline TUI configurator  ║
# ╚══════════════════════════════════════════╝

set -uo pipefail
# Note: do NOT use set -e — arithmetic expressions like (( x > 0 )) return
# exit code 1 when false, which would kill the script under errexit.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$PLUGIN_DIR/config.json"
THEMES_DIR="$PLUGIN_DIR/themes"
STATUSLINE="$SCRIPT_DIR/statusline.sh"
JQ=$(command -v jq 2>/dev/null || echo "/opt/homebrew/bin/jq")

# ── Startup checks ───────────────────────────────────────────────────────
if [ ! -t 0 ]; then
  echo "Error: configure requires an interactive terminal" >&2
  exit 1
fi

if ! "$JQ" --version >/dev/null 2>&1; then
  echo "Error: jq is required. Install with: brew install jq" >&2
  exit 1
fi

TERM_COLS=$(tput cols)
TERM_LINES=$(tput lines)
if (( TERM_COLS < 60 || TERM_LINES < 25 )); then
  echo "Error: terminal too small (need 60x25, got ${TERM_COLS}x${TERM_LINES})" >&2
  exit 1
fi

# ── Terminal state management ────────────────────────────────────────────
cleanup() {
  tput cnorm 2>/dev/null   # show cursor
  tput rmcup 2>/dev/null   # exit alternate screen
  stty echo 2>/dev/null    # restore echo
}
trap cleanup EXIT

tput smcup    # enter alternate screen
tput civis    # hide cursor
tput clear    # clear screen
stty -echo    # disable echo

# ── Preview sample data ──────────────────────────────────────────────────
SAMPLE_DATA='{
  "session_id": "preview",
  "model": { "id": "claude-opus-4-6", "display_name": "Opus 4.6 (1M context)" },
  "workspace": { "current_dir": "'"$HOME"'/project" },
  "context_window": { "used_percentage": 58, "remaining_percentage": 42 },
  "rate_limits": {
    "five_hour": { "used_percentage": 76, "resets_at": 9999999999 },
    "seven_day": { "used_percentage": 33, "resets_at": 9999999999 }
  }
}'

# ── Load existing config (for preselection) ──────────────────────────────
if [ -f "$CONFIG" ]; then
  cur_theme=$("$JQ" -r '.theme // "terminal-glitch"' "$CONFIG")
  cur_symbols=$("$JQ" -r '.symbol_set // "unicode"' "$CONFIG")
  cur_spacing=$("$JQ" -r '.spacing // "normal"' "$CONFIG")
  cur_separator=$("$JQ" -r '.separator // "│"' "$CONFIG")
  cur_blocks=$("$JQ" -r '.blocks // ["model","context","rate_5h","rate_7d","directory","git","time"] | .[]' "$CONFIG")
else
  cur_theme="terminal-glitch"
  cur_symbols="unicode"
  cur_spacing="normal"
  cur_separator="│"
  cur_blocks="model context rate_5h rate_7d directory git time"
fi

# Selections (will be filled by each step)
sel_symbols=""
sel_theme=""
sel_blocks=""
sel_spacing=""
sel_separator=""

echo "Scaffold ready — steps will be added in subsequent tasks."
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x scripts/configure.sh`

- [ ] **Step 3: Create test-configure.sh with startup check tests**

```bash
#!/usr/bin/env bash
# Tests for configure.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGURE="$PROJECT_DIR/scripts/configure.sh"

PASS=0
FAIL=0

pass() { PASS=$((PASS+1)); echo "  ✔ $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ✗ $1: $2"; }

# ── Test: script exists and is executable ─────────────────────────────────
test_exists() {
  echo "▸ test_exists"
  if [ -x "$CONFIGURE" ]; then
    pass "configure.sh is executable"
  else
    fail "configure.sh" "not found or not executable"
  fi
}

# ── Test: exits with error when stdin is not a TTY ────────────────────────
test_requires_tty() {
  echo "▸ test_requires_tty"
  local output
  output=$(echo "" | bash "$CONFIGURE" 2>&1) || true
  if echo "$output" | grep -q "interactive terminal"; then
    pass "rejects non-TTY stdin"
  else
    fail "TTY check" "did not reject piped stdin"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────
echo "=== configure.sh tests ==="
test_exists
test_requires_tty

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

- [ ] **Step 4: Make test executable and run**

Run: `chmod +x tests/test-configure.sh && bash tests/test-configure.sh`
Expected: 2 passed, 0 failed

- [ ] **Step 5: Commit**

```bash
git add scripts/configure.sh tests/test-configure.sh
git commit -m "feat: configure.sh scaffold — 啟動檢查、alternate screen、cleanup trap"
```

---

## Task 2: TUI Drawing Primitives

**Files:**
- Modify: `scripts/configure.sh`

Add reusable functions for drawing the TUI: header, key reading, screen clearing, and the preview renderer.

- [ ] **Step 1: Add drawing helper functions to configure.sh**

Insert after the selections variables block, before the final echo:

```bash
# ── Drawing helpers ──────────────────────────────────────────────────────

# Clear screen and draw the wizard header
draw_header() {
  local step="$1" total="$2" title="$3"
  tput clear
  echo -e "\033[1;36m╔══════════════════════════════════════════════════╗\033[0m"
  echo -e "\033[1;36m║   CYBERPUNK STATUSLINE CONFIGURATOR             ║\033[0m"
  echo -e "\033[1;36m╚══════════════════════════════════════════════════╝\033[0m"
  echo ""
  echo -e "\033[2mStep ${step}/${total}\033[0m — \033[1m${title}\033[0m"
  echo ""
}

# Draw footer with navigation hints
draw_footer() {
  local hints="$1"
  local row=$((TERM_LINES - 1))
  tput cup "$row" 0
  echo -e "\033[2m${hints}\033[0m"
}

# Read a single keypress. Sets KEY to: "up", "down", "enter", "space", "b", "q", or the character
read_key() {
  KEY=""
  local c
  IFS= read -rsn1 c
  case "$c" in
    $'\x1b')
      local seq
      IFS= read -rsn2 -t 1 seq || true
      case "$seq" in
        '[A') KEY="up" ;;
        '[B') KEY="down" ;;
        *)    KEY="escape" ;;
      esac
      ;;
    '')    KEY="enter" ;;
    ' ')   KEY="space" ;;
    b|B)   KEY="b" ;;
    q|Q)   KEY="q" ;;
    *)     KEY="$c" ;;
  esac
}

# Render live preview of the statusline with given config overrides
# Usage: render_preview theme symbol_set spacing separator blocks_csv
render_preview() {
  local theme="$1" symbol_set="$2" spacing="$3" separator="$4" blocks_csv="$5"

  local tmp_config
  tmp_config=$(mktemp)

  # Build blocks JSON array from CSV
  local blocks_json=""
  local first=true
  IFS=',' read -ra block_arr <<< "$blocks_csv"
  for b in "${block_arr[@]}"; do
    if [ "$first" = true ]; then
      blocks_json="\"$b\""
      first=false
    else
      blocks_json="$blocks_json, \"$b\""
    fi
  done

  cat > "$tmp_config" <<CONF
{
  "theme": "$theme",
  "symbol_set": "$symbol_set",
  "spacing": "$spacing",
  "separator": "$separator",
  "blocks": [$blocks_json],
  "bar_width": 10
}
CONF

  local output
  output=$(CONFIG_OVERRIDE="$tmp_config" bash "$STATUSLINE" <<< "$SAMPLE_DATA" 2>/dev/null) || true
  rm -f "$tmp_config"

  echo -e "$output"
}

# Draw preview at a fixed row near the bottom
draw_preview() {
  local preview_row=$((TERM_LINES - 4))
  tput cup "$preview_row" 0
  # Clear the preview area (3 lines)
  echo -e "\033[K"
  echo -e "\033[K"
  tput cup "$preview_row" 0
  echo -e "\033[2mPreview:\033[0m"
  tput cup $((preview_row + 1)) 0
  render_preview "$@"
}
```

- [ ] **Step 2: Run existing tests to verify no regressions**

Run: `bash tests/test-configure.sh`
Expected: 2 passed, 0 failed

- [ ] **Step 3: Commit**

```bash
git add scripts/configure.sh
git commit -m "feat: TUI drawing primitives — header, footer, key reader, preview renderer"
```

---

## Task 3: Single-Select Menu Function

**Files:**
- Modify: `scripts/configure.sh`

Add a reusable `menu_select` function that renders a list of options with arrow-key navigation. Returns the selected index. This is used by Steps 1, 2, 4, 5.

- [ ] **Step 1: Add menu_select function**

Insert after the `draw_preview` function:

```bash
# Single-select menu with arrow key navigation
# Usage: menu_select initial_index label1 label2 ...
# Returns selected index (0-based) in MENU_RESULT
menu_select() {
  local cursor="$1"
  shift
  local options=("$@")
  local count=${#options[@]}

  while true; do
    # Draw options
    for i in "${!options[@]}"; do
      tput cup $((6 + i)) 0
      echo -e "\033[K"  # clear line
      if [ "$i" -eq "$cursor" ]; then
        echo -e " \033[1;36m❯\033[0m \033[1m${options[$i]}\033[0m"
      else
        echo -e "   \033[2m${options[$i]}\033[0m"
      fi
    done

    read_key
    case "$KEY" in
      up)    (( cursor > 0 )) && (( cursor-- )) ;;
      down)  (( cursor < count - 1 )) && (( cursor++ )) ;;
      enter) break ;;
      q)     cleanup; exit 0 ;;
      b)     MENU_RESULT=-1; return ;;
    esac
  done

  MENU_RESULT=$cursor
}
```

- [ ] **Step 2: Run tests**

Run: `bash tests/test-configure.sh`
Expected: 2 passed, 0 failed

- [ ] **Step 3: Commit**

```bash
git add scripts/configure.sh
git commit -m "feat: menu_select — 可重用的單選選單元件，支援 ↑↓ 導航"
```

---

## Task 4: Step 1 — Symbol Test + Selection

**Files:**
- Modify: `scripts/configure.sh`

Implement the first wizard step. Displays three symbol sets, user picks which displays correctly.

- [ ] **Step 1: Add step_symbols function and main flow**

Replace the final `echo "Scaffold ready..."` line with:

```bash
# ══════════════════════════════════════════════════════════════════════════
# ── STEP FUNCTIONS ───────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════

step_symbols() {
  draw_header 1 5 "Which symbols display correctly?"

  local options=(
    "Nerd Font:  󰚩 󰍛  󰔟"
    "Unicode:   ⬡ ◈ ⚡ ⟳ ⌁ ⎇ ◷ █ ░"
    "ASCII:     [M] [C] [!] [~] [D] [G] [T] # ."
  )
  local values=("nerd" "unicode" "ascii")

  # Find initial cursor from existing config
  local init=1  # default to unicode
  for i in "${!values[@]}"; do
    if [ "${values[$i]}" = "$cur_symbols" ]; then
      init=$i
      break
    fi
  done

  draw_footer "↑↓ move · Enter select · q quit"
  menu_select "$init" "${options[@]}"

  if [ "$MENU_RESULT" -eq -1 ]; then
    return 1  # can't go back from step 1
  fi

  sel_symbols="${values[$MENU_RESULT]}"
}

# ── Main wizard flow ─────────────────────────────────────────────────────
current_step=1

while true; do
  case $current_step in
    1)
      step_symbols
      if [ -n "$sel_symbols" ]; then
        current_step=2
      fi
      ;;
    *)
      # Placeholder for steps 2-5
      tput clear
      echo "Symbol set: $sel_symbols"
      echo ""
      echo "Steps 2-5 coming soon. Press any key to exit."
      read -rsn1
      break
      ;;
  esac
done
```

- [ ] **Step 2: Test manually**

Run: `bash scripts/configure.sh`
Expected: Full-screen wizard shows Step 1 with 3 symbol options, ↑↓ works, Enter selects, then shows placeholder.

- [ ] **Step 3: Commit**

```bash
git add scripts/configure.sh
git commit -m "feat: Step 1 — 符號測試 + 選擇，↑↓ 導航 + Enter 確認"
```

---

## Task 5: Step 2 — Theme Selection with Live Preview

**Files:**
- Modify: `scripts/configure.sh`

The core step: list 12 themes grouped by category, live preview on cursor move.

- [ ] **Step 1: Add step_theme function**

Insert after `step_symbols`, before the main wizard flow:

```bash
step_theme() {
  draw_header 2 5 "Choose your theme:"

  # Build theme list from JSON files (exclude directories like custom-example)
  local theme_files=()
  local theme_ids=()
  local theme_labels=()

  # Cyberpunk themes (ordered)
  local cyberpunk_order=("terminal-glitch" "neon-classic" "synthwave-sunset" "blade-runner" "retrowave-chrome")
  # Classic themes (ordered)
  local classic_order=("dracula" "tokyo-night" "catppuccin-mocha" "rose-pine" "nord" "one-dark" "gruvbox-dark")

  local all_labels=()
  local all_ids=()
  local group_indices=()  # indices where group headers should appear

  # Cyberpunk group
  group_indices+=(0)
  all_labels+=("── Cyberpunk ──")
  all_ids+=("__header__")
  for tid in "${cyberpunk_order[@]}"; do
    local tf="$THEMES_DIR/${tid}.json"
    if [ -f "$tf" ]; then
      local name desc
      name=$("$JQ" -r '.name // "'"$tid"'"' "$tf")
      desc=$("$JQ" -r '.description // ""' "$tf")
      if [ -n "$desc" ]; then
        all_labels+=("$name — $desc")
      else
        all_labels+=("$name")
      fi
      all_ids+=("$tid")
    fi
  done

  # Classic group
  group_indices+=("${#all_labels[@]}")
  all_labels+=("── Classic ──")
  all_ids+=("__header__")
  for tid in "${classic_order[@]}"; do
    local tf="$THEMES_DIR/${tid}.json"
    if [ -f "$tf" ]; then
      local name
      name=$("$JQ" -r '.name // "'"$tid"'"' "$tf")
      all_labels+=("$name")
      all_ids+=("$tid")
    fi
  done

  local count=${#all_labels[@]}

  # Find initial cursor from existing config (skip headers)
  local cursor=1  # first non-header
  for i in "${!all_ids[@]}"; do
    if [ "${all_ids[$i]}" = "$cur_theme" ]; then
      cursor=$i
      break
    fi
  done

  # Determine blocks CSV for preview
  local blocks_csv
  if [ -n "$sel_blocks" ]; then
    blocks_csv="$sel_blocks"
  else
    blocks_csv=$(echo "$cur_blocks" | tr ' ' '\n' | tr '\n' ',' | sed 's/,$//')
  fi
  local spacing="${sel_spacing:-$cur_spacing}"
  local separator="${sel_separator:-$cur_separator}"

  draw_footer "↑↓ move · Enter select · b back · q quit"

  local prev_cursor=-1
  while true; do
    # Draw options (only redraw if cursor moved)
    if [ "$cursor" != "$prev_cursor" ]; then
      for i in "${!all_labels[@]}"; do
        tput cup $((6 + i)) 0
        echo -e "\033[K"
        if [ "${all_ids[$i]}" = "__header__" ]; then
          echo -e " \033[2;33m${all_labels[$i]}\033[0m"
        elif [ "$i" -eq "$cursor" ]; then
          echo -e " \033[1;36m❯\033[0m \033[1m${all_labels[$i]}\033[0m"
        else
          echo -e "   \033[2m${all_labels[$i]}\033[0m"
        fi
      done

      # Live preview
      if [ "${all_ids[$cursor]}" != "__header__" ]; then
        draw_preview "${all_ids[$cursor]}" "${sel_symbols:-$cur_symbols}" "$spacing" "$separator" "$blocks_csv"
      fi
      prev_cursor=$cursor
    fi

    read_key
    case "$KEY" in
      up)
        (( cursor > 0 )) && (( cursor-- ))
        # Skip headers
        while [ "$cursor" -ge 0 ] && [ "${all_ids[$cursor]}" = "__header__" ]; do
          (( cursor > 0 )) && (( cursor-- )) || break
        done
        ;;
      down)
        (( cursor < count - 1 )) && (( cursor++ ))
        # Skip headers
        while [ "$cursor" -lt "$count" ] && [ "${all_ids[$cursor]}" = "__header__" ]; do
          (( cursor < count - 1 )) && (( cursor++ )) || break
        done
        ;;
      enter)
        if [ "${all_ids[$cursor]}" != "__header__" ]; then
          sel_theme="${all_ids[$cursor]}"
          return 0
        fi
        ;;
      b) return 1 ;;
      q) cleanup; exit 0 ;;
    esac
  done
}
```

- [ ] **Step 2: Wire step 2 into main flow**

Update the main wizard `case` block:

```bash
while true; do
  case $current_step in
    1)
      step_symbols
      if [ -n "$sel_symbols" ]; then
        current_step=2
      fi
      ;;
    2)
      if step_theme; then
        current_step=3
      else
        current_step=1
      fi
      ;;
    *)
      tput clear
      echo "Symbol set: $sel_symbols"
      echo "Theme: $sel_theme"
      echo ""
      echo "Steps 3-5 coming soon. Press any key to exit."
      read -rsn1
      break
      ;;
  esac
done
```

- [ ] **Step 3: Test manually**

Run: `bash scripts/configure.sh`
Expected: Step 1 → Step 2 shows 12 themes in 2 groups, ↑↓ skips headers, live preview updates at bottom on cursor move. `b` goes back to Step 1.

- [ ] **Step 4: Commit**

```bash
git add scripts/configure.sh
git commit -m "feat: Step 2 — 主題選擇，12 個主題分組顯示 + 即時渲染預覽"
```

---

## Task 6: Step 3 — Block Selection (Checkbox)

**Files:**
- Modify: `scripts/configure.sh`

- [ ] **Step 1: Add step_blocks function**

Insert after `step_theme`:

```bash
step_blocks() {
  draw_header 3 5 "Which blocks to show? (Space to toggle)"

  local block_ids=("model" "context" "rate_5h" "rate_7d" "directory" "git" "time")
  local block_descs=(
    "model       — Model name (e.g., Opus 4.6)"
    "context     — Context window usage %"
    "rate_5h     — 5-hour rate limit %"
    "rate_7d     — 7-day rate limit %"
    "directory   — Working directory"
    "git         — Git branch"
    "time        — Current time"
  )

  # Build initial states from existing config
  local states=()
  for bid in "${block_ids[@]}"; do
    if echo " $cur_blocks " | grep -q " $bid "; then
      states+=("1")
    else
      states+=("0")
    fi
  done

  draw_footer "↑↓ move · Space toggle · Enter confirm · b back · q quit"

  # We need live preview for blocks too, but checkbox doesn't support it natively
  # So we wrap the checkbox with a custom loop
  local cursor=0
  local count=${#block_descs[@]}

  while true; do
    for i in "${!block_descs[@]}"; do
      tput cup $((6 + i)) 0
      echo -e "\033[K"
      local check_mark
      if [ "${states[$i]}" = "1" ]; then
        check_mark="\033[32m✔\033[0m"
      else
        check_mark="\033[2m✗\033[0m"
      fi
      if [ "$i" -eq "$cursor" ]; then
        echo -e " \033[1;36m❯\033[0m${check_mark} \033[1m${block_descs[$i]}\033[0m"
      else
        echo -e "  ${check_mark} \033[2m${block_descs[$i]}\033[0m"
      fi
    done

    # Build current blocks CSV for preview
    local blocks_csv=""
    local first=true
    for i in "${!block_ids[@]}"; do
      if [ "${states[$i]}" = "1" ]; then
        if $first; then
          blocks_csv="${block_ids[$i]}"
          first=false
        else
          blocks_csv="$blocks_csv,${block_ids[$i]}"
        fi
      fi
    done

    draw_preview "${sel_theme:-$cur_theme}" "${sel_symbols:-$cur_symbols}" "${sel_spacing:-$cur_spacing}" "${sel_separator:-$cur_separator}" "$blocks_csv"

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
        ;;
      enter)
        # Require at least 1 block
        local any_checked=false
        for s in "${states[@]}"; do
          [ "$s" = "1" ] && any_checked=true
        done
        if ! $any_checked; then
          # Flash warning on footer
          tput cup $((TERM_LINES - 1)) 0
          echo -e "\033[K\033[31mAt least one block must be enabled!\033[0m"
          sleep 1
          draw_footer "↑↓ move · Space toggle · Enter confirm · b back · q quit"
          continue
        fi
        # Build result
        sel_blocks=""
        local first=true
        for i in "${!block_ids[@]}"; do
          if [ "${states[$i]}" = "1" ]; then
            if $first; then
              sel_blocks="${block_ids[$i]}"
              first=false
            else
              sel_blocks="$sel_blocks,${block_ids[$i]}"
            fi
          fi
        done
        return 0
        ;;
      b) return 1 ;;
      q) cleanup; exit 0 ;;
    esac
  done
}
```

- [ ] **Step 2: Wire step 3 into main flow**

Update the `case` block to add step 3:

```bash
    3)
      if step_blocks; then
        current_step=4
      else
        current_step=2
      fi
      ;;
```

- [ ] **Step 3: Test manually**

Run: `bash scripts/configure.sh`
Expected: Steps 1→2→3. Step 3 shows 7 blocks with checkboxes, Space toggles, preview updates live showing only checked blocks. `b` goes back to Step 2.

- [ ] **Step 4: Commit**

```bash
git add scripts/configure.sh
git commit -m "feat: Step 3 — 區塊勾選，Space 切換 + 即時預覽"
```

---

## Task 7: Step 4 — Spacing Mode

**Files:**
- Modify: `scripts/configure.sh`

- [ ] **Step 1: Add step_spacing function**

Insert after `step_blocks`:

```bash
step_spacing() {
  draw_header 4 5 "Spacing mode:"

  local options=(
    "Normal        — symbol + label + bar + %"
    "Compact       — symbol + bar + %"
    "Ultra Compact — symbol + % only"
  )
  local values=("normal" "compact" "ultra-compact")

  local init=0
  for i in "${!values[@]}"; do
    if [ "${values[$i]}" = "$cur_spacing" ]; then
      init=$i
      break
    fi
  done

  local blocks_csv="${sel_blocks:-$(echo "$cur_blocks" | tr ' ' '\n' | tr '\n' ',' | sed 's/,$//')}"
  local theme="${sel_theme:-$cur_theme}"
  local symbols="${sel_symbols:-$cur_symbols}"
  local separator="${sel_separator:-$cur_separator}"

  draw_footer "↑↓ move · Enter select · b back · q quit"

  local cursor=$init
  local count=${#options[@]}
  local prev_cursor=-1

  while true; do
    if [ "$cursor" != "$prev_cursor" ]; then
      for i in "${!options[@]}"; do
        tput cup $((6 + i)) 0
        echo -e "\033[K"
        if [ "$i" -eq "$cursor" ]; then
          echo -e " \033[1;36m❯\033[0m \033[1m${options[$i]}\033[0m"
        else
          echo -e "   \033[2m${options[$i]}\033[0m"
        fi
      done
      draw_preview "$theme" "$symbols" "${values[$cursor]}" "$separator" "$blocks_csv"
      prev_cursor=$cursor
    fi

    read_key
    case "$KEY" in
      up)    (( cursor > 0 )) && (( cursor-- )) ;;
      down)  (( cursor < count - 1 )) && (( cursor++ )) ;;
      enter) sel_spacing="${values[$cursor]}"; return 0 ;;
      b)     return 1 ;;
      q)     cleanup; exit 0 ;;
    esac
  done
}
```

- [ ] **Step 2: Wire step 4 into main flow**

```bash
    4)
      if step_spacing; then
        current_step=5
      else
        current_step=3
      fi
      ;;
```

- [ ] **Step 3: Test manually and commit**

Run: `bash scripts/configure.sh`
Expected: Steps 1-4 work. Step 4 shows 3 spacing options with live preview showing the difference.

```bash
git add scripts/configure.sh
git commit -m "feat: Step 4 — 間距模式選擇 + 即時預覽"
```

---

## Task 8: Step 5 — Separator Style

**Files:**
- Modify: `scripts/configure.sh`

- [ ] **Step 1: Add step_separator function**

Insert after `step_spacing`:

```bash
step_separator() {
  draw_header 5 5 "Separator style:"

  local options=(
    "Pipe  │"
    "Slash /"
    "Dot   ·"
    "Space  "
    "Arrow ›"
  )
  local values=("│" "/" "·" " " "›")

  local init=0
  for i in "${!values[@]}"; do
    if [ "${values[$i]}" = "$cur_separator" ]; then
      init=$i
      break
    fi
  done

  local blocks_csv="${sel_blocks:-$(echo "$cur_blocks" | tr ' ' '\n' | tr '\n' ',' | sed 's/,$//')}"
  local theme="${sel_theme:-$cur_theme}"
  local symbols="${sel_symbols:-$cur_symbols}"
  local spacing="${sel_spacing:-$cur_spacing}"

  draw_footer "↑↓ move · Enter select · b back · q quit"

  local cursor=$init
  local count=${#options[@]}
  local prev_cursor=-1

  while true; do
    if [ "$cursor" != "$prev_cursor" ]; then
      for i in "${!options[@]}"; do
        tput cup $((6 + i)) 0
        echo -e "\033[K"
        if [ "$i" -eq "$cursor" ]; then
          echo -e " \033[1;36m❯\033[0m \033[1m${options[$i]}\033[0m"
        else
          echo -e "   \033[2m${options[$i]}\033[0m"
        fi
      done
      draw_preview "$theme" "$symbols" "$spacing" "${values[$cursor]}" "$blocks_csv"
      prev_cursor=$cursor
    fi

    read_key
    case "$KEY" in
      up)    (( cursor > 0 )) && (( cursor-- )) ;;
      down)  (( cursor < count - 1 )) && (( cursor++ )) ;;
      enter) sel_separator="${values[$cursor]}"; return 0 ;;
      b)     return 1 ;;
      q)     cleanup; exit 0 ;;
    esac
  done
}
```

- [ ] **Step 2: Wire step 5 into main flow**

```bash
    5)
      if step_separator; then
        current_step=6
      else
        current_step=4
      fi
      ;;
```

- [ ] **Step 3: Test manually and commit**

Run: `bash scripts/configure.sh`
Expected: All 5 steps work. Step 5 shows 5 separator options with live preview. `b` navigates back through all steps.

```bash
git add scripts/configure.sh
git commit -m "feat: Step 5 — 分隔符選擇 + 即時預覽"
```

---

## Task 9: Completion Screen + Config Write

**Files:**
- Modify: `scripts/configure.sh`

Write the final config and show a summary.

- [ ] **Step 1: Add step_done function and wire into main flow**

Insert after `step_separator`:

```bash
step_done() {
  # Build blocks JSON
  local blocks_json=""
  local first=true
  IFS=',' read -ra block_arr <<< "$sel_blocks"
  for b in "${block_arr[@]}"; do
    if $first; then
      blocks_json="\"$b\""
      first=false
    else
      blocks_json="$blocks_json, \"$b\""
    fi
  done

  local block_count=${#block_arr[@]}

  # Write config
  cat > "$CONFIG" <<CONF
{
  "theme": "$sel_theme",
  "symbol_set": "$sel_symbols",
  "spacing": "$sel_spacing",
  "separator": "$sel_separator",
  "blocks": [$blocks_json],
  "bar_width": 10
}
CONF

  # Show completion screen
  tput clear
  echo -e "\033[1;32m╔══════════════════════════════════════════════════╗\033[0m"
  echo -e "\033[1;32m║   ✔ Configuration saved!                        ║\033[0m"
  echo -e "\033[1;32m╚══════════════════════════════════════════════════╝\033[0m"
  echo ""
  echo -e "\033[2mTheme:    \033[0m $sel_theme"
  echo -e "\033[2mSymbols:  \033[0m $sel_symbols"
  echo -e "\033[2mBlocks:   \033[0m ${block_count}/7 enabled"
  echo -e "\033[2mSpacing:  \033[0m $sel_spacing"
  echo -e "\033[2mSeparator:\033[0m $sel_separator"
  echo ""
  render_preview "$sel_theme" "$sel_symbols" "$sel_spacing" "$sel_separator" "$sel_blocks"
  echo ""
  echo ""
  echo -e "\033[2mYour status line will update on the next refresh.\033[0m"
  echo -e "\033[2mRun\033[0m \033[36mcyberpunk-statusline configure\033[0m \033[2manytime to reconfigure.\033[0m"
  echo ""
  echo -e "\033[2mPress any key to exit.\033[0m"
  read -rsn1
}
```

Update the main flow to replace the placeholder with the done step:

```bash
while true; do
  case $current_step in
    1)
      step_symbols
      if [ -n "$sel_symbols" ]; then
        current_step=2
      fi
      ;;
    2)
      step_theme
      if [ $? -eq 0 ]; then
        current_step=3
      else
        current_step=1
      fi
      ;;
    3)
      if step_blocks; then
        current_step=4
      else
        current_step=2
      fi
      ;;
    4)
      if step_spacing; then
        current_step=5
      else
        current_step=3
      fi
      ;;
    5)
      step_separator
      if [ $? -eq 0 ]; then
        current_step=6
      else
        current_step=4
      fi
      ;;
    6)
      step_done
      break
      ;;
  esac
done
```

- [ ] **Step 2: Test full flow manually**

Run: `bash scripts/configure.sh`
Expected: Complete 5 steps → summary screen with config preview → config.json updated. Verify with: `cat config.json`

- [ ] **Step 3: Commit**

```bash
git add scripts/configure.sh
git commit -m "feat: 完成畫面 — 設定寫入 config.json + 摘要顯示 + 最終預覽"
```

---

## Task 10: Automated Tests

**Files:**
- Modify: `tests/test-configure.sh`

Add tests to validate the configure script structure and non-interactive behavior.

- [ ] **Step 1: Add more tests**

```bash
# ── Test: script contains all 5 step functions ────────────────────────────
test_step_functions() {
  echo "▸ test_step_functions"
  local missing=0
  for fn in step_symbols step_theme step_blocks step_spacing step_separator step_done; do
    if grep -q "^${fn}()" "$CONFIGURE"; then
      pass "$fn exists"
    else
      fail "$fn" "function not found"
      missing=$((missing + 1))
    fi
  done
}

# ── Test: script contains TUI primitives ──────────────────────────────────
test_tui_primitives() {
  echo "▸ test_tui_primitives"
  for fn in draw_header draw_footer read_key render_preview draw_preview menu_select; do
    if grep -q "^${fn}()" "$CONFIGURE"; then
      pass "$fn exists"
    else
      fail "$fn" "function not found"
    fi
  done
}

# ── Test: startup checks are present ──────────────────────────────────────
test_startup_checks() {
  echo "▸ test_startup_checks"
  if grep -q '\-t 0' "$CONFIGURE"; then
    pass "TTY check present"
  else
    fail "TTY check" "not found"
  fi
  if grep -q 'jq' "$CONFIGURE"; then
    pass "jq check present"
  else
    fail "jq check" "not found"
  fi
  if grep -q 'tput cols' "$CONFIGURE"; then
    pass "terminal size check present"
  else
    fail "terminal size" "not found"
  fi
}
```

Update main to run new tests:

```bash
echo "=== configure.sh tests ==="
test_exists
test_requires_tty
test_step_functions
test_tui_primitives
test_startup_checks
```

- [ ] **Step 2: Run tests**

Run: `bash tests/test-configure.sh`
Expected: All tests pass.

- [ ] **Step 3: Also run existing statusline tests to confirm no regressions**

Run: `bash tests/test-statusline.sh`
Expected: All pass.

- [ ] **Step 4: Commit**

```bash
git add tests/test-configure.sh
git commit -m "test: configure.sh 自動化測試 — step 函式、TUI 元件、啟動檢查"
```

---

## Task 11: Final Integration

**Files:**
- Modify: `skills/configure/SKILL.md` (optional: add note about TUI alternative)

- [ ] **Step 1: Run full end-to-end test**

Run: `bash scripts/configure.sh`
Walk through all 5 steps, use `b` to go back, then complete. Verify `config.json` is correct.

- [ ] **Step 2: Run all tests**

```bash
bash tests/test-statusline.sh && bash tests/test-configure.sh
```
Expected: All pass.

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "feat: TUI configure wizard 完成 — p10k 風格互動式設定精靈

5 步流程搭配即時渲染預覽：
1. 符號測試 + 選擇
2. 主題選擇（12 個主題，分組顯示）
3. 區塊勾選
4. 間距模式
5. 分隔符風格

純 Bash 實作，零外部依賴（jq 除外）。"
```
