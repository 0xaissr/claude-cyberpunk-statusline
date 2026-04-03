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
