#!/usr/bin/env bash
# Regenerate data/script-hub.list from files in script-hub/.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HUB_DIR="$ROOT/script-hub"
OUT="$ROOT/data/script-hub.list"

usage() {
  echo "Usage: $(basename "$0") [-h]" >&2
  echo "  Scan script-hub/ and write data/script-hub.list (line_no<TAB>name)." >&2
}

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  usage
  exit 0
fi

[[ -d $HUB_DIR ]] || {
  echo "gen-script-hub-list: directory not found: $HUB_DIR" >&2
  exit 1
}

mapfile -t names < <(
  for f in "$HUB_DIR"/*; do
    [[ -f $f ]] || continue
    basename "$f"
  done | sort
)

if ((${#names[@]} == 0)); then
  echo "gen-script-hub-list: no files in $HUB_DIR" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
i=1
for name in "${names[@]}"; do
  printf '%d\t%s\n' "$i" "$name"
  ((++i))
done >"$OUT"

echo "gen-script-hub-list: wrote ${#names[@]} entries to $OUT" >&2
