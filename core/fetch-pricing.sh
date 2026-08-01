#!/usr/bin/env bash
# Fetch Claude model pricing and emit a compact lookup table on stdout.
#
# Why a third-party source: Anthropic's own Models API (/v1/models) returns
# capabilities but *no* pricing, and docs/en/pricing.md 404s — there is no
# machine-readable first-party feed. LiteLLM's table is the de-facto standard
# and is what `ccusage` (this project's primary daily-cost path) already reads,
# so using it here keeps the two cost paths on the same numbers.
#
# Output contract: a single-line JSON object mapping model id → per-1M-token
# prices {i, o, cw5, cw1h, cr}. Exits non-zero and prints nothing on any
# failure, so the caller's `>tmp && mv` keeps the previous cache intact and
# statusline.sh falls back to its built-in table.
#
# NOTE: the upstream payload is ~1.7MB. Never load it into a shell variable —
# bash's ${var//pattern/} on a string that size degrades pathologically (it
# hung for minutes in testing). Keep it on disk and let jq read the file.
set -uo pipefail

SRC="${PRICING_SRC_URL:-https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json}"
JQ=$(command -v jq 2>/dev/null || echo "/opt/homebrew/bin/jq")

"$JQ" --version >/dev/null 2>&1 || exit 1

if [ -n "${PRICING_FIXTURE:-}" ]; then
  src_file="$PRICING_FIXTURE"
  [ -s "$src_file" ] || exit 1
else
  command -v curl >/dev/null 2>&1 || exit 1
  src_file=$(mktemp) || exit 1
  trap 'rm -f "$src_file"' EXIT
  curl -sSL --max-time 20 -o "$src_file" "$SRC" 2>/dev/null || exit 1
  [ -s "$src_file" ] || exit 1
fi

# Sanity bounds reject a corrupted or mis-scaled upstream row rather than
# letting it through: silently-wrong prices are worse than a known-stale
# built-in table. $1000/1M is far above any real rate, and input must be > 0.
out=$("$JQ" -c '
  def ok($x): ($x | type) == "number" and $x > 0 and $x <= 1000;
  [ to_entries[]
    | select((.key | type) == "string")
    | select((.value | type) == "object")
    | select(.value.litellm_provider == "anthropic")
    | select(.key | startswith("claude-"))
    | { key: .key,
        value: {
          i:    ((.value.input_cost_per_token  // 0) * 1000000),
          o:    ((.value.output_cost_per_token // 0) * 1000000),
          cw5:  ((.value.cache_creation_input_token_cost // 0) * 1000000),
          cw1h: ((.value.cache_creation_input_token_cost_above_1hr // 0) * 1000000),
          cr:   ((.value.cache_read_input_token_cost // 0) * 1000000) } }
    # cw5/cw1h/cr may legitimately be 0 for models without prompt caching, but
    # input and output must both be present and plausible.
    | select(ok(.value.i) and ok(.value.o))
    # A cache-write price above ~2x input means the row is mis-scaled; drop it
    # rather than over-billing.
    | select(.value.cw1h <= (.value.i * 2.5) and .value.cw5 <= (.value.i * 2.5))
  ] | from_entries' "$src_file" 2>/dev/null)

# A parse that yields nothing usable is a failure, not an empty table.
[ -n "$out" ] || exit 1
n=$("$JQ" -rn --argjson o "$out" '$o | length' 2>/dev/null || echo 0)
[ "${n:-0}" -ge 5 ] || exit 1

printf '%s\n' "$out"
