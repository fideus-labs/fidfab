#!/usr/bin/env bash
# test-build.sh — host-side check that docker/build.sh passes the host's claude / codex
# version to the build as a floor (">=<version>") unless the version is set by hand, and
# that the Dockerfile quotes the specs that receive it, and that a host git URL rewrite
# reaches the build only when it is safe to. Stubs docker, claude and codex.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
# `docker build` logs its claude / codex version build args.
cat > "$tmp/bin/docker" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" | grep -E '^(CLAUDE_CODE|CODEX)_VERSION=' | tr '\n' ' ' > "$FIDFAB_TEST_LOG"
printf '%s\n' "$@" > "$FIDFAB_TEST_LOG.all"
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

# A host insteadOf rewrite of the URL reaches the build only when the rewritten URL is plain
# HTTPS and reads anonymously; otherwise the SSH URL and the ssh-agent are kept. The git stub
# answers the anonymous probe (which must not see the rewrite config) and is git otherwise.
real_git="$(command -v git)"
cat > "$tmp/bin/git" <<STUB
#!/usr/bin/env bash
if [[ "\$*" != *--get-url* && "\$*" == *"ls-remote -- "* ]]; then
  [[ -z "\${GIT_CONFIG_COUNT:-}\${NETRC:-}" && "\$HOME" == /dev/null && "\$PWD" == / && "\$*" == *" https://readable.test/OWNER/REPO HEAD" ]]; exit
fi
exec "$real_git" "\$@"
STUB
chmod +x "$tmp/bin/git"
repo_check() { # name, insteadOf base, expected TARGET_REPO_URL, ssh forwarded (yes/no)
  local out ssh=no
  out="$(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0="url.$2.insteadOf" GIT_CONFIG_VALUE_0=git@github.com: SSH_AUTH_SOCK=/x NETRC="$tmp/netrc" \
    docker/build.sh git@github.com:OWNER/REPO 2>&1)"
  if grep -qx -- --ssh "$FIDFAB_TEST_LOG.all"; then ssh=yes; fi
  if grep -qxF "TARGET_REPO_URL=$3" "$FIDFAB_TEST_LOG.all" && [[ "$ssh" == "$4" && "$out" != *s3cret* ]]; then
    echo "ok   $1"; else echo "FAIL $1: $(tr '\n' ' ' < "$FIDFAB_TEST_LOG.all")"; fail=1
  fi
}
ssh_url=git@github.com:OWNER/REPO
repo_check "readable HTTPS rewrite -> cloned without the agent" https://readable.test/ https://readable.test/OWNER/REPO no
repo_check "unreadable rewrite -> SSH clone with the agent" https://unreadable.test/ "$ssh_url" yes
repo_check "rewrite with credentials -> SSH clone, nothing printed" https://u:s3cret@readable.test/ "$ssh_url" yes
repo_check "helper-form rewrite with credentials -> SSH clone" https::https://u:s3cret@readable.test/ "$ssh_url" yes
repo_check "rewrite to a host path -> SSH clone with the agent" "file://$tmp/" "$ssh_url" yes

# Unquoted, the shell reads the ">" of a floor as a redirection and npm installs latest.
for spec in '"@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"' '"@openai/codex@${CODEX_VERSION}"'; do
  if grep -qF "$spec" docker/Dockerfile; then echo "ok   Dockerfile quotes $spec"; else echo "FAIL Dockerfile does not quote $spec"; fail=1; fi
done

exit "$fail"
