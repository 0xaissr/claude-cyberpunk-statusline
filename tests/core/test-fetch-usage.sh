#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
FETCH="$PROJECT_DIR/core/fetch-usage.sh"
FIX="$SCRIPT_DIR/fixtures"

PASS=0; FAIL=0
check() { # desc, expected, actual
  if [ "$2" = "$3" ]; then echo "✓ $1"; ((PASS++)); else echo "✗ $1 — expected [$2] got [$3]"; ((FAIL++)); fi
}

out=$(USAGE_FIXTURE="$FIX/usage-quota.json" bash "$FETCH")
check "quota: account_type"  "quota" "$(echo "$out" | jq -r '.account_type')"
check "quota: used_cents"    "12156" "$(echo "$out" | jq -r '.spend.used_cents')"
check "quota: limit_cents"   "50000" "$(echo "$out" | jq -r '.spend.limit_cents')"
check "quota: utilization"   "24"    "$(echo "$out" | jq -r '.spend.utilization | round')"
check "quota: currency"      "USD"   "$(echo "$out" | jq -r '.spend.currency')"
check "quota: resets_at>now" "yes"   "$([ "$(echo "$out" | jq -r '.spend.resets_at')" -gt "$(date +%s)" ] && echo yes || echo no)"

# quota + one-time credit (cinder_cove)
out=$(USAGE_FIXTURE="$FIX/usage-quota-credit.json" bash "$FETCH")
check "credit: account_type"   "quota" "$(echo "$out" | jq -r '.account_type')"
check "credit: utilization"    "8"     "$(echo "$out" | jq -r '.credit.utilization | round')"
check "credit: resets_at>now"  "yes"   "$([ "$(echo "$out" | jq -r '.credit.resets_at')" -gt "$(date +%s)" ] && echo yes || echo no)"
check "credit: spend retained" "12156" "$(echo "$out" | jq -r '.spend.used_cents')"

# quota WITHOUT credit → no .credit key
out=$(USAGE_FIXTURE="$FIX/usage-quota.json" bash "$FETCH")
check "no-credit: key absent" "null" "$(echo "$out" | jq -r '.credit // "null"')"

out=$(USAGE_FIXTURE="$FIX/usage-subscription.json" bash "$FETCH")
check "subscription: account_type" "subscription" "$(echo "$out" | jq -r '.account_type')"

out=$(USAGE_FIXTURE="$FIX/usage-empty.json" bash "$FETCH")
check "empty: account_type" "unknown" "$(echo "$out" | jq -r '.account_type')"
out=$(echo 'not json' > /tmp/cyberpunk-bad.json; USAGE_FIXTURE="/tmp/cyberpunk-bad.json" bash "$FETCH"; rm -f /tmp/cyberpunk-bad.json)
check "bad json: account_type" "unknown" "$(echo "$out" | jq -r '.account_type')"

# Empty / whitespace-only response (simulates curl offline/timeout) must still
# emit the unknown contract — not an empty string.
out=$(printf '' > /tmp/cyberpunk-empty.txt; USAGE_FIXTURE="/tmp/cyberpunk-empty.txt" bash "$FETCH"; rm -f /tmp/cyberpunk-empty.txt)
check "empty response: account_type" "unknown" "$(echo "$out" | jq -r '.account_type // "MISSING"')"
out=$(printf '   \n' > /tmp/cyberpunk-ws.txt; USAGE_FIXTURE="/tmp/cyberpunk-ws.txt" bash "$FETCH"; rm -f /tmp/cyberpunk-ws.txt)
check "whitespace response: account_type" "unknown" "$(echo "$out" | jq -r '.account_type // "MISSING"')"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
