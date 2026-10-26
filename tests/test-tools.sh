#!/usr/bin/env bash
# Verify the base toolchain inside the fidfab image.
set -euo pipefail
fail=0
check() { if "$@" >/dev/null 2>&1; then echo "[tools] ok   $*"; else echo "[tools] FAIL $*"; fail=1; fi; }
check bash -c '. /etc/os-release && [ "$VERSION_ID" = "24.04" ]'
check pixi --version
check rustc --version
check cargo --version
check cargo nextest --version
check sccache --version
check bash -c '[ "$RUSTC_WRAPPER" = sccache ] && [ "$SCCACHE_CACHE_SIZE" = 25G ]'
check node --version
check vp --version
check uv --version
check serena --version
check ccc version
check gh --version
check claude --version
check codex --version
check coderabbit --version
check claude-agent-acp --version
check codex-acp --version
check test -f "$HOME/.claude/skills/planning-with-files/SKILL.md"
check test -f "$HOME/.claude/skills/code-review/SKILL.md"
check test -f "$HOME/.claude/skills/security-audit/SKILL.md"
check test -f "$HOME/.agents/skills/planning-with-files/SKILL.md"
check test -f "$HOME/.claude/settings.json"
check test -f "$HOME/.codex/config.toml"
check grep -q serena "$HOME/.claude.json"
check grep -q cocoindex-code "$HOME/.codex/config.toml"
# Vite+ ships node/npm shims in its fallback-bin; the system Node must win.
check bash -c '[ "$(command -v node)" = /usr/bin/node ]'
# The build-time manifest is written by fidfab-doctor; every tool must be found.
check bash -c 'test -s /opt/fidfab/manifest.json && ! grep -q MISSING /opt/fidfab/manifest.json'
# GitHub's host keys are pinned so private target repos can be cloned over SSH.
check ssh-keygen -F github.com -f /etc/ssh/ssh_known_hosts
check ssh-keygen -F '[ssh.github.com]:443' -f /etc/ssh/ssh_known_hosts
# A baked clone must fetch with GITHUB_TOKEN at run time, so its origin is HTTPS
# on a host that serves git over HTTPS (ssh.github.com does not).
if [[ -d /opt/fidfab/repo/.git ]]; then
  check bash -c 'u="$(git -C /opt/fidfab/repo remote get-url origin)" && [[ $u == https://* && $u != https://ssh.github.com/* ]]'
fi
for s in fidfab-bootstrap fidfab-claude-acp fidfab-codex-acp fidfab-coderabbit fidfab-diff fidfab-pr-status fidfab-doctor fidfab-warm-cache; do check command -v "$s"; done
# pixi can create an environment offline-free (uses the warm cache if present)
tmp="$(mktemp -d)"; ( cd "$tmp" && pixi init -q . >/dev/null && pixi --version >/dev/null ) && echo "[tools] ok   pixi init" || { echo "[tools] FAIL pixi init"; fail=1; }
rm -rf "$tmp"
# A Rust checkout warmed by fidfab-warm-cache is served from sccache afterwards:
# rebuilding into an empty target dir must hit the cache for the library crate.
tmp="$(mktemp -d)"
( cd "$tmp" && export CARGO_TARGET_DIR="$tmp/target" \
  && cargo new -q --lib dep && cargo new -q app && cargo add -q --manifest-path app/Cargo.toml --path dep \
  && fidfab-warm-cache "$tmp/app" >/dev/null 2>&1 \
  && rm -rf "$tmp/target" && sccache --zero-stats >/dev/null && cargo build -q --manifest-path app/Cargo.toml \
  && sccache --show-stats | grep -Eq 'Cache hits +[1-9]' ) \
  && echo "[tools] ok   sccache warm cache" || { echo "[tools] FAIL sccache warm cache"; fail=1; }
rm -rf "$tmp"
fidfab-doctor || true
exit $fail
