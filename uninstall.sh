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
