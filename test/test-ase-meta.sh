#!/usr/bin/env bash
# Local smoke test for ase-meta script header parsing (not for CI).
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$ROOT/.." && pwd)
# shellcheck source=../lib/ase-common.sh
source "$REPO/lib/ase-common.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "test-ase-meta: FAIL: $*" >&2
  exit 1
}

ok() {
  echo "test-ase-meta: OK: $*"
}

META_SCRIPT="$TMP/with-meta.sh"
cat >"$META_SCRIPT" <<'EOF'
#!/usr/bin/env bash
# --- ase-meta ---
# author: test-author
# desc: Example script for meta parsing
# constant: depth=1 (max-depth for du)
# constant: limit=20 (lines shown via head)
# source: https://example.com/script-hub/with-meta
# license: MIT
# --- end ---
set -euo pipefail
echo ok
EOF

LEGACY_SCRIPT="$TMP/legacy.sh"
cat >"$LEGACY_SCRIPT" <<'EOF'
#!/usr/bin/env bash
# Legacy one-line description
set -euo pipefail
echo ok
EOF

ase_script_has_meta_block "$META_SCRIPT" || fail "expected meta block in with-meta.sh"
ase_script_has_meta_block "$LEGACY_SCRIPT" && fail "legacy script should not have meta block"

[[ $(ase_script_meta_get "$META_SCRIPT" author) == "test-author" ]] || \
  fail "author mismatch: $(ase_script_meta_get "$META_SCRIPT" author)"
[[ $(ase_script_meta_get "$META_SCRIPT" desc) == "Example script for meta parsing" ]] || \
  fail "desc mismatch"
[[ $(ase_script_meta_get "$META_SCRIPT" source) == "https://example.com/script-hub/with-meta" ]] || \
  fail "source mismatch"
[[ $(ase_script_meta_get "$META_SCRIPT" license) == "MIT" ]] || \
  fail "unknown key license should be readable"

constants=$(ase_script_meta_constants "$META_SCRIPT")
[[ $(printf '%s\n' "$constants" | wc -l) -eq 2 ]] || fail "expected 2 constants, got: $constants"
printf '%s\n' "$constants" | grep -qx 'depth=1 (max-depth for du)' || fail "constant depth missing"
printf '%s\n' "$constants" | grep -qx 'limit=20 (lines shown via head)' || fail "constant limit missing"

[[ $(ase_script_desc "$META_SCRIPT") == "Example script for meta parsing" ]] || \
  fail "ase_script_desc meta: $(ase_script_desc "$META_SCRIPT")"
[[ $(ase_script_desc "$LEGACY_SCRIPT") == "Legacy one-line description" ]] || \
  fail "ase_script_desc legacy: $(ase_script_desc "$LEGACY_SCRIPT")"
[[ $(ase_script_description_line "$LEGACY_SCRIPT") == "Legacy one-line description" ]] || \
  fail "ase_script_description_line legacy"

DU_HERE="$REPO/script-hub/du-here"
[[ -f $DU_HERE ]] || fail "missing script-hub/du-here"
ase_script_has_meta_block "$DU_HERE" || fail "du-here should have meta block"
[[ $(ase_script_desc "$DU_HERE") == "Summarize disk usage of files in the current directory (human-readable)" ]] || \
  fail "du-here desc mismatch"

ok "meta parsing and legacy fallback"
