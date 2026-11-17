#!/usr/bin/env bash
# test-codex-model.sh — offline check of the Codex model selection: fidfab-codex-acp alias
# resolution (with a stub codex-acp that prints the config it was given) and the default
# model in the Codex config. Needs no credentials, network or image.
#
# Usage: tests/test-codex-model.sh [wrapper] [config.toml]
#   Defaults to the repository's docker/rootfs/usr/local/bin/fidfab-codex-acp and
#   docker/config/codex-config.toml; tests/test-codex-acp.sh passes the installed ones.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wrapper="$(realpath "${1:-$root/docker/rootfs/usr/local/bin/fidfab-codex-acp}")"
config="${2:-$root/docker/config/codex-config.toml}"

stub="$(mktemp -d)"; trap 'rm -rf "$stub"' EXIT
printf '#!/bin/sh\nprintf "%%s\\n" "$CODEX_CONFIG"\n' > "$stub/codex-acp"; chmod +x "$stub/codex-acp"
fail=0
# expect NAME EXPECTED_CONFIG_GLOB ENV... -- ARGS...
expect() {
  local name="$1" want="$2" got envs=(); shift 2
  while [[ $# -gt 0 && "$1" != -- ]]; do envs+=("$1"); shift; done; shift
  got="$(cd "$stub" && env -u FIDFAB_MODEL_TERRA PATH="$stub:$PATH" CODEX_HOME="$stub/home" "${envs[@]}" "$wrapper" "$@")" || got="<exit $?>"
  # shellcheck disable=SC2053  # $want is a glob on purpose
  if [[ "$got" == $want ]]; then echo "ok   $name"; else echo "FAIL $name: got $got"; fail=1; fi
}
m() { printf '{"model":"%s",*' "$1"; }

expect "terra alias"                 "$(m gpt-5.6-terra)"  -- --model terra
expect "no --model defaults to terra" "$(m gpt-5.6-terra)" --
expect "FIDFAB_MODEL_TERRA override" "$(m pinned-id)"      FIDFAB_MODEL_TERRA=pinned-id -- --model terra
expect "empty override falls back"   "$(m gpt-5.6-terra)"  FIDFAB_MODEL_TERRA= -- --model terra
expect "literal ID passes through"   "$(m other-id)"       -- --model other-id
expect "luna is rejected"            "<exit 64>"           -- --model luna
expect "FIDFAB_MODEL_LUNA is ignored" "$(m gpt-5.6-terra)" FIDFAB_MODEL_LUNA=gpt-5.6-luna -- --model terra
if (cd "$stub" && env FIDFAB_MODEL_LUNA=x PATH="$stub:$PATH" CODEX_HOME="$stub/home" "$wrapper" 2>&1 >/dev/null) \
    | grep -q 'FIDFAB_MODEL_LUNA is ignored'; then echo "ok   FIDFAB_MODEL_LUNA warns on stderr"
else echo "FAIL FIDFAB_MODEL_LUNA set without a warning"; fail=1; fi
err="$(cd "$stub" && env PATH="$stub:$PATH" CODEX_HOME="$stub/home" "$wrapper" --model luna 2>&1 >/dev/null || true)"
if [[ "$err" == *"replaced by terra"* ]]; then echo "ok   luna rejection names terra"
else echo "FAIL luna rejection message does not mention terra"; fail=1; fi
expect "--effort is passed through"  '{"model":"gpt-5.6-terra",*"model_reasoning_effort":"xhigh"}' -- --model terra --effort xhigh
expect "--effort before --model"     '{"model":"gpt-5.6-terra",*"model_reasoning_effort":"low"}'   -- --effort low --model terra
expect "model with a quote is rejected"  "<exit 64>"   -- --model 'x","sandbox_mode":"read-only'
expect "model with a backslash is rejected" "<exit 64>" -- --model 'x\\y'
expect "pinned ID with a quote is rejected" "<exit 64>" 'FIDFAB_MODEL_TERRA=a"b' -- --model terra
expect "provider/model ID passes"        "$(m openai/gpt-x:1)" -- --model openai/gpt-x:1
expect "unknown --effort is rejected"   "<exit 64>"    -- --model terra --effort 'high"'
expect "--model without a value"        "<exit 64>"    -- --model
expect "--effort without a value"       "<exit 64>"    -- --model terra --effort
expect "--model with an empty value"    "<exit 64>"    -- --model ''

if grep -qE '^model[[:space:]]*=[[:space:]]*"gpt-5\.6-terra"' "$config"; then echo "ok   $config defaults to gpt-5.6-terra"
else echo "FAIL $config model is '$(grep -E '^model[[:space:]]*=' "$config" || true)'"; fail=1; fi
exit $fail
