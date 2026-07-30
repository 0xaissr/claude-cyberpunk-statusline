#!/usr/bin/env bash
# ╔══════════════════════════════════════════╗
# ║  cyberpunk-statusline Codex installer    ║
# ╚══════════════════════════════════════════╝
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
THEMES_DIR="$SCRIPT_DIR/themes"
PATCHED_INSTALLER="${CODEX_PATCHED_INSTALLER_OVERRIDE:-$SCRIPT_DIR/adapters/codex/install-patched.sh}"
LIB_CONFIG="$SCRIPT_DIR/adapters/codex/lib-config.sh"
CODEX_STATUSLINE_CONFIG="${CODEX_STATUSLINE_CONFIG:-$SCRIPT_DIR/adapters/codex/config.json}"
CONFIG_TOML="${CODEX_CONFIG_TOML:-$HOME/.codex/config.toml}"
RENDERER_CMD="CODEX_STATUSLINE_CONFIG=\"$CODEX_STATUSLINE_CONFIG\" bash \"$SCRIPT_DIR/adapters/codex/statusline.sh\" --line"
OFFICIAL_STATUS_LINE='["model-with-reasoning", "project-name", "five-hour-limit", "weekly-limit", "run-state", "context-used"]'
DRY_RUN=false
SELECTED_THEME=""
ALIAS_MODE="ask"
INSTALL_MODE="official"

usage() {
  cat >&2 <<'EOF'
usage: install-codex.sh [--dry-run] [--theme THEME] [--official|--patched] [--alias|--no-alias]
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --official|--native) INSTALL_MODE="official" ;;
    --patched) INSTALL_MODE="patched" ;;
    --alias) ALIAS_MODE="yes" ;;
    --no-alias) ALIAS_MODE="no" ;;
    --theme=*) SELECTED_THEME="${1#--theme=}" ;;
    --theme)
      shift
      SELECTED_THEME="${1:-}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
  shift || true
done

if [ "$INSTALL_MODE" = "official" ] && [ "$ALIAS_MODE" = "ask" ]; then
  ALIAS_MODE="no"
fi

JQ=$(command -v jq 2>/dev/null || echo "/opt/homebrew/bin/jq")
if ! "$JQ" --version >/dev/null 2>&1; then
  echo "jq is required but not found. Install with: brew install jq" >&2
  exit 1
fi

theme_exists() {
  local theme="$1"
  [ -n "$theme" ] && { [ -f "$THEMES_DIR/$theme.json" ] || [ -f "$THEMES_DIR/$theme/theme.json" ]; }
}

theme_ids() {
  find "$THEMES_DIR" -maxdepth 1 \( -name '*.json' -type f -o -type d \) -print \
    | while IFS= read -r path; do
        if [ -f "$path" ]; then
          basename "$path" .json
        elif [ -f "$path/theme.json" ]; then
          basename "$path"
        fi
      done \
    | sort
}

choose_theme() {
  if [ -n "$SELECTED_THEME" ]; then
    return
  fi

  echo "Step 1/4: choose Codex theme"
  local themes=()
  while IFS= read -r theme; do
    themes+=("$theme")
  done < <(theme_ids)

  local i
  for i in "${!themes[@]}"; do
    printf "  %2d. %s\n" "$((i + 1))" "${themes[$i]}"
  done

  printf "Select theme [1-%d] (default: tokyo-night): " "${#themes[@]}"
  local answer
  read -r answer
  if [ -z "$answer" ]; then
    SELECTED_THEME="tokyo-night"
  elif [[ "$answer" =~ ^[0-9]+$ ]] && [ "$answer" -ge 1 ] && [ "$answer" -le "${#themes[@]}" ]; then
    SELECTED_THEME="${themes[$((answer - 1))]}"
  else
    SELECTED_THEME="$answer"
  fi
}

write_codex_config() {
  local dest="$1" theme="$2" tmp
  tmp=$(mktemp)
  "$JQ" -n --arg theme "$theme" '{
    theme: $theme,
    symbol_set: "nerd",
    spacing: "ultra-compact",
    style: "rainbow",
    separator: "",
    head: "rounded",
    tail: "sharp",
    blocks: ["model", "context", "tokens", "rate_5h", "rate_7d", "cost", "burn", "git", "time"],
    bar_width: 6,
    bar_filled: "●",
    bar_empty: "○",
    show_icons: true,
    time_format: "24h",
    account_type: "subscription"
  }' > "$tmp"

  mkdir -p "$(dirname "$dest")"
  mv "$tmp" "$dest"
}

ensure_alias() {
  local zshrc="$HOME/.zshrc"
  local alias_line='alias codex="$HOME/.local/bin/codex-cyberpunk"'

  if [ "$ALIAS_MODE" = "ask" ]; then
    printf "Step 4/4: make 'codex' launch codex-cyberpunk? [Y/n]: "
    local answer
    read -r answer
    case "$answer" in
      n|N|no|NO) ALIAS_MODE="no" ;;
      *) ALIAS_MODE="yes" ;;
    esac
  fi

  [ "$ALIAS_MODE" = "yes" ] || return 0
  touch "$zshrc"
  if grep -Fq "$alias_line" "$zshrc"; then
    return 0
  fi
  {
    echo ""
    echo "# Use the patched Codex build with the cyberpunk statusline by default."
    echo "$alias_line"
  } >> "$zshrc"
}

write_official_codex_config() {
  # shellcheck source=/dev/null
  source "$LIB_CONFIG"
  mkdir -p "$(dirname "$CONFIG_TOML")"
  _codex_remove_status_line_command "$CONFIG_TOML" "$SCRIPT_DIR"
  _codex_set_status_line "$CONFIG_TOML" "$OFFICIAL_STATUS_LINE"
}

choose_theme

if ! theme_exists "$SELECTED_THEME"; then
  echo "unknown theme: $SELECTED_THEME" >&2
  echo "available themes:" >&2
  theme_ids >&2
  exit 1
fi

echo ""
if [ "$DRY_RUN" = true ]; then
  echo "codex statusline installer (dry-run)"
else
  echo "codex statusline installer"
fi
echo "mode: $INSTALL_MODE"
echo "theme: $SELECTED_THEME"
echo "Codex statusline config: $CODEX_STATUSLINE_CONFIG"
echo "Codex TOML config: $CONFIG_TOML"
if [ "$INSTALL_MODE" = "patched" ]; then
  echo "renderer command: $RENDERER_CMD"
  echo "patched installer: $PATCHED_INSTALLER"
fi
echo "alias codex: $ALIAS_MODE"
echo "actions:"
echo "  - write adapters/codex/config.json"
if [ "$INSTALL_MODE" = "official" ]; then
  echo "  - write official tui.status_line items into Codex config"
  echo "  - skip patched Codex build"
  echo "note: official Codex does not currently support command-rendered cyberpunk status lines"
else
  echo "  - run adapters/codex/install-patched.sh"
  echo "  - optionally add shell alias for codex"
fi

if [ "$DRY_RUN" = true ]; then
  if [ "$INSTALL_MODE" = "official" ]; then
    echo "would write: $CODEX_STATUSLINE_CONFIG"
    echo "would set: [tui].status_line in $CONFIG_TOML"
  else
    echo "would run: CODEX_STATUSLINE_CONFIG=\"$CODEX_STATUSLINE_CONFIG\" $PATCHED_INSTALLER --dry-run"
    echo "delegates: adapters/codex/install-patched.sh --dry-run"
  fi
  echo "dry-run: no files were changed"
  exit 0
fi

echo ""
echo "Step 2/4: writing Codex statusline config"
write_codex_config "$CODEX_STATUSLINE_CONFIG" "$SELECTED_THEME"

if [ "$INSTALL_MODE" = "official" ]; then
  echo "Step 3/4: configuring official Codex status line"
  write_official_codex_config
  echo "Skipping patched Codex build."
else
  echo "Step 3/4: installing patched Codex"
  CODEX_STATUSLINE_CONFIG="$CODEX_STATUSLINE_CONFIG" "$PATCHED_INSTALLER"
  ensure_alias
fi

echo ""
echo "Codex statusline installation complete."
echo "Run: codex"
