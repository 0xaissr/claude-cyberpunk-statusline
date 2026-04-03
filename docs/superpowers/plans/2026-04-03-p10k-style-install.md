# P10k-Style Installation Refactor

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 將 cyberpunk-statusline 從 Claude plugin 系統改為 Powerlevel10k 風格的 git clone + install.sh 安裝方式。

**Architecture:** Flatten `cyberpunk-statusline/` 子目錄到 repo root。新增 `install.sh` 自動設定 Claude Code statusLine 並啟動 configure wizard；新增 `uninstall.sh` 清除設定。移除所有 Claude plugin 機制（`.claude-plugin/`、`hooks/`、`skills/`）。

**Tech Stack:** Bash, jq, Claude Code CLI (`claude config`)

---

## File Structure (After)

```
cyberpunk-statusline/          ← repo root
├── install.sh                 ← NEW: 安裝腳本
├── uninstall.sh               ← NEW: 反安裝腳本
├── configure.sh               ← MOVED from cyberpunk-statusline/scripts/configure.sh
├── statusline.sh              ← MOVED from cyberpunk-statusline/scripts/statusline.sh
├── config.json                ← user config (gitignored)
├── themes/                    ← MOVED from cyberpunk-statusline/themes/
│   ├── terminal-glitch.json
│   ├── ... (all theme files)
│   └── custom-example/
├── tests/                     ← MOVED from cyberpunk-statusline/tests/
│   ├── test-statusline.sh
│   ├── test-configure.sh
│   └── sample-input.json
├── .gitignore                 ← UPDATED: add config.json
├── README.md                  ← UPDATED: new install instructions
├── LOG.md
└── docs/
```

**Deleted:**
- `cyberpunk-statusline/.claude-plugin/` (entire dir)
- `cyberpunk-statusline/hooks/` (entire dir)
- `cyberpunk-statusline/skills/` (entire dir)
- `cyberpunk-statusline/scripts/debug-keys.sh` (dev tool, already gitignored)
- `cyberpunk-statusline/config.json` (user-specific)

---

### Task 1: Flatten directory structure

**Files:**
- Move: `cyberpunk-statusline/scripts/statusline.sh` → `statusline.sh`
- Move: `cyberpunk-statusline/scripts/configure.sh` → `configure.sh`
- Move: `cyberpunk-statusline/themes/` → `themes/`
- Move: `cyberpunk-statusline/tests/` → `tests/`
- Delete: `cyberpunk-statusline/` (entire subdirectory)

- [ ] **Step 1: Move core files to repo root**

```bash
cd ~/Documents/VibeCoding/cyberpunk-statusline

# Move scripts to root
mv cyberpunk-statusline/scripts/statusline.sh ./statusline.sh
mv cyberpunk-statusline/scripts/configure.sh ./configure.sh

# Move themes and tests
mv cyberpunk-statusline/themes/ ./themes/
mv cyberpunk-statusline/tests/ ./tests/

# Ensure executable
chmod +x statusline.sh configure.sh
```

- [ ] **Step 2: Delete the old cyberpunk-statusline subdirectory**

```bash
rm -rf cyberpunk-statusline/
```

- [ ] **Step 3: Update .gitignore — add config.json, remove old entries**

Replace `.gitignore` with:

```
.DS_Store
/tmp/
.superpowers/
config.json
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: flatten 目錄結構 — 移除 Claude plugin 子目錄，腳本提升到 repo root"
```

---

### Task 2: Fix path references in statusline.sh

**Files:**
- Modify: `statusline.sh`

After flatten, `PLUGIN_DIR` resolves to repo root. The script uses `PLUGIN_DIR` to find `config.json` and `themes/`. Since files are now at root level, the path logic needs updating.

- [ ] **Step 1: Update PLUGIN_DIR resolution**

In `statusline.sh`, change:

```bash
# OLD
PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG_OVERRIDE:-$PLUGIN_DIR/config.json}"
```

to:

```bash
# NEW
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${CONFIG_OVERRIDE:-$SCRIPT_DIR/config.json}"
```

- [ ] **Step 2: Update THEME_DIR**

Change:

```bash
THEME_DIR="$PLUGIN_DIR/themes"
```

to:

```bash
THEME_DIR="$SCRIPT_DIR/themes"
```

- [ ] **Step 3: Run tests to verify**

```bash
cd ~/Documents/VibeCoding/cyberpunk-statusline
bash tests/test-statusline.sh
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add statusline.sh
git commit -m "fix: statusline.sh 路徑改為 SCRIPT_DIR — 配合 flatten 後的目錄結構"
```

---

### Task 3: Fix path references in configure.sh

**Files:**
- Modify: `configure.sh`

- [ ] **Step 1: Update path resolution**

In `configure.sh`, change:

```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$PLUGIN_DIR/config.json"
THEMES_DIR="$PLUGIN_DIR/themes"
STATUSLINE="$SCRIPT_DIR/statusline.sh"
```

to:

```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
THEMES_DIR="$SCRIPT_DIR/themes"
STATUSLINE="$SCRIPT_DIR/statusline.sh"
```

Remove any other references to `PLUGIN_DIR` throughout the file.

- [ ] **Step 2: Commit**

```bash
git add configure.sh
git commit -m "fix: configure.sh 路徑改為 SCRIPT_DIR — 配合 flatten 後的目錄結構"
```

---

### Task 4: Fix path references in test files

**Files:**
- Modify: `tests/test-statusline.sh`
- Modify: `tests/test-configure.sh`

- [ ] **Step 1: Update test-statusline.sh paths**

Change:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STATUSLINE="$PROJECT_DIR/scripts/statusline.sh"
SAMPLE="$SCRIPT_DIR/sample-input.json"
```

to:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STATUSLINE="$PROJECT_DIR/statusline.sh"
SAMPLE="$SCRIPT_DIR/sample-input.json"
```

Also update theme dir references — the test uses `$PROJECT_DIR/themes` which stays correct.

- [ ] **Step 2: Update test-configure.sh paths**

Change:

```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGURE="$PROJECT_DIR/scripts/configure.sh"
```

to:

```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGURE="$PROJECT_DIR/configure.sh"
```

- [ ] **Step 3: Run tests**

```bash
bash tests/test-statusline.sh
bash tests/test-configure.sh
```

Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add tests/
git commit -m "fix: 測試腳本路徑更新 — 配合 flatten 後的目錄結構"
```

---

### Task 5: Create install.sh

**Files:**
- Create: `install.sh`

- [ ] **Step 1: Write install.sh**

```bash
#!/usr/bin/env bash
# ╔══════════════════════════════════════════╗
# ║  cyberpunk-statusline installer          ║
# ║  p10k-style: git clone → install → done ║
# ╚══════════════════════════════════════════╝
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATUSLINE="$SCRIPT_DIR/statusline.sh"
CONFIGURE="$SCRIPT_DIR/configure.sh"

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║  cyberpunk-statusline installer      ║"
echo "  ╚══════════════════════════════════════╝"
echo ""

# ── Check jq ─────────────────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  echo "  ✗ jq is required but not found."
  echo "    Install with: brew install jq (macOS) or apt install jq (Linux)"
  exit 1
fi
echo "  ✔ jq found"

# ── Ensure scripts are executable ────────────────────────────────────────
chmod +x "$STATUSLINE" "$CONFIGURE"
echo "  ✔ Scripts are executable"

# ── Configure Claude Code statusLine ─────────────────────────────────────
STATUSLINE_CMD="bash \"$STATUSLINE\""
STATUSLINE_JSON="{\"type\":\"command\",\"command\":\"$STATUSLINE_CMD\"}"

if command -v claude >/dev/null 2>&1; then
  echo ""
  echo "  Configuring Claude Code statusLine..."
  if claude config set -g statusLine "$STATUSLINE_JSON" 2>/dev/null; then
    echo "  ✔ Claude Code statusLine configured"
  else
    echo "  ⚠ Auto-config failed. Run this manually:"
    echo ""
    echo "    claude config set -g statusLine '$STATUSLINE_JSON'"
    echo ""
  fi
else
  echo ""
  echo "  ⚠ claude CLI not found. After installing Claude Code, run:"
  echo ""
  echo "    claude config set -g statusLine '$STATUSLINE_JSON'"
  echo ""
fi

# ── Launch configure wizard if no config exists ──────────────────────────
CONFIG="$SCRIPT_DIR/config.json"
if [ ! -f "$CONFIG" ]; then
  echo ""
  echo "  No config found. Launching setup wizard..."
  echo ""
  bash "$CONFIGURE"
else
  echo ""
  echo "  ✔ Existing config found ($(jq -r '.theme // "unknown"' "$CONFIG"))"
  echo "    Run ./configure.sh to reconfigure."
fi

echo ""
echo "  ✔ Installation complete!"
echo "    Restart your Claude Code session to see the status line."
echo ""
```

- [ ] **Step 2: Make executable**

```bash
chmod +x install.sh
```

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat: 新增 install.sh — p10k 風格安裝腳本，自動設定 Claude Code statusLine"
```

---

### Task 6: Create uninstall.sh

**Files:**
- Create: `uninstall.sh`

- [ ] **Step 1: Write uninstall.sh**

```bash
#!/usr/bin/env bash
# ╔══════════════════════════════════════════╗
# ║  cyberpunk-statusline uninstaller        ║
# ╚══════════════════════════════════════════╝
set -euo pipefail

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║  cyberpunk-statusline uninstaller    ║"
echo "  ╚══════════════════════════════════════╝"
echo ""

# ── Remove Claude Code statusLine config ─────────────────────────────────
if command -v claude >/dev/null 2>&1; then
  echo "  Removing Claude Code statusLine config..."
  if claude config set -g statusLine '""' 2>/dev/null; then
    echo "  ✔ statusLine config removed"
  else
    echo "  ⚠ Could not remove config automatically."
    echo "    Run: claude config set -g statusLine '\"\"'"
  fi
else
  echo "  ⚠ claude CLI not found."
  echo "    If you have Claude Code, run: claude config set -g statusLine '\"\"'"
fi

echo ""
echo "  ✔ Uninstall complete."
echo "    You can now safely delete this directory."
echo "    Restart your Claude Code session to apply changes."
echo ""
```

- [ ] **Step 2: Make executable**

```bash
chmod +x uninstall.sh
```

- [ ] **Step 3: Commit**

```bash
git add uninstall.sh
git commit -m "feat: 新增 uninstall.sh — 移除 Claude Code statusLine 設定"
```

---

### Task 7: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite README with p10k-style install instructions**

Replace the Installation section with:

```markdown
## Installation

### 1. Clone

```bash
git clone https://github.com/0xaissr/cyberpunk-statusline.git ~/cyberpunk-statusline
```

### 2. Install

```bash
cd ~/cyberpunk-statusline && ./install.sh
```

This will:
- Check prerequisites (jq)
- Configure Claude Code's statusLine setting
- Launch the setup wizard (if first time)

### 3. Restart

Restart your Claude Code session to see the status line.

### Reconfigure

```bash
cd ~/cyberpunk-statusline && ./configure.sh
```

### Update

```bash
cd ~/cyberpunk-statusline && git pull
```

### Uninstall

```bash
cd ~/cyberpunk-statusline && ./uninstall.sh
```
```

Remove all references to `/plugin`, `/reload-plugins`, marketplace, etc.

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: README 改為 p10k 風格安裝說明 — git clone + install.sh"
```

---

### Task 8: Update LOG.md and final verification

**Files:**
- Modify: `LOG.md`

- [ ] **Step 1: Run all tests**

```bash
cd ~/Documents/VibeCoding/cyberpunk-statusline
bash tests/test-statusline.sh
bash tests/test-configure.sh
```

Expected: all pass.

- [ ] **Step 2: Test install.sh in dry-run fashion**

```bash
# Verify the script parses without syntax errors
bash -n install.sh
bash -n uninstall.sh
bash -n configure.sh
bash -n statusline.sh
```

Expected: no errors.

- [ ] **Step 3: Update LOG.md**

Add entry documenting the refactor from Claude plugin to p10k-style installation.

- [ ] **Step 4: Commit**

```bash
git add LOG.md
git commit -m "docs: LOG.md 記錄 p10k 風格安裝重構"
```
