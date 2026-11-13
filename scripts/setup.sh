#!/usr/bin/env bash
# setup.sh — configure a workstation to run fidfab workflows with a local Fabro server.
#
# Idempotent and interactive where a credential is needed. Steps (each can be
# run on its own with `scripts/setup.sh <step>`):
#
#   fabro        install Fabro, upgrade to the latest pre-release, run the install wizard
#   litellm      Fabro's LiteLLM provider for Gemini on Vertex AI (default model)
#   brave        Brave Search API key for Fabro's web search tool
#   claude       Claude Code subscription token for the Claude Code ACP agent
#   codex        Codex (ChatGPT subscription or API key) auth for the Codex ACP agent
#   coderabbit   CodeRabbit CLI agentic API key
#   environment  register the "fidfab" Docker environment with the local server
#   doctor       fabro doctor
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
secret_exists() { fabro secret list --no-upgrade-check 2>/dev/null | grep -qx "$1" || fabro secret list --no-upgrade-check 2>/dev/null | grep -q "^$1\b"; }
set_secret() { # name description
  local name="$1" desc="$2"
  if secret_exists "$name"; then
    read -r -p "  Secret $name already exists. Replace it? [y/N] " yn
    [[ "$yn" =~ ^[Yy] ]] || return 0
  fi
  fabro secret set --no-upgrade-check --description "$desc" "$name"
}
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
# their workflow.toml [run.model]; the Carbon review nodes pin
# vertex-gemini-4-carbon. ACP stages (Claude Code, Codex) ignore both.
[llm.providers.litellm]
base_url = "http://localhost:$port/v1"
default_model = "vertex-gemini-3.8-flash"
enabled = true

[llm.providers.litellm.models."vertex-gemini-3.8-flash"]
display_name = "Gemini 3.8 Flash (Vertex AI)"
api_model = "gemini-3.8-flash"
limits = { context_tokens = 1048576, max_output_tokens = 65536 }
capabilities = { text = true, tools = true }
small_default = true

[llm.providers.litellm.models."vertex-gemini-4-carbon"]
display_name = "Gemini 4 Carbon (Vertex AI)"
api_model = "gemini-4-carbon"
limits = { context_tokens = 1048576, max_output_tokens = 65536 }
capabilities = { text = true, tools = true }
EOF
  # An existing block is left alone (it may hold the user's own settings), so say what it lacks.
  local want
  for want in "base_url = \"http://localhost:$port/v1\"" \
    '[llm.providers.litellm.models."vertex-gemini-3.8-flash"]' \
    '[llm.providers.litellm.models."vertex-gemini-4-carbon"]'; do
    grep -qF -- "$want" "$SETTINGS" \
      || note "WARNING: $SETTINGS lacks $want; edit [llm.providers.litellm] to match docs/vertex-ai-litellm.md section 7"
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
  local model
  for model in vertex-gemini-3.8-flash vertex-gemini-4-carbon; do
    fabro model test --model "$model" --tools --no-upgrade-check \
      || note "$model test failed; check scripts/litellm-proxy.sh status and the proxy logs"
  done
}

step_brave() {
  bold "Brave Search"
  note "Create a key at https://brave.com/search/api/ (the Data for AI plan covers agent use)"
  note "Fabro prefers Brave for its web_search tool whenever BRAVE_SEARCH_API_KEY is in the vault."
  set_secret BRAVE_SEARCH_API_KEY "Brave Search API key for Fabro web_search"
}

step_claude() {
  bold "Claude Code (ACP, subscription)"
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
[[ ${#steps[@]} -eq 0 ]] && steps=(fabro litellm brave claude codex coderabbit environment doctor)
for s in "${steps[@]}"; do
  case "$s" in
    fabro|litellm|brave|claude|codex|coderabbit|environment|doctor) "step_$s" ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "unknown step: $s" >&2; exit 64 ;;
  esac
  echo
done
