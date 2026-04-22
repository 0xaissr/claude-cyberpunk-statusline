#!/usr/bin/env bash
# ╔══════════════════════════════════════════╗
# ║  cyberpunk-statusline uninstaller        ║
# ╚══════════════════════════════════════════╝
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_lib_tab_state.sh"

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

# Tear down tab-state hooks if present
if [ -L "$HOME/.claude/scripts/tab-state.sh" ] || \
   ( [ -f "$HOME/.claude/settings.json" ] && \
     grep -q 'tab-state.sh' "$HOME/.claude/settings.json" 2>/dev/null ); then
  echo "→ Removing iTerm2 tab-state hooks..."
  if _remove_tab_state_hooks; then
    echo "  ✓ tab-state hooks removed"
  else
    echo "  ✗ tab-state hooks removal failed — inspect ~/.claude/settings.json"
  fi
fi

echo ""
echo "  ✔ Uninstall complete."
echo "    You can now safely delete this directory."
echo "    Restart your Claude Code session to apply changes."
echo ""
