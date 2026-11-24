#!/usr/bin/env bash
# test-setup.sh — host-side check that `scripts/setup.sh fabro` skips Fabro's LLM wizard
# step (and with it the "OpenAI (Codex) detected" device-login prompt) whenever gh is
# logged in, and falls back to the interactive wizard otherwise, and that the environment
# step writes its settings.toml block exactly once, and that a secret already in the vault
# is not requested again, and that the author step copies git config user.name/email into
# [run.git.author]. Stubs fabro, gh, claude and codex.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"
cat > "$tmp/bin/fabro" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == install || "$1 ${2:-}" == "secret set" || "$1 ${2:-}" == "secret rm" || "$1 ${2:-}" == "server restart" ]] && printf '%s\n' "$*" >> "$FIDFAB_TEST_LOG"
[[ "$*" == *--value-stdin* ]] && cat >/dev/null # else the writer can die of SIGPIPE under pipefail
[[ "$1 ${2:-}" == "secret list" ]] && for n in ${FABRO_STUB_SECRETS:-}; do printf '    "name": "%s",\n' "$n"; done
[[ "$*" == *--non-interactive* && -n "${FABRO_STUB_FAIL_SCRIPTED:-}" ]] && exit 2
[[ "$1 ${2:-}" == "secret set" && -n "${FABRO_STUB_FAIL_SECRET:-}" ]] && exit 1
[[ "$1" == --version ]] && echo "fabro 0.0.0-stub"
exit 0
STUB
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
# github-app's lookup of an existing App is the one call that asks for client_id
[[ "$*" == *client_id* ]] && { [[ -n "${GH_STUB_APP:-}" ]] && echo "$GH_STUB_APP"; exit; }
[[ -n "${GH_STUB_LOGIN:-}" ]] && { echo "$GH_STUB_LOGIN"; exit 0; }
exit 1
STUB
for cli in claude codex; do
  printf '#!/usr/bin/env bash\necho "%s $*" >> "$FIDFAB_TEST_LOG"\n' "$cli" > "$tmp/bin/$cli"
done
# like the real one, a codex login leaves an auth.json behind
echo '[[ "$1" == login && -n "${CODEX_HOME:-}" ]] && echo "{}" > "$CODEX_HOME/auth.json"; exit 0' >> "$tmp/bin/codex"
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
# Each model section must carry both keys (not just the file as a whole).
n="$(awk '/^\[llm\.providers\.litellm\.models\./ { m = $0 }
          m != "" && /^capabilities = .*reasoning_effort = \{/ { c[m] = 1 }
          m != "" && /^protocol_options = \{ reasoning_effort_levels = true \}/ { p[m] = 1 }
          END { for (k in c) if (k in p) n++; print n + 0 }' "$tmp/home/.fabro/settings.toml")"
if [[ "$n" == 2 ]]; then echo "ok   litellm step declares reasoning effort on both Gemini models"; else echo "FAIL litellm step: $n models declare reasoning effort"; fail=1; fi
# A block written before the reasoning_effort keys existed is left alone, but the step says so.
mkdir -p "$tmp/oldhome/.fabro"
grep -vF 'protocol_options = ' "$tmp/home/.fabro/settings.toml" > "$tmp/oldhome/.fabro/settings.toml"
out="$(HOME="$tmp/oldhome" FIDFAB_LITELLM_DIR="$tmp/nolitellm" scripts/setup.sh litellm 2>&1 </dev/null || true)"
n="$(grep -cF 'protocol_options = ' "$tmp/oldhome/.fabro/settings.toml" || true)"
if [[ "$out" == *'models."vertex-gemini-3.8-flash"] lacks protocol_options.reasoning_effort_levels = true'* &&
      "$out" == *'models."vertex-gemini-4-carbon"] lacks protocol_options.reasoning_effort_levels = true'* &&
      "$out" != *"lacks capabilities.reasoning_effort"* && "$n" == 0 ]]; then
  echo "ok   litellm step warns about an existing block without reasoning effort"
else echo "FAIL litellm step: no warning for an old block (or block rewritten: $n): $out"; fail=1; fi
# Only one model updated by hand: the other is still reported, for both keys.
awk '/^\[llm\.providers\.litellm\.models\."vertex-gemini-4-carbon"\]/ { carbon = 1 }
     carbon && /^capabilities = / { print "capabilities = { text = true, tools = true }"; next }
     carbon && /^protocol_options = / { next }
     { print }' "$tmp/home/.fabro/settings.toml" > "$tmp/oldhome/.fabro/settings.toml"
out="$(HOME="$tmp/oldhome" FIDFAB_LITELLM_DIR="$tmp/nolitellm" scripts/setup.sh litellm 2>&1 </dev/null || true)"
if [[ "$out" == *'models."vertex-gemini-4-carbon"] lacks capabilities.reasoning_effort'* &&
      "$out" == *'models."vertex-gemini-4-carbon"] lacks protocol_options.reasoning_effort_levels = true'* &&
      "$out" != *'models."vertex-gemini-3.8-flash"] lacks'* ]]; then
  echo "ok   litellm step checks each Gemini model section"
else echo "FAIL litellm step: partly updated block not reported per model: $out"; fail=1; fi
# Sub-table and dotted forms count; an effort table without medium does not.
awk '/^\[llm\.providers\.litellm\.models\."vertex-gemini-4-carbon"\]/ { carbon = 1 }
     carbon && /^capabilities = / { next }
     carbon && /^protocol_options = / { next }
     { print }
     END { print "[llm.providers.litellm.models.\"vertex-gemini-4-carbon\".capabilities]"
           print "text = true"
           print "reasoning_effort = { low = true, high = true }   # no medium"
           print "[llm.providers.litellm.models.\"vertex-gemini-4-carbon\".protocol_options]"
           print "reasoning_effort_levels = true"
           print "[llm.providers.litellm.models.\"vertex-gemini-3.8-flash\".capabilities.reasoning_effort]"
           print "medium = true" }' "$tmp/home/.fabro/settings.toml" > "$tmp/oldhome/.fabro/settings.toml"
sed -i '/^\[llm\.providers\.litellm\.models\."vertex-gemini-3\.8-flash"\]/,/^$/{/^capabilities = /d}' "$tmp/oldhome/.fabro/settings.toml"
out="$(HOME="$tmp/oldhome" FIDFAB_LITELLM_DIR="$tmp/nolitellm" scripts/setup.sh litellm 2>&1 </dev/null || true)"
if [[ "$out" == *'models."vertex-gemini-4-carbon"] lacks capabilities.reasoning_effort'* &&
      "$out" != *'models."vertex-gemini-4-carbon"] lacks protocol_options'* &&
      "$out" != *'models."vertex-gemini-3.8-flash"] lacks'* ]]; then
  echo "ok   litellm step reads sub-table forms and requires medium"
else echo "FAIL litellm step: sub-table forms or missing medium misread: $out"; fail=1; fi
out="$(FIDFAB_LITELLM_DIR="$tmp/nolitellm" scripts/setup.sh litellm 2>&1 </dev/null || true)"
if [[ "$out" != *WARNING*lacks* ]]; then echo "ok   litellm step is quiet about a current block"
else echo "FAIL litellm step warns about a current block: $out"; fail=1; fi
: > "$FIDFAB_TEST_LOG"

# author: git config user.name/email land in [run.git.author] once, TOML-escaped.
author_cfg() { GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0="$1" \
  GIT_CONFIG_KEY_1=user.email GIT_CONFIG_VALUE_1="$2" scripts/setup.sh author; }
: > "$FIDFAB_TEST_LOG" # drop the environment step's restarts
author_cfg Ada '' >/dev/null
if grep -qF '[run.git.author]' "$tmp/home/.fabro/settings.toml"; then echo "FAIL author step: wrote a block without user.email"; fail=1; else echo "ok   author step skips when user.email is unset"; fi
author_cfg 'Ada "A\B" Lovelace' ada@example.com >/dev/null
author_cfg 'Ada "A\B" Lovelace' ada@example.com >/dev/null
check "author step restarts the server only when it adds the block" "server restart --no-upgrade-check"
# The matching lines must be exactly these, once each: a second block repeats them, wrong
# escaping drops the name line.
want="$(printf '%s\n' '[run.git.author]' 'name = "Ada \"A\\B\" Lovelace"' 'email = "ada@example.com"')"
got="$(grep -xF -f <(printf '%s\n' "$want") "$tmp/home/.fabro/settings.toml" || true)"
if [[ "$got" == "$want" ]]; then echo "ok   author step writes git config identity once, TOML-escaped"; else echo "FAIL author step: $got"; fail=1; fi
if [[ "$(author_cfg Other other@example.com)" == *WARNING* ]]; then echo "ok   author step warns when git config changed"; else echo "FAIL author step: no warning"; fail=1; fi
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
rm "$CODEX_HOME/auth.json"
FABRO_STUB_SECRETS=CODEX_AUTH_JSON_B64 scripts/setup.sh --replace codex </dev/null >/dev/null
check "--replace: codex secret set, no auth.json -> a new login, stored" \
  "codex login --device-auth
secret set --no-upgrade-check --value-stdin --description base64 of ~/.codex/auth.json (ChatGPT login or API key) CODEX_AUTH_JSON_B64"
FABRO_STUB_SECRETS=CODERABBIT_API_KEY scripts/setup.sh coderabbit </dev/null >/dev/null
check "coderabbit secret set -> kept" ""
FABRO_STUB_SECRETS=CODERABBIT_API_KEY scripts/setup.sh --replace coderabbit </dev/null >/dev/null
check "--replace: coderabbit secret set -> asked again" \
  "secret set --no-upgrade-check --description CodeRabbit agentic API key for coderabbit review --agent CODERABBIT_API_KEY"

# github-app registers an App for the organization typed in (or the user's own account) unless
# Fabro already uses one, and then gives the App's own addresses for its permissions.
mkdir -p "$tmp/apphome/.fabro"
# Only [server.integrations.github] counts, not a key of the same name in another table.
printf '[server.integrations.slack]\nstrategy = "app"\n[server.integrations.github]\nstrategy = "token"\n' \
  > "$tmp/apphome/.fabro/settings.toml"
printf '\nacme\n' | HOME="$tmp/apphome" scripts/setup.sh github-app >/dev/null
check "github-app registers an organization's App" \
  "install github --no-upgrade-check --non-interactive --strategy app --owner org:acme"
echo | HOME="$tmp/apphome" scripts/setup.sh github-app >/dev/null
check "... or one for the user's own account" \
  "install github --no-upgrade-check --non-interactive --strategy app --owner personal"
if ! printf '\nacme; rm -rf /\n' | HOME="$tmp/apphome" scripts/setup.sh github-app >/dev/null 2>&1; then
  echo "ok   github-app refuses an invalid organization name"; else echo "FAIL github-app accepted an invalid name"; fail=1; fi
check "... without registering" ""
# A slug at the first prompt adopts that App instead of registering one: its IDs and owner from
# GitHub, a key and secrets into the vault, then the settings table (comments and other tables
# kept). Unless gh can read the App and the file is a private key, Fabro is left as it was.
printf -- '-----BEGIN RSA PRIVATE KEY-----\nx\n-----END RSA PRIVATE KEY-----\n' > "$tmp/key.pem"
printf '# kept\n[server.integrations.github] # token\nstrategy = "token"\n\n# web\n[server.web]\nenabled = true\n' \
  > "$tmp/apphome/.fabro/settings.toml"
adopt() { printf '%s\n%s\n' "${2:-acme-bot}" "$1" | HOME="$tmp/apphome" scripts/setup.sh github-app 2>&1; }
on_token() { grep -qxF 'strategy = "token"' "$tmp/apphome/.fabro/settings.toml"; }
if ! adopt "$tmp/key.pem" >/dev/null && ! GH_STUB_APP="123456 Iv1.abc acme" adopt /dev/null >/dev/null &&
   ! GH_STUB_APP="123456  acme" adopt "$tmp/key.pem" >/dev/null && # an App that shows no client ID
   ! GH_STUB_APP="123456 Iv1.abc acme" adopt "$tmp/key.pem" 'acme bot;' >/dev/null && on_token; then
  echo "ok   github-app refuses an App gh cannot read, a bad slug and a file that is not a private key"
else echo "FAIL github-app adopted an App it could not read, a bad slug or a bad key file"; fail=1; fi
check "... storing nothing" ""
# The settings change last: a secret that fails to store leaves Fabro on the token strategy.
if ! FABRO_STUB_FAIL_SECRET=1 GH_STUB_APP="123456 Iv1.abc acme" adopt "$tmp/key.pem" >/dev/null && on_token; then
  echo "ok   github-app keeps the token strategy when a secret fails to store"
else echo "FAIL github-app switched strategy although a secret failed to store"; fail=1; fi
: > "$FIDFAB_TEST_LOG"
out="$(GH_STUB_APP="123456 Iv1.abc acme" adopt "$tmp/key.pem")"
check "github-app adopts an existing App: key and secrets in, gh token out, a restart, no registration" \
  "secret set --no-upgrade-check --type file --value-stdin --description private key of the GitHub App acme-bot GITHUB_APP_PRIVATE_KEY
secret set --no-upgrade-check --description client secret of the GitHub App acme-bot GITHUB_APP_CLIENT_SECRET
secret set --no-upgrade-check --value-stdin --description random: fidfab takes no GitHub webhooks GITHUB_APP_WEBHOOK_SECRET
secret rm --no-upgrade-check GITHUB_TOKEN
server restart --no-upgrade-check"
want=$'# kept\n[server.integrations.github]\nstrategy = "app"\napp_id = "123456"\nclient_id = "Iv1.abc"\nslug = "acme-bot"\n\n# web\n[server.web]\nenabled = true'
if [[ "$(cat "$tmp/apphome/.fabro/settings.toml")" == "$want" &&
      "$out" == *"https://github.com/organizations/acme/settings/apps/acme-bot and"* &&
      "$out" == *"https://github.com/apps/acme-bot/installations/new"* ]]; then
  echo "ok   github-app points the settings at the adopted App and names its pages"
else echo "FAIL github-app adopted settings: $(cat "$tmp/apphome/.fabro/settings.toml") / $out"; fail=1; fi
# Settings without the table get it appended; a personal App's page; a key path under ~.
printf '[server.web]\nenabled = true\n' > "$tmp/apphome/.fabro/settings.toml"
cp "$tmp/key.pem" "$tmp/apphome/key.pem"
# shellcheck disable=SC2088  # the literal ~ is what the step has to expand
out="$(GH_STUB_APP="123456 Iv1.abc " adopt '~/key.pem')"
want=$'[server.web]\nenabled = true\n\n[server.integrations.github]\nstrategy = "app"\napp_id = "123456"\nclient_id = "Iv1.abc"\nslug = "acme-bot"'
if [[ "$(cat "$tmp/apphome/.fabro/settings.toml")" == "$want" &&
      "$out" == *"https://github.com/settings/apps/acme-bot and"* ]]; then
  echo "ok   github-app appends the table when there is none, for a personal App and a ~ key path"
else echo "FAIL github-app appended settings: $(cat "$tmp/apphome/.fabro/settings.toml") / $out"; fail=1; fi
: > "$FIDFAB_TEST_LOG"
printf '[server.integrations.github]\nstrategy = \047app\047  # set by hand\nslug = "fabro-acme"\n' \
  > "$tmp/apphome/.fabro/settings.toml"
out="$(HOME="$tmp/apphome" scripts/setup.sh github-app </dev/null)"
check "github-app keeps an App already set up" ""
if [[ "$out" == *"https://github.com/settings/apps/fabro-acme/permissions"* &&
      "$out" == *"https://github.com/apps/fabro-acme/installations/new"* ]]; then
  echo "ok   github-app names the App's permission and installation pages"
else echo "FAIL github-app pages: $out"; fail=1; fi
out="$(GH_STUB_LOGIN=acme HOME="$tmp/apphome" scripts/setup.sh github-app </dev/null)"
if [[ "$out" == *"https://github.com/organizations/acme/settings/apps/fabro-acme/permissions"* ]]; then
  echo "ok   github-app gives an organization's App its organization's settings page"
else echo "FAIL github-app organization page: $out"; fail=1; fi
: > "$FIDFAB_TEST_LOG"
# Fabro's App install leaves only GitHub sign-in, which locks out the CLI's dev token: the step
# adds it back once (restarting the server), whatever a comment says, and leaves
# [server.auth.github] alone.
printf '[server.auth]\nmethods = ["github"]  # dev-token off\n\n[server.auth.github]\nallowed_usernames = ["octocat"]\n' \
  >> "$tmp/apphome/.fabro/settings.toml"
HOME="$tmp/apphome" scripts/setup.sh github-app </dev/null >/dev/null
HOME="$tmp/apphome" scripts/setup.sh github-app </dev/null >/dev/null
check "github-app restarts the server only when it adds the dev-token login" "server restart --no-upgrade-check"
got="$(grep -E '^(methods|allowed_usernames) =' "$tmp/apphome/.fabro/settings.toml")"
if [[ "$got" == $'methods = ["dev-token", "github"]  # dev-token off\nallowed_usernames = ["octocat"]' ]]; then
  echo "ok   github-app keeps the dev-token login next to GitHub sign-in"
else echo "FAIL github-app auth methods: $got"; fail=1; fi

exit "$fail"
