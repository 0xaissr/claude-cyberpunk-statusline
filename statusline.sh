#!/usr/bin/env bash
# ╔══════════════════════════════════════════╗
# ║  cyberpunk-statusline rendering engine   ║
# ╚══════════════════════════════════════════╝

# ── Read stdin ─────────────────────────────────────────────────────────────
input=$(cat)

# ── Resolve paths ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${CONFIG_OVERRIDE:-$SCRIPT_DIR/config.json}"
JQ=$(command -v jq 2>/dev/null || echo "/opt/homebrew/bin/jq")
if ! "$JQ" --version >/dev/null 2>&1; then
  echo "cyberpunk-statusline: jq is required but not found"
  exit 0
fi
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# ── Shared pricing table ───────────────────────────────────────────────────
# 單一定價來源：cost 區塊（_refresh_cost 的本地 JSONL fallback）與
# session/last_chat 區塊（_scan_transcript）都要用同一份單價，否則同一條
# status line 上兩邊金額可能對不上。兩處都用字串接續的方式把這段 jq 片段
# 接進各自的 jq 程式（見下方兩處用法），數字本身沒有變動，純粹去重複。
JQ_PRICE_FN='def price($m):
  if   ($m | startswith("claude-opus"))   then {i: 15, o: 75, cw: 18.75, cr: 1.50}
  elif ($m | startswith("claude-sonnet")) then {i: 3,  o: 15, cw: 3.75,  cr: 0.30}
  elif ($m | startswith("claude-haiku"))  then {i: 1,  o: 5,  cw: 1.25,  cr: 0.10}
  else {i: 15, o: 75, cw: 18.75, cr: 1.50} end;'

# ── Helpers ────────────────────────────────────────────────────────────────
hex_to_fg() {
  local hex="${1#\#}"
  printf '\033[38;2;%d;%d;%dm' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

hex_to_bg() {
  local hex="${1#\#}"
  printf '\033[48;2;%d;%d;%dm' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

make_bar() {
  local pct="${1:-0}" width="${2:-10}" filled_char="${3:-█}" empty_char="${4:-░}"
  local filled=$(awk "BEGIN{v=int($pct*$width/100+0.5); if(v>$width) v=$width; if(v<0) v=0; print v}")
  local empty=$(($width - $filled))
  local bar=""
  local i
  for ((i=0; i<filled; i++)); do bar+="$filled_char"; done
  for ((i=0; i<empty; i++)); do bar+="$empty_char"; done
  printf "%s" "$bar"
}

neon_colour() {
  local pct="${1:-0}" neon_hex="$2" warn_hex="$3" alert_hex="$4"
  local v=$(printf "%.0f" "$pct" 2>/dev/null || echo 0)
  if   [ "$v" -ge 80 ]; then hex_to_fg "$alert_hex"
  elif [ "$v" -ge 50 ]; then hex_to_fg "$warn_hex"
  else                       hex_to_fg "$neon_hex"
  fi
}

# ── Burn-rate libraries ────────────────────────────────────────────────────
source "$SCRIPT_DIR/core/usage-history.sh"
source "$SCRIPT_DIR/core/burn-rate.sh"

# ── Load config ────────────────────────────────────────────────────────────
if [ ! -f "$CONFIG" ]; then
  echo "cyberpunk-statusline: run /cyberpunk-statusline configure"
  exit 0
fi

cfg_theme=$("$JQ" -r '.theme // "terminal-glitch"' "$CONFIG")
cfg_symbols=$("$JQ" -r '.symbol_set // "unicode"' "$CONFIG")
cfg_spacing=$("$JQ" -r '.spacing // "normal"' "$CONFIG")
cfg_separator=$("$JQ" -r '.separator // "│"' "$CONFIG")
cfg_style=$("$JQ" -r '.style // "classic"' "$CONFIG")
cfg_head=$("$JQ" -r '.head // "sharp"' "$CONFIG")
cfg_tail=$("$JQ" -r '.tail // "sharp"' "$CONFIG")
cfg_bar_width=$("$JQ" -r '.bar_width // 10' "$CONFIG")
cfg_bar_filled=$("$JQ" -r '.bar_filled // ""' "$CONFIG")
cfg_bar_empty=$("$JQ" -r '.bar_empty // ""' "$CONFIG")
cfg_show_icons=$("$JQ" -r 'if .show_icons == false then "false" else "true" end' "$CONFIG")
cfg_time_format=$("$JQ" -r '.time_format // "24h"' "$CONFIG")
cfg_account_type=$("$JQ" -r '.account_type // "auto"' "$CONFIG")
cfg_blocks=$("$JQ" -r '.blocks // ["model","context","rate_5h","rate_7d","cost","burn","directory","git","time"] | .[]' "$CONFIG")
cfg_blocks_line2=$("$JQ" -r '.blocks_line2 // [] | .[]' "$CONFIG")

# ── Resolve theme ──────────────────────────────────────────────────────────
THEME_DIR="$SCRIPT_DIR/themes"

# Check for custom renderer (directory with render.sh)
if [ -d "$THEME_DIR/$cfg_theme" ] && [ -f "$THEME_DIR/$cfg_theme/render.sh" ]; then
  THEME_FILE="$THEME_DIR/$cfg_theme/theme.json"
else
  THEME_FILE="$THEME_DIR/$cfg_theme.json"
fi

if [ ! -f "$THEME_FILE" ]; then
  echo "cyberpunk-statusline: theme '$cfg_theme' not found"
  exit 0
fi

# ── Read theme colors ─────────────────────────────────────────────────────
color() { "$JQ" -r ".colors.$1 // \"#888888\"" "$THEME_FILE"; }

C_BG_PRIMARY=$(color bg_primary)
C_BG_PANEL=$(color bg_panel)
C_ACCENT_1=$(color accent_1)
C_ACCENT_2=$(color accent_2)
C_ACCENT_3=$(color accent_3)
C_WARNING=$(color warning)
C_ALERT=$(color alert)
C_SEP=$(color separator)
C_DIM=$(color dim)

# ── Read theme symbols ────────────────────────────────────────────────────
sym() { "$JQ" -r ".symbols.$cfg_symbols.$1 // \"?\"" "$THEME_FILE"; }

S_MODEL=$(sym model)
S_CTX=$(sym context)
S_5H=$(sym rate_5h)
S_7D=$(sym rate_7d)
S_DIR=$(sym directory)
S_GIT=$(sym git)
S_TIME=$(sym time)
S_BAR_FILLED=$(sym bar_filled)
S_BAR_EMPTY=$(sym bar_empty)
S_COST=$(sym cost)
S_SPEND=$(sym spend)
[ "$S_SPEND" = "?" ] && S_SPEND="$S_COST"
S_CREDIT=$(sym credit)
[ "$S_CREDIT" = "?" ] && S_CREDIT="$S_SPEND"
S_BURN=$(sym burn)
[ "$S_BURN" = "?" ] && S_BURN="󱐋"
S_SESSION=$(sym session)
[ "$S_SESSION" = "?" ] && S_SESSION=$(sym tokens)
[ "$S_SESSION" = "?" ] && S_SESSION="⇅"
S_LAST_CHAT=$(sym last_chat)
[ "$S_LAST_CHAT" = "?" ] && S_LAST_CHAT="⌯"

# Clear icons if show_icons is disabled
if [ "$cfg_show_icons" = "false" ]; then
  S_MODEL="" S_CTX="" S_5H="" S_7D="" S_DIR="" S_GIT="" S_TIME="" S_COST="" S_SPEND="" S_CREDIT="" S_BURN="" S_SESSION="" S_LAST_CHAT=""
fi

# ── Read block color mappings ─────────────────────────────────────────────
block_color() {
  local ref=$("$JQ" -r ".blocks.$1.color // \"accent_1\"" "$THEME_FILE")
  color "$ref"
}
block_bg() {
  local ref=$("$JQ" -r ".blocks.$1.bg // \"bg_panel\"" "$THEME_FILE")
  color "$ref"
}
# Rainbow: use accent color as bg, dark text as fg
pl_block_bg() {
  local ref=$("$JQ" -r ".blocks.$1.pl_bg // .blocks.$1.color // \"accent_1\"" "$THEME_FILE")
  color "$ref"
}
pl_block_fg() {
  local ref=$("$JQ" -r ".blocks.$1.pl_fg // \"bg_primary\"" "$THEME_FILE")
  color "$ref"
}

# Detect rainbow mode (also support legacy separator-based detection)
PL_MODE=false
if [ "$cfg_style" = "rainbow" ] || [ "$cfg_separator" = "" ] || [ "$cfg_separator" = "" ]; then
  PL_MODE=true
  # Head = left opening of first segment; Tail = right separator / closing glyph
  # Nerd Font Powerline glyphs:
  #   Sharp:    (E0B0) /  (E0B2)
  #   Slanted:  (E0BC) /  (E0BA)  — Powerline Extra
  #   Rounded:  (E0B4) /  (E0B6)  — Powerline Extra
  #   Flat:     no glyph, just rectangular block edges
  case "$cfg_head" in
    sharp)    PL_HEAD_OPEN="" ;;
    slanted)  PL_HEAD_OPEN="" ;;
    rounded)  PL_HEAD_OPEN="" ;;
    *)        PL_HEAD_OPEN="" ;;
  esac
  case "$cfg_tail" in
    sharp)    PL_TAIL_SEP="" ;;
    slanted)  PL_TAIL_SEP="" ;;
    rounded)  PL_TAIL_SEP="" ;;
    *)        PL_TAIL_SEP="" ;;
  esac
fi

# ── Parse stdin JSON ──────────────────────────────────────────────────────
model=$(echo "$input" | "$JQ" -r '.model.display_name // "UNKNOWN"')
# Read effort level from ~/.claude/settings.json (low/medium/high) and capitalize
effort_level=""
if [ -f "$HOME/.claude/settings.json" ]; then
  effort_level=$("$JQ" -r '.effortLevel // empty' "$HOME/.claude/settings.json" 2>/dev/null)
fi
effort_cap=""
if [ -n "$effort_level" ]; then
  effort_cap="$(tr '[:lower:]' '[:upper:]' <<< "${effort_level:0:1}")${effort_level:1}"
fi
# Merge effort into the "(1M context)" marker → "(1M.High)"; otherwise append as "(High)"
if [[ "$model" == *"(1M context)"* ]]; then
  if [ -n "$effort_cap" ]; then
    model="${model//(1M context)/(1M.${effort_cap})}"
  else
    model="${model//(1M context)/(1M)}"
  fi
elif [ -n "$effort_cap" ]; then
  model="${model} (${effort_cap})"
fi
used_pct=$(echo "$input" | "$JQ" -r '.context_window.used_percentage // empty')
five_pct=$(echo "$input" | "$JQ" -r 'if (.rate_limits.five_hour.used_percentage | type) == "number" then .rate_limits.five_hour.used_percentage else empty end')
five_reset=$(echo "$input" | "$JQ" -r '.rate_limits.five_hour.resets_at // empty')
week_pct=$(echo "$input" | "$JQ" -r 'if (.rate_limits.seven_day.used_percentage | type) == "number" then .rate_limits.seven_day.used_percentage else empty end')
week_reset=$(echo "$input" | "$JQ" -r '.rate_limits.seven_day.resets_at // empty')
cwd=$(echo "$input" | "$JQ" -r '.workspace.current_dir // .cwd // "?"')
session_id=$(echo "$input" | "$JQ" -r '.session_id // empty')
transcript_path=$(echo "$input" | "$JQ" -r '.transcript_path // empty')
case "$cfg_time_format" in
  12h)        now=$(date +"%I:%M:%S %p") ;;
  24h-no-sec) now=$(date +"%H:%M") ;;
  12h-no-sec) now=$(date +"%-I:%M %p") ;;
  24h-date)   now=$(date +"%m/%d %H:%M") ;;
  12h-date)   now=$(date +"%m/%d %-I:%M %p") ;;
  *)          now=$(date +"%H:%M:%S") ;;
esac
git_branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || true)
# Fallback: use the repo where statusline.sh lives (useful for preview)
if [ -z "$git_branch" ]; then
  git_branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$SCRIPT_DIR" symbolic-ref --short HEAD 2>/dev/null || true)
fi

# ── Daily cost (cached, foreground refresh) ───────────────────────────────
COST_CACHE_DIR="$HOME/.cache/cyberpunk-statusline"
COST_CACHE="$COST_CACHE_DIR/daily-cost"
COST_CACHE_MAX_AGE=30  # 30 seconds — short enough to refresh after each chat
daily_cost=""

# Read cached value
if [ -f "$COST_CACHE" ]; then
  daily_cost=$(cat "$COST_CACHE" 2>/dev/null)
fi

_refresh_cost() {
  mkdir -p "$COST_CACHE_DIR"
  local val=""

  # Primary: ccusage (online pricing). Don't pass --offline because the
  # bundled pricing table lags behind new model IDs like claude-opus-4-7
  # (prices them as $0). Online mode fetches from LiteLLM's pricing repo
  # which is updated more quickly.
  if command -v ccusage >/dev/null 2>&1; then
    val=$(ccusage claude daily --jq '.totals.totalCost' --since "$(date +%Y%m%d)" 2>/dev/null)
  elif command -v npx >/dev/null 2>&1; then
    val=$(npx ccusage@latest claude daily --jq '.totals.totalCost' --since "$(date +%Y%m%d)" 2>/dev/null)
  fi

  # Fallback: local JSONL calc when ccusage unavailable or fails.
  # Uses startswith() so new model IDs inherit their family's pricing.
  if [ -z "$val" ] || [ "$val" = "null" ]; then
    local today=$(date +%Y-%m-%d)
    val=$(find "$HOME/.claude/projects" -name "*.jsonl" -maxdepth 2 2>/dev/null \
      | xargs grep -h '"type":"assistant"' 2>/dev/null \
      | "$JQ" -s --arg today "$today" '
        '"$JQ_PRICE_FN"'
        [ .[] | select(.timestamp | startswith($today)) |
          select(.message.id != null) |
          {k: (.message.id + "|" + (.requestId // "")), e: .}
        ] | group_by(.k) | map(.[0].e) |
        [ .[] | .message as $msg | $msg.usage as $u | price($msg.model) as $p |
          (($u.input_tokens // 0) * $p.i
           + ($u.output_tokens // 0) * $p.o
           + ($u.cache_creation_input_tokens // 0) * $p.cw
           + ($u.cache_read_input_tokens // 0) * $p.cr) / 1000000
        ] | add // 0
      ' 2>/dev/null)
  fi

  if [ -n "$val" ] && [ "$val" != "null" ]; then
    printf '%.2f' "$val" > "$COST_CACHE" 2>/dev/null
  fi
}

# Foreground refresh when stale — ensures current prompt shows latest cost
if [ ! -f "$COST_CACHE" ] || [ $(($(date +%s) - $(stat -f%m "$COST_CACHE" 2>/dev/null || echo 0))) -gt "$COST_CACHE_MAX_AGE" ]; then
  _refresh_cost
  daily_cost=$(cat "$COST_CACHE" 2>/dev/null)
fi

# ── Session tokens (cached, invalidated by transcript mtime) ──────────────
# 產出 session（本次對話累計）與 last_chat（最後一次 API 呼叫）各自的
# token 與金額。四類 token 全部計入（含 cache_read）——它佔實際花費約
# 一半，金額既然含它，token 也該含才對得起來。
session_tokens=""
session_cost=""
last_tokens=""
last_cost=""

# stdin's transcript_path is preferred; session_id is the documented fallback
# (it is present in the statusline schema, transcript_path is not guaranteed).
# Match the session id against the projects tree rather than deriving the
# directory slug from cwd — the slug mangles both '/' and '.' into '-'.
_resolve_transcript() {
  if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    printf '%s' "$transcript_path"
    return
  fi
  [ -n "$session_id" ] || return
  local f
  for f in "$HOME"/.claude/projects/*/"$session_id".jsonl; do
    [ -f "$f" ] || continue
    printf '%s' "$f"
    return
  done
}

# 單次掃描產出四個值：session 累計 token/金額、最後一次呼叫的 token/金額。
# 去重鍵 message.id|requestId 沿用 cost fallback 的慣例，重試不重複計算。
# 定價表與 _refresh_cost 共用同一份 $JQ_PRICE_FN（見檔案開頭），避免兩處
# 各自維護導致金額對不上；用 startswith 讓新 model ID 自動繼承家族單價。
# 四類 token 全部計入（含 cache_read）——金額必須含它，token 也含才對得起來。
_scan_transcript() {
  grep -h '"type":"assistant"' "$1" 2>/dev/null | "$JQ" -s -r '
    '"$JQ_PRICE_FN"'
    def tok($u): ($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0)
                 + ($u.cache_read_input_tokens // 0) + ($u.output_tokens // 0);
    def cost($e): $e.message as $msg | $msg.usage as $u | price($msg.model // "") as $p |
      (($u.input_tokens // 0) * $p.i
       + ($u.output_tokens // 0) * $p.o
       + ($u.cache_creation_input_tokens // 0) * $p.cw
       + ($u.cache_read_input_tokens // 0) * $p.cr) / 1000000;
    [ .[] | select(.message.id != null) ] | to_entries
    | map({k: (.value.message.id + "|" + (.value.requestId // "")), i: .key, e: .value})
    | group_by(.k) | map(.[0]) | sort_by(.i) | map(.e) as $msgs |
    ( [ $msgs[] | tok(.message.usage) ] | add // 0 ) as $st |
    ( [ $msgs[] | cost(.) ]             | add // 0 ) as $sc |
    ( if ($msgs | length) > 0 then ($msgs | last) else null end ) as $lastmsg |
    ( if $lastmsg == null then 0 else tok($lastmsg.message.usage) end ) as $lt |
    ( if $lastmsg == null then 0 else cost($lastmsg) end ) as $lc |
    "\($st)|\($sc)|\($lt)|\($lc)"
  ' 2>/dev/null
}

_transcript=""
# Override 短路整段 transcript 解析 —— 供 configure.sh 的即時預覽（樣本資料
# 沒有真實 session）、Codex adapter 與測試使用。
if [ -n "${SESSION_TOKENS_OVERRIDE:-}${SESSION_COST_OVERRIDE:-}${LAST_CHAT_TOKENS_OVERRIDE:-}${LAST_CHAT_COST_OVERRIDE:-}" ]; then
  session_tokens="${SESSION_TOKENS_OVERRIDE:-}"
  session_cost="${SESSION_COST_OVERRIDE:-}"
  last_tokens="${LAST_CHAT_TOKENS_OVERRIDE:-}"
  last_cost="${LAST_CHAT_COST_OVERRIDE:-}"
else
  _transcript=$(_resolve_transcript)
fi
if [ -n "$_transcript" ]; then
  _tokens_cache="$COST_CACHE_DIR/session-tokens-$(basename "$_transcript" .jsonl)"
  _t_mtime=$(stat -f%m "$_transcript" 2>/dev/null || echo 0)
  _c_mtime="" _c_st="" _c_sc="" _c_lt="" _c_lc=""
  # 舊版快取只有兩個欄位，讀進來 _c_lc 會是空的 → 視為 miss 重算。
  [ -f "$_tokens_cache" ] && IFS='|' read -r _c_mtime _c_st _c_sc _c_lt _c_lc < "$_tokens_cache"

  if [ -n "$_c_lc" ] && [ "$_c_mtime" = "$_t_mtime" ]; then
    session_tokens="$_c_st"; session_cost="$_c_sc"
    last_tokens="$_c_lt";    last_cost="$_c_lc"
  else
    _scanned=$(_scan_transcript "$_transcript")
    if [ -n "$_scanned" ]; then
      IFS='|' read -r session_tokens session_cost last_tokens last_cost <<< "$_scanned"
      mkdir -p "$COST_CACHE_DIR"
      printf '%s|%s\n' "$_t_mtime" "$_scanned" > "$_tokens_cache" 2>/dev/null
    fi
  fi
fi

# 840K / 12.4M —— 一律無條件捨去，避免 999,600 被進位成 "1000K" 這種跨單位的怪值
fmt_tokens() {
  awk -v n="${1:-0}" 'BEGIN{
    if (n >= 1000000)   printf "%.1fM", int(n/100000)/10
    else if (n >= 1000) printf "%dK", int(n/1000)
    else                printf "%d", n
  }'
}

# $1.89 / $0.3442 —— 小額用四位小數，否則兩位小數會全部塌成 $0.00
fmt_price() {
  awk -v v="${1:-}" 'BEGIN{
    if (v == "" || tolower(v) ~ /^[+-]?(nan|inf)/ || v + 0 != v) { printf "--"; exit }
    if (v >= 1) printf "%.2f", v
    else        printf "%.4f", v
  }'
}

# ── Usage / spend (cached, background refresh) ────────────────────────────
USAGE_CACHE="${USAGE_CACHE_OVERRIDE:-$COST_CACHE_DIR/usage.json}"
USAGE_CACHE_MAX_AGE=60

# Background-refresh when stale (skip entirely when a test override is set —
# the override supplies a fixed cache and must not trigger a network call).
if [ -z "${USAGE_CACHE_OVERRIDE:-}" ]; then
  if [ ! -f "$USAGE_CACHE" ] || [ $(($(date +%s) - $(stat -f%m "$USAGE_CACHE" 2>/dev/null || echo 0))) -gt "$USAGE_CACHE_MAX_AGE" ]; then
    mkdir -p "$COST_CACHE_DIR"
    ( "$SCRIPT_DIR/core/fetch-usage.sh" > "$USAGE_CACHE.tmp" 2>/dev/null && mv -f "$USAGE_CACHE.tmp" "$USAGE_CACHE" ) &
    disown 2>/dev/null || true
  fi
fi

# Read whatever the cache currently holds (may be from a previous render).
acct_type="unknown"
spend_used_cents="" spend_limit_cents="" spend_pct="" spend_currency="" spend_reset=""
credit_pct="" credit_reset=""
if [ -f "$USAGE_CACHE" ]; then
  acct_type=$("$JQ" -r '.account_type // "unknown"' "$USAGE_CACHE" 2>/dev/null || echo unknown)
  spend_used_cents=$("$JQ" -r '.spend.used_cents // empty' "$USAGE_CACHE" 2>/dev/null)
  spend_limit_cents=$("$JQ" -r '.spend.limit_cents // empty' "$USAGE_CACHE" 2>/dev/null)
  spend_pct=$("$JQ" -r '.spend.utilization // empty' "$USAGE_CACHE" 2>/dev/null)
  spend_currency=$("$JQ" -r '.spend.currency // "USD"' "$USAGE_CACHE" 2>/dev/null)
  spend_reset=$("$JQ" -r '.spend.resets_at // empty' "$USAGE_CACHE" 2>/dev/null)
  credit_pct=$("$JQ" -r '.credit.utilization // empty' "$USAGE_CACHE" 2>/dev/null)
  credit_reset=$("$JQ" -r '.credit.resets_at // empty' "$USAGE_CACHE" 2>/dev/null)
fi

# Effective account type: config override wins over detection.
case "$cfg_account_type" in
  subscription|quota) eff_account_type="$cfg_account_type" ;;
  *)                  eff_account_type="$acct_type" ;;
esac

# ── Record usage history for burn-rate tracking ───────────────────────────
# 依帳號類型挑指標：quota+credit→credit；quota→spend；否則→seven_day。
burn_metric="" burn_util="" burn_reset=""
if [ "$eff_account_type" = "quota" ]; then
  if [ -n "$credit_pct" ] && awk -v p="$credit_pct" 'BEGIN{exit !(p < 100)}'; then
    burn_metric="credit"; burn_util="$credit_pct"; burn_reset="$credit_reset"
  elif [ -n "$spend_pct" ]; then
    burn_metric="spend"; burn_util="$spend_pct"; burn_reset="$spend_reset"
  fi
else
  if [ -n "$week_pct" ]; then
    burn_metric="seven_day"; burn_util="$week_pct"; burn_reset="$week_reset"
  fi
fi
if [ -n "$burn_metric" ]; then
  history_append "$eff_account_type" "$burn_metric" "$burn_util" "$burn_reset" 2>/dev/null || true
fi

# ── Custom renderer check ─────────────────────────────────────────────────
if [ -d "$THEME_DIR/$cfg_theme" ] && [ -f "$THEME_DIR/$cfg_theme/render.sh" ]; then
  source "$THEME_DIR/$cfg_theme/render.sh"
  exit 0
fi

# ── Reset countdown helper ─────────────────────────────────────────────────
format_countdown() {
  local resets_at="$1"
  if [ -z "$resets_at" ]; then return; fi
  local now_ts=$(date +%s)
  local diff=$(( resets_at - now_ts ))
  if [ "$diff" -le 0 ]; then return; fi
  local days=$(( diff / 86400 ))
  local hours=$(( (diff % 86400) / 3600 ))
  local mins=$(( (diff % 3600) / 60 ))
  if [ "$days" -gt 99 ]; then
    printf '↻>99d'
  elif [ "$days" -gt 0 ]; then
    printf '↻%dd%dh' "$days" "$hours"
  elif [ "$hours" -gt 0 ]; then
    printf '↻%dh%02dm' "$hours" "$mins"
  else
    printf '↻%dm' "$mins"
  fi
}

# ── Spend formatting helpers ──────────────────────────────────────────────
# Round cents → whole-dollar integer.
spend_dollars() { local c="${1:-0}"; echo $(( (c + 50) / 100 )); }
# Currency prefix: "$" for USD, otherwise "<CODE> ".
spend_cur() { if [ "${1:-USD}" = "USD" ] || [ -z "${1:-}" ]; then echo -n "\$"; else echo -n "${1} "; fi; }

# ── Build separator ────────────────────────────────────────────────────────
if ! $PL_MODE; then
  SEP_FG=$(hex_to_fg "$C_SEP")
  SEP=" ${SEP_FG}${cfg_separator}${RESET} "
fi

# ── Block content helpers (text only, no bg/fg wrapper) ───────────────────
block_text_model() { echo -n " ${S_MODEL} ${model} "; }

block_text_pct() {
  local block_name="$1" symbol="$2" label="$3" pct="$4" resets_at="${5:-}"
  local fg_hex=$(block_color "$block_name")
  local dim_fg=$(hex_to_fg "$C_DIM")

  if [ -z "$pct" ]; then
    echo -n " ${symbol} ${label} -- "
    return
  fi

  local pct_int=$(printf "%.0f" "$pct")
  local countdown=$(format_countdown "$resets_at")
  local reset_str=""
  if [ -n "$countdown" ]; then reset_str=" ${countdown}"; fi

  # Determine bar chars: config overrides > theme defaults
  local bar_f="${cfg_bar_filled:-$S_BAR_FILLED}"
  local bar_e="${cfg_bar_empty:-$S_BAR_EMPTY}"
  local bw="$cfg_bar_width"

  case "$cfg_spacing" in
    ultra-compact) echo -n " ${symbol} ${pct_int}%${reset_str} " ;;
    compact)
      local bar=$(make_bar "$pct_int" "$bw" "$bar_f" "$bar_e")
      echo -n " ${symbol} ${bar} ${pct_int}%${reset_str} "
      ;;
    *)
      local bar=$(make_bar "$pct_int" "$bw" "$bar_f" "$bar_e")
      echo -n " ${symbol} ${label} ${bar} ${pct_int}%${reset_str} "
      ;;
  esac
}

block_text_directory() {
  local short_dir=$(basename "$cwd")
  echo -n " ${S_DIR} ${short_dir} "
}

block_text_git() {
  if [ -n "$git_branch" ]; then
    echo -n " ${S_GIT} ${git_branch} "
  else
    echo -n " ${S_GIT} no-git "
  fi
}

block_text_time() { echo -n " ${S_TIME} ${now} "; }

block_text_cost() {
  if [ -n "$daily_cost" ]; then
    echo -n " \$${daily_cost} "
  else
    echo -n " \$-- "
  fi
}

block_text_spend() {
  if [ -z "$spend_limit_cents" ]; then echo -n " ${S_SPEND} \$-- "; return; fi
  local cur=$(spend_cur "$spend_currency")
  local used=$(spend_dollars "$spend_used_cents")
  local limit=$(spend_dollars "$spend_limit_cents")
  local pct_int=$(printf "%.0f" "$spend_pct")
  local countdown=$(format_countdown "$spend_reset")
  local reset_str=""; [ -n "$countdown" ] && reset_str=" ${countdown}"
  echo -n " ${S_SPEND} ${cur}${used}/${cur}${limit} ${pct_int}%${reset_str} "
}

block_text_credit() {
  block_text_pct "rate_7d" "$S_CREDIT" "CR" "$credit_pct" "$credit_reset"
}

# burn：以「實際速度 〈關係符〉 健康速度」呈現，數字一位小數。
# 例：實際 87.58%/d、健康 0.82%/d → "87.6 > 0.8"（> 代表太快）。健康速度未知時右側顯示 --。
_burn_fmt() {
  awk -v a="$1" -v s="$2" '
    BEGIN{
      if (s=="") { printf "%.1f > --", a; exit }
      op = (a>s)? ">" : (a<s)? "<" : "=";
      printf "%.1f %s %.1f", a, op, s
    }'
}

block_text_burn() {
  local _ba _bs _btf _bc _br
  IFS='|' read -r _ba _bs _btf _bc _br <<< "$(burn_rate_calc)"
  if [ -z "$_ba" ]; then echo -n " ${S_BURN} -- "; return; fi
  echo -n " ${S_BURN} $(_burn_fmt "$_ba" "$_bs") "
}

# 共用的內文組法：token 為空 → --；金額為空（Codex 無 session 價）→ 只印 token
_usage_text() {
  local symbol="$1" toks="$2" cost="$3"
  if [ -z "$toks" ]; then
    echo -n " ${symbol} -- "
  elif [ -z "$cost" ]; then
    echo -n " ${symbol} $(fmt_tokens "$toks") "
  else
    echo -n " ${symbol} $(fmt_tokens "$toks") \$$(fmt_price "$cost") "
  fi
}

block_text_session()   { _usage_text "$S_SESSION"   "$session_tokens" "$session_cost"; }
block_text_last_chat() { _usage_text "$S_LAST_CHAT" "$last_tokens"    "$last_cost"; }

# ── Classic block renderers ───────────────────────────────────────────────
render_block_model() {
  local fg=$(hex_to_fg "$(block_color model)")
  local bg=$(hex_to_bg "$(block_bg model)")
  echo -n "${bg}${fg}${BOLD} ${S_MODEL} ${model} ${RESET}"
}

render_pct_block() {
  local block_name="$1" symbol="$2" label="$3" pct="$4" resets_at="${5:-}"
  local fg_hex=$(block_color "$block_name")
  local bg_hex=$(block_bg "$block_name")
  local fg=$(hex_to_fg "$fg_hex")
  local bg=$(hex_to_bg "$bg_hex")
  local bar_bg=$(hex_to_bg "$C_BG_PRIMARY")
  local dim_fg=$(hex_to_fg "$C_DIM")

  if [ -z "$pct" ]; then
    echo -n "${bg}${fg}${BOLD} ${symbol} ${label} ${RESET} ${DIM}--${RESET}"
    return
  fi

  local pct_int=$(printf "%.0f" "$pct")
  local col=$(neon_colour "$pct_int" "$fg_hex" "$C_WARNING" "$C_ALERT")
  local countdown=$(format_countdown "$resets_at")
  local reset_str=""
  if [ -n "$countdown" ]; then
    reset_str=" ${dim_fg}${countdown}${RESET}"
  fi

  case "$cfg_spacing" in
    ultra-compact)
      echo -n "${bar_bg}${col} ${symbol} ${BOLD}${pct_int}%${reset_str} ${RESET}"
      ;;
    compact)
      local c_bar_f="${cfg_bar_filled:-$S_BAR_FILLED}" c_bar_e="${cfg_bar_empty:-$S_BAR_EMPTY}"
      local c_bw="$cfg_bar_width"
      local bar=$(make_bar "$pct_int" "$c_bw" "$c_bar_f" "$c_bar_e")
      echo -n "${bg}${fg}${BOLD} ${symbol} ${RESET}${bar_bg}${col} ${bar} ${BOLD}${pct_int}%${reset_str} ${RESET}"
      ;;
    *)
      local c_bar_f="${cfg_bar_filled:-$S_BAR_FILLED}" c_bar_e="${cfg_bar_empty:-$S_BAR_EMPTY}"
      local c_bw="$cfg_bar_width"
      local bar=$(make_bar "$pct_int" "$c_bw" "$c_bar_f" "$c_bar_e")
      echo -n "${bg}${fg}${BOLD} ${symbol} ${label} ${RESET}${bar_bg}${col} ${bar} ${BOLD}${pct_int}%${reset_str} ${RESET}"
      ;;
  esac
}

render_block_context()  { render_pct_block "context" "$S_CTX" "CTX" "$used_pct"; }
render_block_rate_5h()  { render_pct_block "rate_5h" "$S_5H"  "5H"  "$five_pct" "$five_reset"; }
render_block_rate_7d()  { render_pct_block "rate_7d" "$S_7D"  "7D"  "$week_pct" "$week_reset"; }
render_block_credit() { render_pct_block "rate_7d" "$S_CREDIT" "CR" "$credit_pct" "$credit_reset"; }

render_block_burn() {
  local fg_hex=$(block_color rate_7d)
  local bg=$(hex_to_bg "$(block_bg rate_7d)")
  local dim_fg=$(hex_to_fg "$C_DIM")
  local _ba _bs _btf _bc _br
  IFS='|' read -r _ba _bs _btf _bc _br <<< "$(burn_rate_calc)"
  if [ -z "$_ba" ]; then
    echo -n "${bg}${dim_fg} ${S_BURN} -- ${RESET}"; return
  fi
  # burn 是速率比值（actual vs sustainable），用二元 alert 判斷而非 neon_colour 的百分比三段色
  local col; if [ "$_btf" = "yes" ]; then col=$(hex_to_fg "$C_ALERT"); else col=$(hex_to_fg "$fg_hex"); fi
  echo -n "${bg}${col}${BOLD} ${S_BURN} $(_burn_fmt "$_ba" "$_bs") ${RESET}"
}

render_block_directory() {
  local fg=$(hex_to_fg "$(block_color directory)")
  local bg=$(hex_to_bg "$(block_bg directory)")
  local short_dir=$(basename "$cwd")
  echo -n "${bg}${fg}${BOLD} ${S_DIR} ${short_dir} ${RESET}"
}

render_block_git() {
  local fg=$(hex_to_fg "$(block_color git)")
  local bg=$(hex_to_bg "$(block_bg git)")
  if [ -n "$git_branch" ]; then
    echo -n "${bg}${fg}${BOLD} ${S_GIT} ${git_branch} ${RESET}"
  else
    local dim_fg=$(hex_to_fg "$C_DIM")
    local dim_bg=$(hex_to_bg "$C_BG_PRIMARY")
    echo -n "${dim_bg}${dim_fg} ${S_GIT} no-git ${RESET}"
  fi
}

render_block_time() {
  local fg=$(hex_to_fg "$(block_color time)")
  local bg=$(hex_to_bg "$(block_bg time)")
  echo -n "${bg}${fg} ${S_TIME} ${now} ${RESET}"
}

render_block_cost() {
  local fg=$(hex_to_fg "$(block_color cost)")
  local bg=$(hex_to_bg "$(block_bg cost)")
  if [ -n "$daily_cost" ]; then
    echo -n "${bg}${fg}${BOLD} \$${daily_cost} ${RESET}"
  else
    local dim_fg=$(hex_to_fg "$C_DIM")
    echo -n "${bg}${dim_fg} \$-- ${RESET}"
  fi
}

render_block_spend() {
  local fg_hex=$(block_color rate_5h)
  local bg_hex=$(block_bg rate_5h)
  local fg=$(hex_to_fg "$fg_hex")
  local bg=$(hex_to_bg "$bg_hex")
  local bar_bg=$(hex_to_bg "$C_BG_PRIMARY")
  local dim_fg=$(hex_to_fg "$C_DIM")

  if [ -z "$spend_limit_cents" ]; then
    echo -n "${bg}${dim_fg} ${S_SPEND} \$-- ${RESET}"
    return
  fi

  local cur=$(spend_cur "$spend_currency")
  local used=$(spend_dollars "$spend_used_cents")
  local limit=$(spend_dollars "$spend_limit_cents")
  local pct_int=$(printf "%.0f" "$spend_pct")
  local col=$(neon_colour "$pct_int" "$fg_hex" "$C_WARNING" "$C_ALERT")
  local countdown=$(format_countdown "$spend_reset")
  local reset_str=""; [ -n "$countdown" ] && reset_str=" ${dim_fg}${countdown}${RESET}"
  local amt="${cur}${used}/${cur}${limit}"

  case "$cfg_spacing" in
    ultra-compact)
      echo -n "${bar_bg}${col} ${S_SPEND} ${BOLD}${amt} ${pct_int}%${reset_str} ${RESET}"
      ;;
    *)
      local c_bar_f="${cfg_bar_filled:-$S_BAR_FILLED}" c_bar_e="${cfg_bar_empty:-$S_BAR_EMPTY}"
      local bar=$(make_bar "$pct_int" "$cfg_bar_width" "$c_bar_f" "$c_bar_e")
      echo -n "${bg}${fg}${BOLD} ${S_SPEND} ${RESET}${bar_bg}${col} ${amt} ${bar} ${BOLD}${pct_int}%${reset_str} ${RESET}"
      ;;
  esac
}

_render_usage() {
  local name="$1" symbol="$2" toks="$3" cost="$4"
  local fg=$(hex_to_fg "$(block_color "$name")")
  local bg=$(hex_to_bg "$(block_bg "$name")")
  if [ -z "$toks" ]; then
    local dim_fg=$(hex_to_fg "$C_DIM")
    echo -n "${bg}${dim_fg} ${symbol} -- ${RESET}"
  elif [ -z "$cost" ]; then
    echo -n "${bg}${fg}${BOLD} ${symbol} $(fmt_tokens "$toks") ${RESET}"
  else
    echo -n "${bg}${fg}${BOLD} ${symbol} $(fmt_tokens "$toks") \$$(fmt_price "$cost") ${RESET}"
  fi
}

render_block_session()   { _render_usage session   "$S_SESSION"   "$session_tokens" "$session_cost"; }
render_block_last_chat() { _render_usage last_chat "$S_LAST_CHAT" "$last_tokens"    "$last_cost"; }

# ── Get block's rainbow bg hex ────────────────────────────────────────────
get_block_bg_hex() {
  local block="$1"
  if $PL_MODE; then
    pl_block_bg "$block"
  else
    block_bg "$block"
  fi
}

# ── Assemble ───────────────────────────────────────────────────────────────

# 舊 config 的 "tokens" 映射為 "session"，升級後不會壞掉。
_canon_block() {
  case "$1" in
    tokens) echo "session" ;;
    *)      echo "$1" ;;
  esac
}

# quota 帳號：把 rate_5h/rate_7d 的位置換成單一 spend 區塊，並在其前面
# 插入尚未用光的 credit。只作用於第一列。
apply_quota_substitution() {
  local out=() b
  local _spend_added=false
  for b in "$@"; do
    if [ "$b" = "rate_5h" ] || [ "$b" = "rate_7d" ]; then
      if ! $_spend_added; then out+=("spend"); _spend_added=true; fi
      continue
    fi
    out+=("$b")
  done
  if ! $_spend_added; then
    out=()
    for b in "$@"; do
      out+=("$b")
      [ "$b" = "context" ] && out+=("spend") && _spend_added=true
    done
    $_spend_added || out+=("spend")
  fi
  # one-time credit 區塊：存在且尚未用光（< 100%）時插在第一個 spend 之前
  # （credit → spend）；credit 用光後隱藏，只留 enterprise spend limit。
  if [ -n "$credit_pct" ] && awk -v p="$credit_pct" 'BEGIN{exit !(p < 100)}'; then
    local tmp=() inserted=false
    for b in "${out[@]}"; do
      if [ "$b" = "spend" ] && ! $inserted; then
        tmp+=("credit"); inserted=true
      fi
      tmp+=("$b")
    done
    out=("${tmp[@]}")
  fi
  printf '%s\n' "${out[@]}"
}

# 把一串區塊名稱渲染成一整列（含 rainbow 頭尾 glyph 或 classic 分隔符）。
# rainbow 的色彩循環以區塊在「該列」中的索引計算，因此每列都從 accent_1
# 重新起算 —— 第二列的 session/last_chat 會自然拿到不同顏色。
assemble_line() {
  local block_list=("$@")
  local line=""
  [ ${#block_list[@]} -eq 0 ] && return

  if $PL_MODE; then
    local PL_CYCLE=("$C_ACCENT_1" "$C_ACCENT_2" "$C_ACCENT_3")
    local prev_bg_hex="" idx block cur_bg_hex cur_fg_hex cur_bg cur_fg head_fg arrow_fg text
    for idx in "${!block_list[@]}"; do
      block="${block_list[$idx]}"
      cur_bg_hex="${PL_CYCLE[$((idx % 3))]}"
      cur_fg_hex=$(pl_block_fg "$block")
      cur_bg=$(hex_to_bg "$cur_bg_hex")
      cur_fg=$(hex_to_fg "$cur_fg_hex")

      if [ "$idx" -eq 0 ]; then
        if [ -n "$PL_HEAD_OPEN" ]; then
          head_fg=$(hex_to_fg "$cur_bg_hex")
          line+="${RESET}${head_fg}${PL_HEAD_OPEN}${RESET}"
        fi
      else
        if [ -n "$PL_TAIL_SEP" ]; then
          arrow_fg=$(hex_to_fg "$prev_bg_hex")
          line+="${RESET}${arrow_fg}${cur_bg}${PL_TAIL_SEP}${RESET}"
        fi
      fi

      text=""
      case "$block" in
        model)     text=$(block_text_model) ;;
        context)   text=$(block_text_pct "context" "$S_CTX" "CTX" "$used_pct") ;;
        rate_5h)   text=$(block_text_pct "rate_5h" "$S_5H" "5H" "$five_pct" "$five_reset") ;;
        rate_7d)   text=$(block_text_pct "rate_7d" "$S_7D" "7D" "$week_pct" "$week_reset") ;;
        directory) text=$(block_text_directory) ;;
        git)       text=$(block_text_git) ;;
        time)      text=$(block_text_time) ;;
        cost)      text=$(block_text_cost) ;;
        spend)     text=$(block_text_spend) ;;
        credit)    text=$(block_text_credit) ;;
        burn)      text=$(block_text_burn) ;;
        session)   text=$(block_text_session) ;;
        last_chat) text=$(block_text_last_chat) ;;
      esac
      line+="${cur_bg}${cur_fg}${BOLD}${text}${RESET}"
      prev_bg_hex="$cur_bg_hex"
    done

    if [ -n "$prev_bg_hex" ] && [ -n "$PL_TAIL_SEP" ]; then
      arrow_fg=$(hex_to_fg "$prev_bg_hex")
      line+="${RESET}${arrow_fg}${PL_TAIL_SEP}${RESET}"
    fi
  else
    local first=true block
    for block in "${block_list[@]}"; do
      if $first; then first=false; else line+="$SEP"; fi
      case "$block" in
        model)     line+=$(render_block_model) ;;
        context)   line+=$(render_block_context) ;;
        rate_5h)   line+=$(render_block_rate_5h) ;;
        rate_7d)   line+=$(render_block_rate_7d) ;;
        directory) line+=$(render_block_directory) ;;
        git)       line+=$(render_block_git) ;;
        time)      line+=$(render_block_time) ;;
        cost)      line+=$(render_block_cost) ;;
        spend)     line+=$(render_block_spend) ;;
        credit)    line+=$(render_block_credit) ;;
        burn)      line+=$(render_block_burn) ;;
        session)   line+=$(render_block_session) ;;
        last_chat) line+=$(render_block_last_chat) ;;
      esac
    done
  fi
  printf '%s' "$line"
}

line1_blocks=()
for b in $cfg_blocks; do line1_blocks+=("$(_canon_block "$b")"); done
if [ "$eff_account_type" = "quota" ] && [ ${#line1_blocks[@]} -gt 0 ]; then
  _subbed=()
  while IFS= read -r b; do [ -n "$b" ] && _subbed+=("$b"); done < <(apply_quota_substitution "${line1_blocks[@]}")
  line1_blocks=("${_subbed[@]}")
fi

line2_blocks=()
for b in $cfg_blocks_line2; do line2_blocks+=("$(_canon_block "$b")"); done

output=""
[ ${#line1_blocks[@]} -gt 0 ] && output=$(assemble_line "${line1_blocks[@]}")

line2=""
[ ${#line2_blocks[@]} -gt 0 ] && line2=$(assemble_line "${line2_blocks[@]}")

# Ensure output ends with newline so subsequent prompts start on a new line
echo -e "$output"
if [ -n "$line2" ]; then
  echo -e "$line2"
fi
echo ""
