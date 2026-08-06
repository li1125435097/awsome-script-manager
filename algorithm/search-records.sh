#!/usr/bin/env bash
# Keyword search: full-word + L/2 + L/4 substrings (len>=2); 2-grams when L>2 unless already covered.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEFAULT_RECORDS="$ROOT/data/search-records.tsv"
SEARCH_TMP=

cleanup_search() {
  rm -f "${SEARCH_TMP:-}"
}

DEFAULT_LIMIT=100

usage() {
  echo "Usage: $(basename "$0") [-l NUM] <query> [records.tsv]" >&2
  echo "  Default: top ${DEFAULT_LIMIT} rows by similarity. -l NUM sets max output (0 = no limit)." >&2
  echo "  Query is split on whitespace into keywords. Per keyword (len>=2):" >&2
  echo "  full-word match; all len/2 and len/4 substrings (if length>=2);" >&2
  echo "  plus 2-char substrings when len>2 unless len/2 or len/4 is already 2. Ranked by score desc." >&2
}

die() {
  echo "search-records: $*" >&2
  exit 1
}

emit_substrings() {
  local text=$1 slen=$2 weight=$3
  local len=${#text} start gram

  (( slen >= 2 && len >= slen )) || return 0
  for ((start = 0; start <= len - slen; start++)); do
    gram=${text:start:slen}
    printf '%d\t%s\n' "$weight" "$gram"
  done
}

collect_keyword_patterns() {
  local kw=$1
  local len=${#kw}
  local half quarter

  (( len >= 2 )) || return 0

  # 全词匹配（权重最高）
  printf '%d\t%s\n' $((len * 4)) "$kw"

  half=$((len / 2))
  quarter=$((len / 4))

  if (( half >= 2 )); then
    emit_substrings "$kw" "$half" "$half"
  fi
  if (( quarter >= 2 )); then
    emit_substrings "$kw" "$quarter" "$quarter"
  fi
  # len/2 或 len/4 已是 2 字时，会扫完全部 2 字子串，不再重复
  if (( len > 2 && half != 2 && quarter != 2 )); then
    emit_substrings "$kw" 2 2
  fi
}

collect_query_patterns() {
  local query=$1
  local kw

  for kw in $query; do
    [[ -n $kw ]] || continue
    collect_keyword_patterns "$kw"
  done
}

write_gram_table() {
  local query=$1 dest=$2
  collect_query_patterns "$query" | awk -F'\t' '
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
  local grams_file=$1 records=$2
  awk -F'\t' '
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
      if (score > 0) print score "\t" $1 "\t" $2
    }' "$grams_file" "$records"
}

main() {
  local limit=$DEFAULT_LIMIT
  local opt
  while getopts ":l:h" opt; do
    case $opt in
      l)
        if ! [[ $OPTARG =~ ^[0-9]+$ ]]; then
          die "-l requires a non-negative integer, got: $OPTARG"
        fi
        limit=$OPTARG
        ;;
      h)
        usage
        exit 0
        ;;
      :)
        die "option -$OPTARG requires an argument"
        ;;
      ?)
        die "unknown option: -$OPTARG"
        ;;
    esac
  done
  shift $((OPTIND - 1))

  [[ $# -ge 1 ]] || {
    usage
    exit 1
  }

  local raw_query=$1
  local query=$1
  local records=${2:-$DEFAULT_RECORDS}
  query=$(printf '%s' "$query" | tr '[:upper:]' '[:lower:]')

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
  ranked=$(rank_records "$SEARCH_TMP" "$records")
  if [[ -z $ranked ]]; then
    echo "search-records: no matches for: $raw_query" >&2
    exit 1
  fi

  local sorted
  sorted=$(printf '%s\n' "$ranked" | sort -t $'\t' -k1,1nr -k2,2 | cut -f2-)

  if (( limit == 0 )); then
    printf '%s\n' "$sorted"
    return 0
  fi

  local n=0 line
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    printf '%s\n' "$line"
    ((++n))
    if (( n >= limit )); then
      break
    fi
  done <<< "$sorted"
}

main "$@"
