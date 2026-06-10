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

out=$(USAGE_FIXTURE="$FIX/usage-subscription.json" bash "$FETCH")
check "subscription: account_type" "subscription" "$(echo "$out" | jq -r '.account_type')"

out=$(USAGE_FIXTURE="$FIX/usage-empty.json" bash "$FETCH")
check "empty: account_type" "unknown" "$(echo "$out" | jq -r '.account_type')"
out=$(echo 'not json' > /tmp/cyberpunk-bad.json; USAGE_FIXTURE="/tmp/cyberpunk-bad.json" bash "$FETCH"; rm -f /tmp/cyberpunk-bad.json)
check "bad json: account_type" "unknown" "$(echo "$out" | jq -r '.account_type')"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
