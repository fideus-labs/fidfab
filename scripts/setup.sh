#!/usr/bin/env bash
# setup.sh — configure a workstation to run fidfab workflows with a local Fabro server.
#
# Idempotent and interactive where a credential is needed; a secret that
# `fabro secret list` already shows is not asked for again, unless --replace
# comes first (`scripts/setup.sh --replace coderabbit`). Steps (each can be
# run on its own with `scripts/setup.sh <step>`):
#
#   fabro        install Fabro, upgrade to the latest pre-release, run the install wizard
#   author       commit as git config user.name / user.email ([run.git.author])
#   litellm      Fabro's LiteLLM provider for Gemini on Vertex AI (default model)
#   brave        Brave Search API key for Fabro's web search tool
#   claude       Claude Code subscription token for the Claude Code ACP agent
#   codex        Codex (ChatGPT subscription or API key) auth for the Codex ACP agent
#   coderabbit   CodeRabbit CLI agentic API key
#   environment  register the "fidfab" Docker environment with the local server
#   doctor       fabro doctor
#   github-app   switch Fabro to a GitHub App, a new one or one that exists, so each run gets a
#                token for its own repository (not among the default steps; docs/github-token.md)
#
# Nothing here writes credentials to disk outside Fabro's vault (and the
# CLIs' own login stores on this machine).
set -euo pipefail

export PATH="$HOME/.fabro/bin:$HOME/.local/bin:$PATH"
FIDFAB_IMAGE="${FIDFAB_IMAGE:-fidfab:latest}"
SETTINGS="$HOME/.fabro/settings.toml"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
note() { printf '  %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
REPLACE=""
keep_secret() { # name; true, with a note, when the vault already holds it and --replace was not given
  [[ -n "$REPLACE" ]] && return 1
  # --json, because the table layout is not a stable interface (its rows are indented).
  grep -qE "\"name\": *\"$1\"" <<<"$(fabro secret list --no-upgrade-check --json 2>/dev/null)" || return 1
  note "$1 is already set, keeping it. To replace it: scripts/setup.sh --replace <this step>."
}
set_secret() { # name description
  keep_secret "$1" || fabro secret set --no-upgrade-check --description "$2" "$1"
}
toml_str() { local s="${1//\\/\\\\}"; printf '"%s"' "${s//\"/\\\"}"; } # TOML basic string
ensure_toml_block() { # marker, heredoc on stdin
  local marker="$1" body
  body="$(cat)"
  mkdir -p "$(dirname "$SETTINGS")"; touch "$SETTINGS"
  if grep -qF -- "$marker" "$SETTINGS"; then
    note "$SETTINGS already contains $marker"
  else
    printf '\n%s\n' "$body" >> "$SETTINGS"
    note "appended $marker to $SETTINGS"
  fi
}

step_fabro() {
  bold "Fabro"
  if ! have fabro; then
    curl -fsSL https://fabro.sh/install.sh | bash
  fi
  fabro upgrade --prerelease --no-upgrade-check || true
  note "fabro $(fabro --version)"
  if [[ ! -f "$SETTINGS" ]]; then
    # With `codex` on PATH the wizard offers OpenAI device-code login, which stores a
    # ChatGPT-subscription credential routed through the Codex backend. fidfab never uses
    # Fabro's OpenAI provider (native nodes run on Gemini through LiteLLM, Codex stages use
    # CODEX_AUTH_JSON_B64), so skip LLM setup with the scripted install (flags hidden from
    # `fabro install --help`); the litellm step configures the model. Fall back to the
    # wizard when gh is unavailable or the flags stop working after the upgrade above.
    local login
    if login="$(gh api user --jq .login 2>/dev/null)" \
      && fabro install --no-upgrade-check --non-interactive --skip-llm --github-strategy token --github-username "$login"; then
      note "Scripted install done: GitHub token from gh ($login), LLM provider skipped."
    else
      note "Scripted install unavailable (gh missing, not logged in, offline, or flags changed);"
      note "running the interactive wizard (LLM provider, GitHub, local server)."
      note "Answer No to 'Configure LLM providers now?' (scripts/setup.sh litellm sets the model), and"
      note "in particular No to 'OpenAI (Codex) detected. Set up OpenAI with device code login?':"
      note "fidfab does not use Fabro's OpenAI provider; Codex stages authenticate with CODEX_AUTH_JSON_B64."
      fabro install
    fi
  fi
  if ! fabro server status --no-upgrade-check >/dev/null 2>&1; then
    fabro server start --no-upgrade-check >/dev/null 2>&1 || true
  fi
  fabro server status --no-upgrade-check || true
}

step_author() {
  bold "Git author for run commits"
  local name email
  name="$(git config user.name || true)"; email="$(git config user.email || true)"
  if [[ -z "$name" || -z "$email" ]]; then
    note "git config user.name or user.email is unset; Fabro keeps deriving the author from the GitHub credential."
    return 0
  fi
  local had=""; grep -qF "[run.git.author]" "$SETTINGS" 2>/dev/null && had=1
  ensure_toml_block "[run.git.author]" <<EOF
# fidfab: commit as the person running setup.sh (git config user.name / user.email)
# instead of the GitHub token's login and noreply address.
[run.git.author]
name = $(toml_str "$name")
email = $(toml_str "$email")
EOF
  # An existing block is kept, so say when git config has changed since it was written.
  grep -qxF -- "name = $(toml_str "$name")" "$SETTINGS" && grep -qxF -- "email = $(toml_str "$email")" "$SETTINGS" \
    || note "WARNING: [run.git.author] in $SETTINGS differs from git config; edit it, then fabro server restart."
  # Restart only for a new block: a no-op re-run should not restart the server under active runs.
  [[ -n "$had" ]] || fabro server restart --no-upgrade-check >/dev/null 2>&1 || true
}

# github_setting <key>: its value under [server.integrations.github] in $SETTINGS, unquoted;
# empty when unset.
github_setting() {
  awk -v k="$1" '/^[[:space:]]*\[/ { s = ($0 ~ /^[[:space:]]*\[server\.integrations\.github\][[:space:]]*(#.*)?$/) }
    s && $0 ~ "^[[:space:]]*" k "[[:space:]]*=" { sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]*(#.*)?$/, "")
      gsub(/["\047]/, ""); print; exit }' "$SETTINGS" 2>/dev/null || true
}

# ensure_dev_token_auth: add "dev-token" to [server.auth] methods in $SETTINGS when missing; true
# when it changed the file. Fabro's App install sets methods = ["github"], which refuses the
# CLI's dev-token login (fabro doctor: "Authentication required.").
# shortcut: line-based, so a multi-line methods array with dev-token on a later line gets it
# twice; Fabro writes the array on one line.
ensure_dev_token_auth() {
  local out
  out="$(awk '/^[[:space:]]*\[/ { s = ($0 ~ /^[[:space:]]*\[server\.auth\][[:space:]]*(#.*)?$/) }
    s && /^[[:space:]]*methods[[:space:]]*=/ { v = $0; sub(/#.*/, "", v)
      if (v !~ /dev-token/) { sub(/\[/, "[\"dev-token\", "); c = 1 } }
    { print } END { exit !c }' "$SETTINGS")" || return 1
  printf '%s\n' "$out" > "$SETTINGS" # in place, keeping the file's mode
}

# use_github_app <app id> <client id> <slug>: point [server.integrations.github] in $SETTINGS at
# that App, as Fabro's own registration writes it; comments and the other tables are kept.
# shortcut: line-based, drops every key line of the table; Fabro's keys there are one-line scalars.
use_github_app() {
  local out
  out="$(awk -v id="$1" -v client="$2" -v slug="$3" '
    function block() { d = 1
      printf "[server.integrations.github]\nstrategy = \"app\"\napp_id = \"%s\"\nclient_id = \"%s\"\nslug = \"%s\"\n", id, client, slug }
    /^[[:space:]]*\[/ { s = ($0 ~ /^[[:space:]]*\[server\.integrations\.github\][[:space:]]*(#.*)?$/)
      if (s) { block(); next } }
    s && /^[[:space:]]*[^#[:space:]]/ { next }
    { print } END { if (!d) { print ""; block() } }' "$SETTINGS")"
  printf '%s\n' "$out" > "$SETTINGS" # in place, keeping the file's mode
}

# adopt_github_app <slug>: what `fabro install github` does for an App it registers, for one that
# already exists: the App's IDs from GitHub into $SETTINGS, and a private key and client secret
# generated for this server into the vault. [server.auth] is left alone.
# Call it bare: under `||` or `if`, set -e would not stop it at a secret that failed to store.
adopt_github_app() {
  local slug="$1" app pem id client org
  [[ "$slug" =~ ^[A-Za-z0-9-]+$ ]] || { note "Not an App slug: $slug"; return 1; }
  # Its ID, client ID and, for an organization's App, the organization its settings page is under.
  app="$(gh api "apps/$slug" --jq '"\(.id) \(.client_id // "") \(.owner | if .type == "Organization" then .login else "" end)"' 2>/dev/null || true)"
  [[ "$app" =~ ^([0-9]+)\ ([A-Za-z0-9._-]+)\ ([A-Za-z0-9-]*)$ ]] \
    || { note "gh cannot read the App $slug: check the slug, and that gh is logged in to an account that sees it."; return 1; }
  id="${BASH_REMATCH[1]}" client="${BASH_REMATCH[2]}" org="${BASH_REMATCH[3]}"
  note "App ID $id. Open https://github.com/${org:+organizations/$org/}settings/apps/$slug and"
  note "generate a private key (GitHub downloads a .pem file) and a new client secret. An App"
  note "holds several of each, so whatever uses it today keeps working."
  read -rp "  Path of the downloaded .pem file: " pem || true
  pem="${pem/#\~/$HOME}"
  grep -qs -- '-----BEGIN .*PRIVATE KEY-----' "$pem" || { note "Not a private key file: $pem"; return 1; }
  base64 -w0 < "$pem" | fabro secret set --no-upgrade-check --type file --value-stdin \
    --description "private key of the GitHub App $slug" GITHUB_APP_PRIVATE_KEY
  note "Stored the private key in Fabro's vault; delete $pem."
  fabro secret set --no-upgrade-check --description "client secret of the GitHub App $slug" GITHUB_APP_CLIENT_SECRET
  # fabro doctor wants a webhook secret too; fidfab takes no webhooks, so nobody has to know it.
  head -c 32 /dev/urandom | base64 -w0 | fabro secret set --no-upgrade-check --value-stdin \
    --description "random: fidfab takes no GitHub webhooks" GITHUB_APP_WEBHOOK_SECRET
  # Last, so a failure above leaves Fabro on the strategy it had.
  use_github_app "$id" "$client" "$slug"
  note "Pointed [server.integrations.github] in $SETTINGS at the App $slug."
  # As Fabro's own switch does: the token strategy's copy of the gh login has no use any more.
  fabro secret rm --no-upgrade-check GITHUB_TOKEN >/dev/null 2>&1 || true
  fabro server restart --no-upgrade-check >/dev/null 2>&1 \
    || note "WARNING: fabro server restart failed; run it yourself so the server reads the change."
}

step_github_app() {
  bold "GitHub App: each run gets a token for its own repository (docs/github-token.md)"
  [[ -f "$SETTINGS" ]] || { note "No $SETTINGS yet: run scripts/setup.sh fabro first."; return 1; }
  local org="" owner slug login
  if [[ "$(github_setting strategy)" == app ]]; then
    note "Fabro already uses a GitHub App; not registering another."
  else
    read -rp "  Slug of an existing GitHub App to use (empty: register a new one): " slug || true
    if [[ -n "$slug" ]]; then
      adopt_github_app "$slug"
    else
      read -rp "  Organization that owns the target repositories (empty: your own account): " org || true
      if [[ -z "$org" ]]; then owner=personal
      elif [[ "$org" =~ ^[A-Za-z0-9-]+$ ]]; then owner="org:$org"
      else note "Not an organization name: $org"; return 1; fi
      note "Needs gh logged in here, and an organization owner for an organization's App. Open the"
      note "URL it prints in a browser on this machine (or forward its port over SSH)."
      fabro install github --no-upgrade-check --non-interactive --strategy app --owner "$owner"
    fi
  fi
  if ensure_dev_token_auth; then
    note "Added \"dev-token\" to [server.auth] methods in $SETTINGS: the CLI logs in with it,"
    note "the web UI keeps GitHub sign-in."
    # A rerun finds the file fixed and does not restart, so say when this one failed.
    fabro server restart --no-upgrade-check >/dev/null 2>&1 \
      || note "WARNING: fabro server restart failed; run it yourself so the server reads the change."
  fi
  slug="$(github_setting slug)"
  [[ -n "$slug" ]] || { note "No App slug in $SETTINGS; finish with docs/github-token.md."; return 0; }
  # An organization's App has its settings under the organization.
  login="${org:-$(gh api "apps/$slug" --jq '.owner | select(.type == "Organization") | .login' 2>/dev/null || true)}"
  note "Every fidfab workflow requests the repository permissions below, and a run fails at its"
  note "first stage while the App lacks one. Fabro registers its App without the last two."
  if [[ -n "$login" ]]; then
    note "1. https://github.com/organizations/$login/settings/apps/$slug/permissions"
  else
    note "1. https://github.com/settings/apps/$slug/permissions"
    note "   (an organization's App: https://github.com/organizations/ORG/settings/apps/$slug/permissions)"
  fi
  note "   Repository permissions: Contents, Pull requests and Issues Read and write; Checks, Actions"
  note "   and Commit statuses Read-only or more; leave the rest; Save changes."
  note "2. https://github.com/apps/$slug/installations/new"
  note "   Only select repositories: the ones you run fidfab on; Install. If it was installed before"
  note "   step 1, accept the permission request under the installation's Configure."
  note "3. scripts/setup.sh doctor, then a verify run on a branch with an open pull request."
  grep -qF "[run.git.author]" "$SETTINGS" \
    || note "Commits are authored by the App's bot until scripts/setup.sh author sets [run.git.author]."
}

# litellm_model_has <model> <capabilities.reasoning_effort|protocol_options.reasoning_effort_levels = true>
# True when that key is set for [llm.providers.litellm.models."<model>"] of $SETTINGS, in
# inline-table, dotted or sub-table form (comments ignored). capabilities.reasoning_effort
# must include medium = true, the level the workflows request.
# shortcut: line-based, so a table value spread over several lines is not recognised.
litellm_model_has() {
  awk -v base="[llm.providers.litellm.models.\"$1\"" -v key="$2" '
    { line = $0; sub(/#.*/, "", line) }
    line ~ /^[[:space:]]*\[/ {
      t = line; gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
      in_s = 0; prefix = ""
      if (t == base "]") in_s = 1
      else if (index(t, base ".") == 1 && substr(t, length(t)) == "]") {
        in_s = 1; prefix = substr(t, length(base) + 2); prefix = substr(prefix, 1, length(prefix) - 1) "."
      }
      next
    }
    !in_s || line !~ /=/ { next }
    {
      # <prefix><key>=<value> with all whitespace removed, e.g. capabilities.reasoning_effort={low=true,...}
      s = prefix line; gsub(/[[:space:]]/, "", s)
    }
    key == "capabilities.reasoning_effort" &&
      (s ~ /^capabilities=\{.*reasoning_effort=\{[^}]*medium=true/ ||
       s ~ /^capabilities\.reasoning_effort=\{[^}]*medium=true/ ||
       s ~ /^capabilities\.reasoning_effort\.medium=true/) { found = 1 }
    key == "protocol_options.reasoning_effort_levels = true" &&
      (s ~ /^protocol_options=\{.*reasoning_effort_levels=true/ ||
       s ~ /^protocol_options\.reasoning_effort_levels=true/) { found = 1 }
    END { exit !found }
  ' "$SETTINGS" 2>/dev/null
}

step_litellm() {
  bold "Gemini on Vertex AI through LiteLLM (Fabro default model)"
  local proxy_env="${FIDFAB_LITELLM_DIR:-$HOME/.config/fidfab-litellm}/proxy.env"
  local port="${FIDFAB_LITELLM_PORT:-4000}"
  note "Google Cloud project, service account and proxy: docs/vertex-ai-litellm.md"
  if ! curl -fsS --max-time 5 "http://127.0.0.1:$port/health/liveliness" >/dev/null 2>&1; then
    note "No LiteLLM proxy answers on 127.0.0.1:$port. Start it first:"
    note "  scripts/litellm-proxy.sh init PROJECT_ID && scripts/litellm-proxy.sh start"
  fi
  ensure_toml_block "[llm.providers.litellm]" <<EOF
# fidfab: Fabro's built-in LiteLLM provider, pointed at the local proxy
# (scripts/litellm-proxy.sh). api_model must match model_name in
# docker/litellm/config.yaml. The workflows select vertex-gemini-3.8-flash in
# their workflow.toml [run.model]; no workflow uses vertex-gemini-4-carbon, which
# a native node can pin. ACP stages (Claude Code, Codex) ignore both.
# The reasoning_effort capability lets the workflows request their effort level (medium);
# Fabro only sends reasoning_effort to a model whose catalog row declares it.
[llm.providers.litellm]
base_url = "http://localhost:$port/v1"
default_model = "vertex-gemini-3.8-flash"
enabled = true

[llm.providers.litellm.models."vertex-gemini-3.8-flash"]
display_name = "Gemini 3.8 Flash (Vertex AI)"
api_model = "gemini-3.8-flash"
limits = { context_tokens = 1048576, max_output_tokens = 65536 }
capabilities = { text = true, tools = true, reasoning = true, reasoning_effort = { low = true, medium = true, high = true } }
protocol_options = { reasoning_effort_levels = true }
small_default = true

[llm.providers.litellm.models."vertex-gemini-4-carbon"]
display_name = "Gemini 4 Carbon (Vertex AI)"
api_model = "gemini-4-carbon"
limits = { context_tokens = 1048576, max_output_tokens = 65536 }
capabilities = { text = true, tools = true, reasoning = true, reasoning_effort = { low = true, medium = true, high = true } }
protocol_options = { reasoning_effort_levels = true }
EOF
  # An existing block is left alone (it may hold the user's own settings), so say what it lacks.
  # shortcut: whole-file literal match, so the same text in a comment or another provider hides
  # the warning; parse the TOML if settings.toml gains a second localhost provider.
  local want model
  for want in "base_url = \"http://localhost:$port/v1\"" \
    '[llm.providers.litellm.models."vertex-gemini-3.8-flash"]' \
    '[llm.providers.litellm.models."vertex-gemini-4-carbon"]'; do
    grep -qF -- "$want" "$SETTINGS" \
      || note "WARNING: $SETTINGS lacks $want; edit [llm.providers.litellm] to match docs/vertex-ai-litellm.md section 7"
  done
  # Fabro sends reasoning_effort only to a model whose own row declares both keys, so check
  # each Gemini section rather than the whole file.
  for model in vertex-gemini-3.8-flash vertex-gemini-4-carbon; do
    for want in 'capabilities.reasoning_effort' 'protocol_options.reasoning_effort_levels = true'; do
      litellm_model_has "$model" "$want" \
        || note "WARNING: $SETTINGS [llm.providers.litellm.models.\"$model\"] lacks $want; edit it to match docs/vertex-ai-litellm.md section 7"
    done
  done
  if grep -q '^\[run\.model\]' "$SETTINGS" 2>/dev/null; then
    note "$SETTINGS has a [run.model] table (from the former DeepSeek step). fabro run does not"
    note "send it to the server; the workflows set [run.model] in workflow.toml. Remove it."
  fi
  if [[ -f "$proxy_env" ]] && grep -q '^LITELLM_MASTER_KEY=' "$proxy_env"; then
    sed -n 's/^LITELLM_MASTER_KEY=//p' "$proxy_env" | tail -1 | tr -d '\n' \
      | fabro secret set --no-upgrade-check --value-stdin --description "LiteLLM proxy master key (scripts/litellm-proxy.sh)" LITELLM_API_KEY
    note "stored LITELLM_API_KEY from $proxy_env"
  else
    set_secret LITELLM_API_KEY "LiteLLM proxy master key (scripts/litellm-proxy.sh)"
  fi
  fabro server restart --no-upgrade-check >/dev/null 2>&1 || true
  for model in vertex-gemini-3.8-flash vertex-gemini-4-carbon; do
    fabro model test --model "$model" --tools --no-upgrade-check \
      || note "$model test failed; check scripts/litellm-proxy.sh status and the proxy logs"
  done
}

step_brave() {
  bold "Brave Search"
  keep_secret BRAVE_SEARCH_API_KEY && return 0
  note "Create a key at https://brave.com/search/api/ (the Data for AI plan covers agent use)"
  note "Fabro prefers Brave for its web_search tool whenever BRAVE_SEARCH_API_KEY is in the vault."
  set_secret BRAVE_SEARCH_API_KEY "Brave Search API key for Fabro web_search"
}

step_claude() {
  bold "Claude Code (ACP, subscription)"
  keep_secret CLAUDE_CODE_OAUTH_TOKEN && return 0
  if have claude; then
    note "Generating a long-lived subscription token with: claude setup-token"
    note "(Log in with your Claude Pro/Max account in the browser when prompted.)"
    token="$(claude setup-token 2>/dev/null | grep -oE 'sk-ant-oat[0-9A-Za-z_-]+' | tail -1 || true)"
    if [[ -n "$token" ]]; then
      printf '%s' "$token" | fabro secret set --no-upgrade-check --value-stdin --description "Claude Code OAuth token (claude setup-token)" CLAUDE_CODE_OAUTH_TOKEN
      note "stored CLAUDE_CODE_OAUTH_TOKEN"
    else
      note "Could not capture the token automatically. Run 'claude setup-token', copy the token, then:"
      set_secret CLAUDE_CODE_OAUTH_TOKEN "Claude Code OAuth token (claude setup-token)"
    fi
  else
    note "Claude Code is not installed on this host (npm install -g @anthropic-ai/claude-code)."
    note "Run 'claude setup-token' somewhere, then paste the token:"
    set_secret CLAUDE_CODE_OAUTH_TOKEN "Claude Code OAuth token (claude setup-token)"
  fi
}

step_codex() {
  bold "Codex (ACP, ChatGPT subscription or API key)"
  local codex_home="${CODEX_HOME:-$HOME/.codex}"
  # An existing auth.json is still copied below: that refreshes the secret without asking anything.
  if [[ ! -f "$codex_home/auth.json" ]] && keep_secret CODEX_AUTH_JSON_B64; then return 0; fi
  if have codex; then
    if [[ ! -f "$codex_home/auth.json" ]]; then
      note "Logging in with the device-code flow: codex login --device-auth"
      codex login --device-auth || codex login
    fi
  fi
  if [[ -f "$codex_home/auth.json" ]]; then
    base64 -w0 < "$codex_home/auth.json" | fabro secret set --no-upgrade-check --value-stdin --description "base64 of ~/.codex/auth.json (ChatGPT login or API key)" CODEX_AUTH_JSON_B64
    note "stored CODEX_AUTH_JSON_B64 from $codex_home/auth.json"
    note "Subscription tokens refresh over time; re-run 'scripts/setup.sh codex' if Codex stages start failing to authenticate."
  else
    note "No Codex login found. Either install Codex (npm install -g @openai/codex) and re-run, or store an API key:"
    read -r -s -p "  OPENAI_API_KEY (input hidden, leave empty to skip): " key; echo
    if [[ -n "$key" ]]; then
      printf '{"OPENAI_API_KEY":"%s"}' "$key" | base64 -w0 | fabro secret set --no-upgrade-check --value-stdin --description "base64 of a Codex auth.json holding an API key" CODEX_AUTH_JSON_B64
      note "stored CODEX_AUTH_JSON_B64 (API key)"
    fi
  fi
}

step_coderabbit() {
  bold "CodeRabbit CLI"
  keep_secret CODERABBIT_API_KEY && return 0
  note "Create an Agentic API key in the CodeRabbit dashboard (Settings → API keys)."
  set_secret CODERABBIT_API_KEY "CodeRabbit agentic API key for coderabbit review --agent"
}

step_environment() {
  bold "Fabro environment: fidfab ($FIDFAB_IMAGE)"
  if ! docker image inspect "$FIDFAB_IMAGE" >/dev/null 2>&1; then
    note "Image $FIDFAB_IMAGE not found locally. Build it with: docker/build.sh <target-repo-url>"
  fi
  ensure_toml_block "[environments.fidfab]" <<EOF
# fidfab: locally built sandbox image. The server imports this table into its
# environment catalog on start-up; the workflows also declare it themselves.
[environments.fidfab]
provider = "docker"

[environments.fidfab.image]
docker = "$FIDFAB_IMAGE"

[environments.fidfab.lifecycle]
preserve = false
stop_on_terminal = true
EOF
  fabro server restart --no-upgrade-check >/dev/null 2>&1 || true
  note "Select it per run: fabro run <workflow> --environment fidfab (Fabro ignores the workflow's run.environment.id)."
}

step_doctor() {
  bold "fabro doctor"
  fabro doctor --no-upgrade-check -v || true
  note "Expected: Fabro server reachable; litellm provider ready; GitHub configured; Docker available."
  note "Secrets present:"; fabro secret list --no-upgrade-check || true
}

steps=("$@")
[[ ${#steps[@]} -eq 0 ]] && steps=(fabro author litellm brave claude codex coderabbit environment doctor)
for s in "${steps[@]}"; do
  case "$s" in
    fabro|author|litellm|brave|claude|codex|coderabbit|environment|doctor) "step_$s" ;;
    github-app) step_github_app ;;
    --replace) REPLACE=1; continue ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown step: $s" >&2; exit 64 ;;
  esac
  echo
done
