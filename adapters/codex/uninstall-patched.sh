#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DRY_RUN=false

usage() {
  echo "usage: uninstall-patched.sh --dry-run" >&2
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
  echo "uninstall-patched.sh currently supports --dry-run only." >&2
  exit 2
fi

CONFIG_TOML="${CODEX_CONFIG_TOML:-$HOME/.codex/config.toml}"
OUTPUT_BIN="$HOME/.local/bin/codex-cyberpunk"

echo "codex patched footer uninstaller (dry-run)"
echo "config file: $CONFIG_TOML"
echo "project root: $PROJECT_DIR"
echo "planned removals:"
echo "  - status_line_command in config when it points at this project"
echo "  - $OUTPUT_BIN"
echo "dry-run: no files were changed"
