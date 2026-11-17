#!/usr/bin/env bash
# check-model-aliases.sh — every `acp.command="fidfab-<agent>-acp ... --model <alias>"` in the
# workflows and components must name an alias the wrapper's `case "$model" in ... esac` block
# resolves. An unknown name is passed to the agent as a literal model ID and the stage fails
# only at run time. Offline; no fabro needed.
#
# Usage: tests/check-model-aliases.sh [repo-root]   (default: this repository)
set -euo pipefail
root="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")/..}" && pwd)"
bin="$root/docker/rootfs/usr/local/bin"
cd "$root"

# aliases <wrapper>: the patterns of the `case "$model"` block, one per line ("" -> empty line).
aliases() {
  sed -n '/^case "\$model" in$/,/^esac$/p' "$1" \
    | sed -nE 's/^[[:space:]]*([^)[:space:]]+)\).*/\1/p' | tr '|' '\n' | sed 's/^""$//'
}

status=0
fail() { echo "$1: $2"; status=1; }
check() { # <file:line> <command>
  local where="$1" words wrapper i model="" have=0
  read -ra words <<<"$2"
  wrapper="${words[0]}"
  [[ "$wrapper" == fidfab-*-acp ]] || return 0
  [[ -f "$bin/$wrapper" ]] || { fail "$where" "unknown wrapper $wrapper"; return; }
  for ((i = 1; i < ${#words[@]}; i++)); do
    case "${words[i]}" in
      --model)
        if (( i + 1 >= ${#words[@]} )) || [[ "${words[i+1]}" == -* ]]; then
          fail "$where" "$wrapper --model has no value"; return
        fi
        model="${words[i+1]}"; have=1; i=$((i + 1)) ;;
      --model=*) fail "$where" "$wrapper takes '--model <alias>', not '${words[i]}'"; return ;;
    esac
  done
  (( have )) || return 0
  aliases "$bin/$wrapper" | grep -qxF -- "$model" \
    || fail "$where" "$wrapper has no model alias '$model'"
}

# Paths are relative to the repository root, so `file:line:` splits cleanly.
while IFS= read -r hit; do
  file="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"; ref="${rest#*:}"
  ref="${ref#acp.command=\"}"; check "$file:$line" "${ref%\"}"
done < <(grep -rnoE --include='*.fabro' 'acp\.command="[^"]*"' components .fabro/workflows 2>/dev/null || true)
exit $status
