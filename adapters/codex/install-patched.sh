#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DRY_RUN=false

usage() {
  echo "usage: install-patched.sh --dry-run" >&2
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [ "$DRY_RUN" != true ]; then
  echo "install-patched.sh currently supports --dry-run only." >&2
  exit 2
fi

CODEX_BIN="${CODEX_BIN_OVERRIDE:-$(command -v codex 2>/dev/null || true)}"
if [ -z "$CODEX_BIN" ]; then
  echo "codex binary not found. Set CODEX_BIN_OVERRIDE or install Codex first." >&2
  exit 1
fi

RENDERER_CMD="bash \"$PROJECT_DIR/adapters/codex/statusline.sh\" --line"
OUTPUT_BIN="$HOME/.local/bin/codex-cyberpunk"
SOURCE_CACHE="${CODEX_PATCH_CACHE:-$HOME/.cache/cyberpunk-statusline/codex-source}"

echo "codex patched footer installer (dry-run)"
echo "current codex: $CODEX_BIN"
echo "renderer command: $RENDERER_CMD"
echo "source cache: $SOURCE_CACHE"
echo "output binary: $OUTPUT_BIN"
echo "actions:"
echo "  - clone or update OpenAI Codex source"
echo "  - apply cyberpunk status_line_command patch"
echo "  - build patched Codex"
echo "  - install as codex-cyberpunk"
echo "dry-run: no files were changed"
