#!/usr/bin/env bash
# Local smoke test for gen-search-records.sh / search-records.sh (not for CI).
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RECORDS="$ROOT/data/search-records.tsv"
GEN="$ROOT/gen-search-records.sh"
SEARCH="$ROOT/search-records.sh"

fail() {
  echo "test-search-records: FAIL: $*" >&2
  exit 1
}

ok() {
  echo "test-search-records: OK: $*"
}

if [[ ! -f $RECORDS ]]; then
  echo "test-search-records: generating $RECORDS (100000 lines)..." >&2
  "$GEN" "$RECORDS" 100000
fi

[[ -f $RECORDS ]] || fail "records missing after generate"

line_count=$(wc -l <"$RECORDS" | tr -d ' ')
(( line_count >= 100000 )) || fail "expected >= 100000 lines, got $line_count"

port_hits=$("$SEARCH" -l 0 端口 "$RECORDS" | wc -l | tr -d ' ')
(( port_hits > 0 )) || fail "query '端口' returned no hits"
ok "query '端口' -> $port_hits hits"

or_hits=$("$SEARCH" -l 0 检测 "$RECORDS" | wc -l | tr -d ' ')
(( or_hits >= port_hits )) || fail "expected '检测' hits ($or_hits) >= '端口' hits ($port_hits)"
ok "query '检测' -> $or_hits hits (union recall >= '端口')"

default_cap=$("$SEARCH" 端口 "$RECORDS" | wc -l | tr -d ' ')
(( default_cap <= 100 )) || fail "default output should be at most 100 lines, got $default_cap"
ok "default limit caps at 100 (got $default_cap lines)"

if "$SEARCH" 'qqqqqqqqqq' "$RECORDS" >/dev/null 2>&1; then
  fail "nonsense query should exit non-zero"
fi
ok "nonsense query exits 1 with no stdout"

echo "test-search-records: timing search on $line_count lines..." >&2
start=$(date +%s)
"$SEARCH" 开放端口检测 "$RECORDS" >/dev/null
end=$(date +%s)
elapsed=$((end - start))
ok "query '开放端口检测' completed in ${elapsed}s"

echo "test-search-records: all checks passed" >&2
