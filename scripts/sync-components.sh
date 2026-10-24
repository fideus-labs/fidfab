#!/usr/bin/env bash
# sync-components.sh — vendor the canonical fidfab components into workflow directories.
#
# Fabro resolves `@prompt` files referenced by imported components relative to
# the importing workflow's directory and refuses paths that escape it. The
# canonical components therefore live once in `components/` and are copied
# verbatim into every workflow directory that imports them.
#
# Usage:
#   scripts/sync-components.sh                 # sync all .fabro/workflows/*/ in this repo
#   scripts/sync-components.sh --check         # exit 1 if any vendored copy is out of date (CI)
#   scripts/sync-components.sh <workflow-dir>  # vendor into another repo's workflow directory
#
# When fidfab is included as a git subtree at <prefix>/, run
#   <prefix>/scripts/sync-components.sh .fabro/workflows/<your-workflow>
# from the consuming repository and import with `import="components/<name>.fabro"`.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$here/components"
check=0
targets=()
for arg in "$@"; do
  case "$arg" in
    --check) check=1 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) targets+=("$arg") ;;
  esac
done
if [[ ${#targets[@]} -eq 0 ]]; then
  for d in "$here"/.fabro/workflows/*/; do targets+=("$d"); done
fi

status=0
for t in "${targets[@]}"; do
  dest="${t%/}/components"
  if [[ $check -eq 1 ]]; then
    if ! diff -r -q --exclude=.synced "$src" "$dest" >/dev/null 2>&1; then
      echo "out of date: $dest (run scripts/sync-components.sh)" >&2
      status=1
    fi
    continue
  fi
  rm -rf "$dest"
  mkdir -p "$dest"
  cp -R "$src"/. "$dest"/
  printf 'Vendored copy of %s — do not edit here; edit components/ and run scripts/sync-components.sh\n' "fidfab/components" > "$dest/.synced"
  echo "synced -> $dest"
done
exit $status
