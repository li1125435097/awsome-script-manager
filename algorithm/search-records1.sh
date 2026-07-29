#!/usr/bin/env bash
# N-gram search: 4/3/2-char substrings, weighted score, highest similarity first.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEFAULT_RECORDS="$ROOT/data/search-records.tsv"
SEARCH_TMP=

cleanup_search() {
  rm -f "${SEARCH_TMP:-}"
}

usage() {
  echo "Usage: $(basename "$0") <query> [records.tsv]" >&2
  echo "  Splits query into 4/3/2-character substrings (weight = length)," >&2
  echo "  scores name-column hits, prints records by descending similarity." >&2
}

die() {
  echo "search-records: $*" >&2
  exit 1
}

# weight<TAB>gram (gram order: len 4, then 3, then 2; dedupe keeps max weight)
collect_weighted_ngrams() {
  local query=$1
  local len=${#query}
  local gram_len start gram

  if ((len < 2)); then
    printf '2\t%s\n' "$query"
    return 0
  fi

  for gram_len in 4 3 2; do
    ((len >= gram_len)) || continue
    for ((start = 0; start <= len - gram_len; start++)); do
      gram=${query:start:gram_len}
      printf '%d\t%s\n' "$gram_len" "$gram"
    done
  done
}

write_gram_table() {
  local query=$1 dest=$2
  collect_weighted_ngrams "$query" | awk -F'\t' '
    $2 != "" {
      g = $2
      w = $1 + 0
      if (!(g in best) || w > best[g]) best[g] = w
    }
    END {
      for (g in best) print best[g] "\t" g
    }' >"$dest"
}

rank_records() {
  local query=$1 grams_file=$2 records=$3
  awk -F'\t' -v q="$query" '
    NR == FNR {
      w[++n] = $1 + 0
      g[n] = $2
      next
    }
    {
      name = tolower($2)
      score = 0
      for (i = 1; i <= n; i++) {
        if (index(name, g[i])) score += w[i]
      }
      if (q != "" && index(name, q)) {
        score += length(q) * 4
      }
      if (score > 0) print score "\t" $1 "\t" $2
    }' "$grams_file" "$records"
}

main() {
  [[ $# -ge 1 ]] || {
    usage
    exit 1
  }

  local raw_query=$1
  local query=$1
  local records=${2:-$DEFAULT_RECORDS}
  query=${query,,}

  [[ -n $query ]] || die "empty query"
  [[ -f $records ]] || die "records not found ($records); run: ./gen-search-records.sh"

  SEARCH_TMP=$(mktemp)
  trap cleanup_search EXIT

  write_gram_table "$query" "$SEARCH_TMP"

  if [[ ! -s $SEARCH_TMP ]]; then
    echo "search-records: no matches for: $raw_query" >&2
    exit 1
  fi

  local ranked
  ranked=$(rank_records "$query" "$SEARCH_TMP" "$records")
  if [[ -z $ranked ]]; then
    echo "search-records: no matches for: $raw_query" >&2
    exit 1
  fi

  printf '%s\n' "$ranked" | sort -t $'\t' -k1,1nr -k2,2 | cut -f2-
}

main "$@"
