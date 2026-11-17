#!/usr/bin/env bash
# test-model-aliases.sh — host-side check of the offline model alias lint
# (tests/check-model-aliases.sh) against scratch repositories, using the real wrappers.
set -euo pipefail
cd "$(dirname "$0")/.."
repo="$PWD"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

fail=0; n=0
# check NAME EXPECT(pass|fail) ACP_COMMAND
check() {
  local r="$tmp/r$((n += 1))" rc=0
  mkdir -p "$r/components" "$r/.fabro/workflows/w" "$r/docker/rootfs/usr/local/bin"
  cp "$repo"/docker/rootfs/usr/local/bin/fidfab-*-acp "$r/docker/rootfs/usr/local/bin/"
  printf 'digraph G {\n  a [backend="acp", acp.command="%s"]\n}\n' "$3" > "$r/components/c.fabro"
  "$repo/tests/check-model-aliases.sh" "$r" >"$tmp/log" 2>&1 || rc=$?
  if { [[ $2 == pass && $rc -eq 0 ]] || [[ $2 == fail && $rc -ne 0 ]]; }; then
    echo "ok   $1"
  else
    echo "FAIL $1: want $2, exit $rc"; cat "$tmp/log"; fail=1
  fi
}

check "codex terra"                     pass 'fidfab-codex-acp --model terra'
check "codex terra after --effort"      pass 'fidfab-codex-acp --effort medium --model terra'
check "codex without --model"           pass 'fidfab-codex-acp --effort low'
check "claude opus"                     pass 'fidfab-claude-acp --model opus --effort max'
check "codex luna (removed alias)"      fail 'fidfab-codex-acp --model luna'
check "luna after --effort"             fail 'fidfab-codex-acp --effort medium --model luna'
check "--model missing its value"       fail 'fidfab-codex-acp --model --effort medium'
check "--model at end without value"    fail 'fidfab-codex-acp --model'
check "option name is not an alias"     fail 'fidfab-codex-acp --model --help'
check "regex metachars are literal"     fail 'fidfab-codex-acp --model t.rra'
check "claude o.us"                     fail 'fidfab-claude-acp --model o.us'
check "--model= form"                   fail 'fidfab-codex-acp --model=terra'
check "unknown wrapper"                 fail 'fidfab-nope-acp --model terra'
check "empty acp.command"               fail ''
check "whitespace-only acp.command"     fail '   '
check "path-qualified wrapper"          fail '/usr/local/bin/fidfab-codex-acp --model terra'
check "path-qualified luna"             fail '/usr/local/bin/fidfab-codex-acp --model luna'
check "slash inside wrapper name"       fail 'fidfab-../../foo-acp --model terra'
check "non-fidfab command is ignored"   pass '/usr/bin/other-agent --model whatever'
if "$repo/tests/check-model-aliases.sh"; then echo "ok   repository workflows"
else echo "FAIL repository workflows use unknown aliases"; fail=1; fi
exit $fail
