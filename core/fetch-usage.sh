#!/usr/bin/env bash
# Fetch & normalize Claude usage from the (reverse-engineered) /api/oauth/usage
# endpoint. Outputs a single-line JSON contract to stdout. Never errors out:
# any failure yields {"account_type":"unknown"} with exit 0.
set -uo pipefail

JQ=$(command -v jq 2>/dev/null || echo "/opt/homebrew/bin/jq")
fail() { printf '{"account_type":"unknown"}\n'; exit 0; }
"$JQ" --version >/dev/null 2>&1 || fail

raw=""
if [ -n "${USAGE_FIXTURE:-}" ]; then
  raw=$(cat "$USAGE_FIXTURE" 2>/dev/null)
else
  token=""
  if command -v security >/dev/null 2>&1; then
    token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
      | "$JQ" -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
  fi
  if [ -z "$token" ] && [ -f "$HOME/.claude/.credentials.json" ]; then
    token=$("$JQ" -r '.claudeAiOauth.accessToken // empty' "$HOME/.claude/.credentials.json" 2>/dev/null)
  fi
  [ -z "$token" ] && fail
  command -v curl >/dev/null 2>&1 || fail
  raw=$(curl -sS --max-time 5 \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "anthropic-version: 2023-06-01" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
fi

# Empty/whitespace-only response (e.g. curl offline/timeout) is a failure:
# jq empty treats no-input as valid (exit 0), so guard it explicitly. This
# preserves the {"account_type":"unknown"} contract and avoids writing a
# 0-byte cache whose fresh mtime would suppress retries for 60s.
[ -z "${raw//[[:space:]]/}" ] && fail
echo "$raw" | "$JQ" empty >/dev/null 2>&1 || fail

reset_epoch=$(date -v1d -v+1m -v0H -v0M -v0S +%s 2>/dev/null)
if [ -z "$reset_epoch" ]; then
  reset_epoch=$(date -d "$(date +%Y-%m-01) +1 month" +%s 2>/dev/null || echo 0)
fi

echo "$raw" | "$JQ" -c --argjson reset "$reset_epoch" '
  if (.extra_usage.monthly_limit | type) == "number" then
    {
      account_type: "quota",
      spend: {
        used_cents:  (.extra_usage.used_credits // 0 | round),
        limit_cents: (.extra_usage.monthly_limit | round),
        utilization: (.extra_usage.utilization // 0),
        currency:    (.extra_usage.currency // "USD"),
        resets_at:   $reset
      }
    }
  elif (.five_hour != null) or (.seven_day != null) then
    {account_type: "subscription"}
  else
    {account_type: "unknown"}
  end
' 2>/dev/null || fail
