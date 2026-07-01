#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_CONFIG="$SCRIPT_DIR/lib-config.sh"
DRY_RUN=false

usage() {
  echo "usage: uninstall-patched.sh [--dry-run]" >&2
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

CONFIG_TOML="${CODEX_CONFIG_TOML:-$HOME/.codex/config.toml}"
OUTPUT_BIN="${CODEX_OUTPUT_BIN_OVERRIDE:-$HOME/.local/bin/codex-cyberpunk}"

if [ "$DRY_RUN" = true ]; then
  echo "codex patched footer uninstaller (dry-run)"
else
  echo "codex patched footer uninstaller"
fi
echo "config file: $CONFIG_TOML"
echo "project root: $PROJECT_DIR"
echo "planned removals:"
echo "  - status_line_command in config when it points at this project"
echo "  - $OUTPUT_BIN"

if [ "$DRY_RUN" = true ]; then
  echo "dry-run: no files were changed"
  exit 0
fi

rm -f "$OUTPUT_BIN"
if [ -f "$CONFIG_TOML" ]; then
  # shellcheck source=/dev/null
  source "$LIB_CONFIG"
  _codex_remove_status_line_command "$CONFIG_TOML" "$PROJECT_DIR"
fi

echo "removed patched Codex binary: $OUTPUT_BIN"
echo "removed project-owned status_line_command from $CONFIG_TOML"
