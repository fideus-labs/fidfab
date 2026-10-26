#!/usr/bin/env bash
# setup.sh — configure a workstation to run fidfab workflows with a local Fabro server.
#
# Idempotent and interactive where a credential is needed. Steps (each can be
# run on its own with `scripts/setup.sh <step>`):
#
#   fabro        install Fabro, upgrade to the latest pre-release, run the install wizard
#   deepseek     DeepSeek API key + DeepSeek as Fabro's default model
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
  if grep -q "$marker" "$SETTINGS"; then
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
    # Fabro's OpenAI provider (native nodes run on DeepSeek, Codex stages use
    # CODEX_AUTH_JSON_B64), so skip LLM setup with the scripted install (flags hidden from
    # `fabro install --help`); the deepseek step configures the model. Fall back to the
    # wizard when gh is unavailable or the flags stop working after the upgrade above.
    local login
    if login="$(gh api user --jq .login 2>/dev/null)" \
      && fabro install --no-upgrade-check --non-interactive --skip-llm --github-strategy token --github-username "$login"; then
      note "Scripted install done: GitHub token from gh ($login), LLM provider skipped."
    else
      note "Scripted install unavailable (gh missing, not logged in, offline, or flags changed);"
      note "running the interactive wizard (LLM provider, GitHub, local server)."
      note "Answer No to 'Configure LLM providers now?' (scripts/setup.sh deepseek sets the model), and"
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

step_deepseek() {
  bold "DeepSeek (Fabro default model)"
  note "Create a key at https://platform.deepseek.com/api_keys"
  if ! fabro provider login --provider deepseek --no-upgrade-check 2>/dev/null; then
    set_secret DEEPSEEK_API_KEY "DeepSeek API key for Fabro prompt/agent nodes"
  fi
  ensure_toml_block "[run.model]" <<'EOF'
# fidfab: DeepSeek as the default model for Fabro-native prompt and agent nodes.
# ACP stages (Claude Code, Codex) use their own subscriptions and ignore this.
[run.model]
name = "deepseek-v4-flash"
provider = "deepseek"
EOF
  fabro server restart --no-upgrade-check >/dev/null 2>&1 || true
  fabro model test deepseek --no-upgrade-check || note "model test failed; check the key and server logs"
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
}

step_doctor() {
  bold "fabro doctor"
  fabro doctor --no-upgrade-check -v || true
  note "Expected: Fabro server reachable; DeepSeek provider ready; GitHub configured; Docker available."
  note "Secrets present:"; fabro secret list --no-upgrade-check || true
}

steps=("$@")
[[ ${#steps[@]} -eq 0 ]] && steps=(fabro deepseek brave claude codex coderabbit environment doctor)
for s in "${steps[@]}"; do
  case "$s" in
    fabro|deepseek|brave|claude|codex|coderabbit|environment|doctor) "step_$s" ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "unknown step: $s" >&2; exit 64 ;;
  esac
  echo
done
