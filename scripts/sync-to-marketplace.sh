#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════╗
# ║  sync-to-marketplace.sh                         ║
# ║  同步開發目錄到 marketplace repo 並推送更新     ║
# ╚══════════════════════════════════════════════════╝

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────
DEV_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MARKETPLACE_DIR="$HOME/.claude/plugins/marketplaces/cyberpunk-statusline-marketplace"
PLUGIN_DIR="$MARKETPLACE_DIR/cyberpunk-statusline"
CACHE_DIR="$HOME/.claude/plugins/cache/cyberpunk-statusline-marketplace/cyberpunk-statusline/1.0.0"

# ── Preflight checks ─────────────────────────────────────────────────────
if [ ! -d "$MARKETPLACE_DIR/.git" ]; then
  echo "❌ Marketplace repo not found at: $MARKETPLACE_DIR"
  exit 1
fi

if [ ! -d "$DEV_DIR/scripts" ] || [ ! -d "$DEV_DIR/themes" ]; then
  echo "❌ Dev directory doesn't look right: $DEV_DIR"
  exit 1
fi

# ── Sync to marketplace repo ─────────────────────────────────────────────
echo "📦 Syncing dev → marketplace repo..."

rsync -av --delete \
  --exclude='.git' \
  --exclude='.claude' \
  --exclude='docs' \
  --exclude='LOG.md' \
  --exclude='scripts/debug-keys.sh' \
  --exclude='scripts/sync-to-marketplace.sh' \
  "$DEV_DIR/" \
  "$PLUGIN_DIR/"

echo ""

# ── Sync to local cache (immediate effect) ────────────────────────────────
if [ -d "$CACHE_DIR" ]; then
  echo "⚡ Syncing to local plugin cache (immediate effect)..."
  rsync -av --delete \
    --exclude='.git' \
    --exclude='.claude' \
    --exclude='docs' \
    --exclude='LOG.md' \
    --exclude='scripts/debug-keys.sh' \
    --exclude='scripts/sync-to-marketplace.sh' \
    "$DEV_DIR/" \
    "$CACHE_DIR/"
  echo ""
fi

# ── Show changes ──────────────────────────────────────────────────────────
echo "📋 Marketplace repo changes:"
cd "$MARKETPLACE_DIR"
git status --short

if [ -z "$(git status --porcelain)" ]; then
  echo "✅ No changes — marketplace is already up to date."
  exit 0
fi

# ── Commit & push ─────────────────────────────────────────────────────────
echo ""
read -p "🚀 Commit & push to GitHub? [y/N] " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
  # Get version from dev plugin.json
  VERSION=$(jq -r '.version // "1.0.0"' "$DEV_DIR/.claude-plugin/plugin.json" 2>/dev/null || echo "1.0.0")

  git add -A
  read -p "📝 Commit message (default: 'sync v$VERSION'): " msg
  msg="${msg:-sync v$VERSION}"

  git -c user.name="0xaissr" -c user.email="0xaissr@gmail.com" commit -m "$msg"
  BRANCH=$(git symbolic-ref --short HEAD)
  git push origin "$BRANCH"

  echo ""
  echo "✅ Done! Marketplace updated."
  echo "   Users can reinstall to get the latest version."
else
  echo "⏸️  Skipped push. Changes are staged in: $MARKETPLACE_DIR"
  echo "   Run manually:"
  echo "     cd $MARKETPLACE_DIR && git add -A && git commit -m 'update' && git push"
fi
