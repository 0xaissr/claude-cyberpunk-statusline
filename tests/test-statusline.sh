#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STATUSLINE="$PROJECT_DIR/scripts/statusline.sh"
SAMPLE="$SCRIPT_DIR/sample-input.json"

PASS=0
FAIL=0

test_exists() {
  if [[ -f "$STATUSLINE" ]] && [[ -x "$STATUSLINE" ]]; then
    echo "✓ test_exists: statusline.sh exists and is executable"
    ((PASS++))
  else
    echo "✗ test_exists: statusline.sh does not exist or is not executable"
    ((FAIL++))
  fi
}

test_default_output() {
  if [[ ! -f "$STATUSLINE" ]]; then
    echo "✗ test_default_output: statusline.sh not found, skipping"
    ((FAIL++))
    return
  fi

  output=$(cat "$SAMPLE" | bash "$STATUSLINE" 2>/dev/null || true)
  if [[ -n "$output" ]]; then
    echo "✓ test_default_output: produced non-empty output"
    ((PASS++))
  else
    echo "✗ test_default_output: output is empty"
    ((FAIL++))
  fi
}

test_theme_json() {
  local themes_dir="$PROJECT_DIR/themes"

  if [[ ! -d "$themes_dir" ]]; then
    echo "⊘ test_theme_json: themes directory not found, skipping"
    return
  fi

  local all_valid=true
  while IFS= read -r theme_file; do
    if ! jq empty "$theme_file" 2>/dev/null; then
      echo "✗ test_theme_json: $theme_file is not valid JSON"
      ((FAIL++))
      all_valid=false
    fi
  done < <(find "$themes_dir" -maxdepth 1 -name "*.json" -type f)

  if $all_valid && [[ $(find "$themes_dir" -maxdepth 1 -name "*.json" -type f | wc -l) -gt 0 ]]; then
    echo "✓ test_theme_json: all theme files are valid JSON"
    ((PASS++))
  elif [[ $(find "$themes_dir" -maxdepth 1 -name "*.json" -type f | wc -l) -eq 0 ]]; then
    echo "⊘ test_theme_json: no theme files found"
  fi
}

test_each_theme() {
  local themes_dir="$PROJECT_DIR/themes"

  if [[ ! -d "$themes_dir" ]]; then
    echo "⊘ test_each_theme: themes directory not found, skipping"
    return
  fi

  if [[ ! -f "$STATUSLINE" ]]; then
    echo "✗ test_each_theme: statusline.sh not found, skipping"
    ((FAIL++))
    return
  fi

  local all_passed=true
  while IFS= read -r theme_file; do
    local theme_name=$(basename "$theme_file" .json)
    local config_tmp=$(mktemp)

    cat > "$config_tmp" <<EOF
{
  "theme": "$theme_name",
  "spacing_mode": "normal"
}
EOF

    local output=$(cat "$SAMPLE" | CONFIG_OVERRIDE="$config_tmp" bash "$STATUSLINE" 2>/dev/null || true)
    rm -f "$config_tmp"

    if [[ -n "$output" ]]; then
      echo "✓ test_each_theme: theme '$theme_name' produced output"
      ((PASS++))
    else
      echo "✗ test_each_theme: theme '$theme_name' produced empty output"
      ((FAIL++))
      all_passed=false
    fi
  done < <(find "$themes_dir" -maxdepth 1 -name "*.json" -type f)

  if [[ $(find "$themes_dir" -maxdepth 1 -name "*.json" -type f | wc -l) -eq 0 ]]; then
    echo "⊘ test_each_theme: no theme files found"
  fi
}

test_spacing_modes() {
  if [[ ! -f "$STATUSLINE" ]]; then
    echo "✗ test_spacing_modes: statusline.sh not found, skipping"
    ((FAIL++))
    return
  fi

  local modes=("compact" "ultra-compact")
  local all_passed=true

  for mode in "${modes[@]}"; do
    local config_tmp=$(mktemp)

    cat > "$config_tmp" <<EOF
{
  "spacing_mode": "$mode"
}
EOF

    local output=$(cat "$SAMPLE" | CONFIG_OVERRIDE="$config_tmp" bash "$STATUSLINE" 2>/dev/null || true)
    rm -f "$config_tmp"

    if [[ -n "$output" ]]; then
      echo "✓ test_spacing_modes: mode '$mode' produced output"
      ((PASS++))
    else
      echo "✗ test_spacing_modes: mode '$mode' produced empty output"
      ((FAIL++))
      all_passed=false
    fi
  done
}

main() {
  echo "Running cyberpunk-statusline tests..."
  echo "======================================"

  test_exists
  test_default_output
  test_theme_json
  test_each_theme
  test_spacing_modes

  echo "======================================"
  echo "Results: $PASS passed, $FAIL failed"

  if [[ $FAIL -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
}

main
