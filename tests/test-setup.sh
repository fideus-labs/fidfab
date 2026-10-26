#!/usr/bin/env bash
# test-setup.sh — host-side check that `scripts/setup.sh fabro` skips Fabro's LLM wizard
# step (and with it the "OpenAI (Codex) detected" device-login prompt) whenever gh is
# logged in, and falls back to the interactive wizard otherwise. Stubs fabro and gh.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"
cat > "$tmp/bin/fabro" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == install ]] && printf '%s\n' "$*" >> "$FIDFAB_TEST_LOG"
[[ "$*" == *--non-interactive* && -n "${FABRO_STUB_FAIL_SCRIPTED:-}" ]] && exit 2
[[ "$1" == --version ]] && echo "fabro 0.0.0-stub"
exit 0
STUB
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
[[ -n "${GH_STUB_LOGIN:-}" ]] && { echo "$GH_STUB_LOGIN"; exit 0; }
exit 1
STUB
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

exit "$fail"
