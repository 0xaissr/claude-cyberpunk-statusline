#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_CONFIG="$SCRIPT_DIR/lib-config.sh"
DRY_RUN=false

usage() {
  echo "usage: install-patched.sh [--dry-run]" >&2
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

CODEX_BIN="${CODEX_BIN_OVERRIDE:-$(command -v codex 2>/dev/null || true)}"
if [ -z "$CODEX_BIN" ]; then
  echo "codex binary not found. Set CODEX_BIN_OVERRIDE or install Codex first." >&2
  exit 1
fi

STATUSLINE_CONFIG="${CODEX_STATUSLINE_CONFIG:-$PROJECT_DIR/adapters/codex/config.json}"
RENDERER_CMD="CODEX_STATUSLINE_CONFIG=\"$STATUSLINE_CONFIG\" bash \"$PROJECT_DIR/adapters/codex/statusline.sh\" --line"
OUTPUT_BIN="${CODEX_OUTPUT_BIN_OVERRIDE:-$HOME/.local/bin/codex-cyberpunk}"
SOURCE_CACHE="${CODEX_PATCH_CACHE:-$HOME/.cache/cyberpunk-statusline/codex-source}"
SOURCE_REPO="${CODEX_SOURCE_REPO_OVERRIDE:-https://github.com/openai/codex.git}"
SOURCE_REF="${CODEX_SOURCE_REF:-rust-v0.142.5}"
PATCH_FILE="$PROJECT_DIR/adapters/codex/patches/status-line-command.patch"
CONFIG_TOML="${CODEX_CONFIG_TOML:-$HOME/.codex/config.toml}"

if [ "$DRY_RUN" = true ]; then
  echo "codex patched footer installer (dry-run)"
else
  echo "codex patched footer installer"
fi
echo "current codex: $CODEX_BIN"
echo "renderer command: $RENDERER_CMD"
echo "statusline config: $STATUSLINE_CONFIG"
echo "source repo: $SOURCE_REPO"
echo "source ref: $SOURCE_REF"
echo "source cache: $SOURCE_CACHE"
echo "patch file: $PATCH_FILE"
echo "output binary: $OUTPUT_BIN"
echo "config file: $CONFIG_TOML"
echo "actions:"
echo "  - clone or update OpenAI Codex source"
echo "  - apply cyberpunk status_line_command patch"
echo "  - build patched Codex"
echo "  - install as codex-cyberpunk"
echo "safety: unsupported Codex source revisions must stop before patch/build"

if [ "$DRY_RUN" = true ]; then
  echo "dry-run: no files were changed"
  exit 0
fi

if [ ! -f "$PATCH_FILE" ]; then
  echo "patch file not found: $PATCH_FILE" >&2
  exit 1
fi

mkdir -p "$(dirname "$SOURCE_CACHE")"
if [ -d "$SOURCE_CACHE/.git" ]; then
  git -C "$SOURCE_CACHE" fetch --tags --quiet
  git -C "$SOURCE_CACHE" checkout --quiet "$SOURCE_REF"
  git -C "$SOURCE_CACHE" reset --hard --quiet "$SOURCE_REF"
else
  rm -rf "$SOURCE_CACHE"
  git clone --quiet --branch "$SOURCE_REF" --depth 1 "$SOURCE_REPO" "$SOURCE_CACHE"
fi

if git -C "$SOURCE_CACHE" apply --check "$PATCH_FILE"; then
  git -C "$SOURCE_CACHE" apply "$PATCH_FILE"
elif git -C "$SOURCE_CACHE" apply --reverse --check "$PATCH_FILE"; then
  echo "patch already applied"
else
  echo "patch does not apply cleanly to $SOURCE_REF" >&2
  exit 1
fi

cargo build --release -p codex-cli --bin codex --manifest-path "$SOURCE_CACHE/codex-rs/Cargo.toml"

mkdir -p "$(dirname "$OUTPUT_BIN")" "$(dirname "$CONFIG_TOML")"
install -m 0755 "$SOURCE_CACHE/codex-rs/target/release/codex" "$OUTPUT_BIN"

# shellcheck source=/dev/null
source "$LIB_CONFIG"
_codex_set_status_line_command "$CONFIG_TOML" "$RENDERER_CMD"

echo "installed patched Codex: $OUTPUT_BIN"
echo "configured status_line_command in $CONFIG_TOML"
