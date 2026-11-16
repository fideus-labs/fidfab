#!/usr/bin/env bash
# test-build.sh — host-side check that docker/build.sh passes the host's claude / codex
# version to the build as a floor (">=<version>") unless the version is set by hand, and
# that the Dockerfile quotes the specs that receive it. Stubs docker, claude and codex.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
# `docker build` logs its claude / codex version build args.
cat > "$tmp/bin/docker" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" | grep -E '^(CLAUDE_CODE|CODEX)_VERSION=' | tr '\n' ' ' > "$FIDFAB_TEST_LOG"
STUB
printf '#!/usr/bin/env bash\necho "${HOST_claude:?}"\n' > "$tmp/bin/claude"
printf '#!/usr/bin/env bash\necho "${HOST_codex:?}"\n'  > "$tmp/bin/codex"
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" FIDFAB_TEST_LOG="$tmp/calls"
unset CLAUDE_CODE_VERSION CODEX_VERSION
export HOST_claude="2.1.325 (Claude Code)" HOST_codex="codex-cli 0.154.0"

fail=0
check() { # name, expected version build args
  if [[ "$(cat "$FIDFAB_TEST_LOG")" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: $(cat "$FIDFAB_TEST_LOG")"; fail=1; fi
}

docker/build.sh >/dev/null
check "host versions -> passed as floors" "CLAUDE_CODE_VERSION=>=2.1.325 CODEX_VERSION=>=0.154.0 "

CLAUDE_CODE_VERSION=latest docker/build.sh >/dev/null
check "explicit CLAUDE_CODE_VERSION wins" "CLAUDE_CODE_VERSION=latest CODEX_VERSION=>=0.154.0 "

HOST_claude="" docker/build.sh >/dev/null
check "host claude prints no version -> no floor for it" "CODEX_VERSION=>=0.154.0 "

# Unquoted, the shell reads the ">" of a floor as a redirection and npm installs latest.
for spec in '"@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"' '"@openai/codex@${CODEX_VERSION}"'; do
  if grep -qF "$spec" docker/Dockerfile; then echo "ok   Dockerfile quotes $spec"; else echo "FAIL Dockerfile does not quote $spec"; fail=1; fi
done

exit "$fail"
