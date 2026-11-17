#!/usr/bin/env bash
# test-setup.sh — host-side check that `scripts/setup.sh fabro` skips Fabro's LLM wizard
# step (and with it the "OpenAI (Codex) detected" device-login prompt) whenever gh is
# logged in, and falls back to the interactive wizard otherwise, and that the environment
# step writes its settings.toml block exactly once, and that a secret already in the vault
# is not requested again. Stubs fabro, gh, claude and codex.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"
cat > "$tmp/bin/fabro" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == install || "$1 ${2:-}" == "secret set" ]] && printf '%s\n' "$*" >> "$FIDFAB_TEST_LOG"
[[ "$*" == *--value-stdin* ]] && cat >/dev/null # else the writer can die of SIGPIPE under pipefail
[[ "$1 ${2:-}" == "secret list" ]] && for n in ${FABRO_STUB_SECRETS:-}; do printf '    "name": "%s",\n' "$n"; done
[[ "$*" == *--non-interactive* && -n "${FABRO_STUB_FAIL_SCRIPTED:-}" ]] && exit 2
[[ "$1" == --version ]] && echo "fabro 0.0.0-stub"
exit 0
STUB
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
[[ -n "${GH_STUB_LOGIN:-}" ]] && { echo "$GH_STUB_LOGIN"; exit 0; }
exit 1
STUB
for cli in claude codex; do
  printf '#!/usr/bin/env bash\necho "%s $*" >> "$FIDFAB_TEST_LOG"\n' "$cli" > "$tmp/bin/$cli"
done
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" HOME="$tmp/home" FIDFAB_TEST_LOG="$tmp/calls"

fail=0
check() { # name, expected install args
  if [[ "$(cat "$FIDFAB_TEST_LOG")" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: $(cat "$FIDFAB_TEST_LOG")"; fail=1; fi
  : > "$FIDFAB_TEST_LOG"
}

GH_STUB_LOGIN=octocat scripts/setup.sh fabro >/dev/null
check "gh logged in -> scripted install skips the LLM step" \
  "install --no-upgrade-check --non-interactive --skip-llm --github-strategy token --github-username octocat"

scripts/setup.sh fabro >/dev/null
check "gh unavailable -> interactive wizard" "install"

GH_STUB_LOGIN=octocat FABRO_STUB_FAIL_SCRIPTED=1 scripts/setup.sh fabro >/dev/null
check "scripted flags rejected -> falls back to the wizard" \
  "install --no-upgrade-check --non-interactive --skip-llm --github-strategy token --github-username octocat
install"

mkdir -p "$tmp/home/.fabro"; : > "$tmp/home/.fabro/settings.toml"
scripts/setup.sh fabro >/dev/null
check "settings.toml present -> no install" ""

# ensure_toml_block must match its marker literally: as a regex, "[environments.fidfab]" is
# a bracket expression that matches almost any line, which made the step a silent no-op.
scripts/setup.sh environment >/dev/null; scripts/setup.sh environment >/dev/null
n="$(grep -cF '[environments.fidfab]' "$tmp/home/.fabro/settings.toml")"
if [[ "$n" == 1 ]]; then echo "ok   environment step appends its block once"; else echo "FAIL environment step: $n blocks"; fail=1; fi

# The Gemini catalog rows must declare reasoning_effort, or Fabro drops the medium effort the
# workflows request. Run before the secret checks below; its own secret call is discarded.
FIDFAB_LITELLM_DIR="$tmp/nolitellm" scripts/setup.sh litellm >/dev/null 2>&1 </dev/null || true
n="$(grep -cF 'protocol_options = { reasoning_effort_levels = true }' "$tmp/home/.fabro/settings.toml")"
if [[ "$n" == 2 ]]; then echo "ok   litellm step declares reasoning effort on both Gemini models"; else echo "FAIL litellm step: $n models declare reasoning effort"; fail=1; fi
# A block written before the reasoning_effort keys existed is left alone, but the step says so.
mkdir -p "$tmp/oldhome/.fabro"
grep -vF 'protocol_options = ' "$tmp/home/.fabro/settings.toml" > "$tmp/oldhome/.fabro/settings.toml"
out="$(HOME="$tmp/oldhome" FIDFAB_LITELLM_DIR="$tmp/nolitellm" scripts/setup.sh litellm 2>&1 </dev/null || true)"
n="$(grep -cF 'protocol_options = ' "$tmp/oldhome/.fabro/settings.toml" || true)"
if [[ "$out" == *"lacks protocol_options = { reasoning_effort_levels = true }"* && "$n" == 0 ]]; then
  echo "ok   litellm step warns about an existing block without reasoning effort"
else echo "FAIL litellm step: no warning for an old block (or block rewritten: $n)"; fail=1; fi
out="$(FIDFAB_LITELLM_DIR="$tmp/nolitellm" scripts/setup.sh litellm 2>&1 </dev/null || true)"
if [[ "$out" != *WARNING*lacks* ]]; then echo "ok   litellm step is quiet about a current block"
else echo "FAIL litellm step warns about a current block: $out"; fail=1; fi
: > "$FIDFAB_TEST_LOG"

FABRO_STUB_SECRETS="BRAVE_SEARCH_API_KEY CLAUDE_CODE_OAUTH_TOKEN" scripts/setup.sh brave claude >/dev/null
check "secrets already in the vault -> not requested again" ""

FABRO_STUB_SECRETS="BRAVE_SEARCH_API_KEY_OLD" scripts/setup.sh brave >/dev/null
check "secret missing -> requested" \
  "secret set --no-upgrade-check --description Brave Search API key for Fabro web_search BRAVE_SEARCH_API_KEY"

# Codex: no login on this host and the secret is set -> nothing asked; with an auth.json the
# secret is refreshed from it, which asks nothing either.
export CODEX_HOME="$tmp/codex"; mkdir -p "$CODEX_HOME"
FABRO_STUB_SECRETS=CODEX_AUTH_JSON_B64 scripts/setup.sh codex >/dev/null
check "codex secret set, no auth.json -> no login, no prompt" ""

echo '{}' > "$CODEX_HOME/auth.json"
FABRO_STUB_SECRETS=CODEX_AUTH_JSON_B64 scripts/setup.sh codex >/dev/null
check "codex secret set, auth.json present -> refreshed from it" \
  "secret set --no-upgrade-check --value-stdin --description base64 of ~/.codex/auth.json (ChatGPT login or API key) CODEX_AUTH_JSON_B64"

exit "$fail"
