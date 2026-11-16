#!/usr/bin/env bash
# build.sh — build the fidfab sandbox image locally.
#
# Usage:
#   docker/build.sh                                  # generic image (no baked repo)
#   docker/build.sh https://github.com/OWNER/REPO    # image specialised for a target repo
#   docker/build.sh https://github.com/OWNER/REPO main fidfab:ngff-zarr
#   docker/build.sh git@github.com:OWNER/REPO        # private repo over SSH (uses ssh-agent)
#
# Environment overrides: FIDFAB_IMAGE (default fidfab:latest), UBUNTU_VERSION,
# NODE_MAJOR, RUST_TOOLCHAIN, CLAUDE_CODE_VERSION, CODEX_VERSION,
# CLAUDE_AGENT_ACP_VERSION, CODEX_ACP_VERSION, DOCKER_BUILD_EXTRA_ARGS.
#
# Unless CLAUDE_CODE_VERSION / CODEX_VERSION is set, the image gets a claude / codex at
# least as new as this host's: see the floor step below.
#
# Nothing secret is baked into the image: credentials are injected by Fabro at
# run time from its vault.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

repo_url="${1:-}"
repo_ref="${2:-main}"
image="${3:-${FIDFAB_IMAGE:-fidfab:latest}}"

args=(
  --file "$here/docker/Dockerfile"
  --tag "$image"
  --build-arg "TARGET_REPO_URL=$repo_url"
  --build-arg "TARGET_REPO_REF=$repo_ref"
)
# SSH URLs (git@host:OWNER/REPO, ssh://...) are cloned with the host's
# ssh-agent, which BuildKit exposes to the clone step only.
case "$repo_url" in
  git@*|ssh://*)
    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
      echo "error: $repo_url is an SSH URL; start ssh-agent and ssh-add your GitHub key" >&2
      exit 1
    fi
    args+=(--ssh default)
    ;;
esac
# The agent versions default to "latest", which a cached layer freezes at whatever was
# latest when it was built. Passing this host's claude / codex version as a floor reruns
# that layer whenever the host has moved on; npm then installs "latest", or the newest
# release above the floor if "latest" is behind it.
# shortcut: a host version with no release at or above it on npm (a pre-release, a local build) fails the install; set the *_VERSION variable by hand then.
for pin in claude:CLAUDE_CODE_VERSION codex:CODEX_VERSION; do
  cli="${pin%%:*}"; var="${pin#*:}"
  [[ -z "${!var:-}" ]] || continue
  host_version="$("$cli" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -n1 || true)"
  if [[ -n "$host_version" ]]; then
    echo "$cli: this host has $host_version, so the image gets at least that"
    printf -v "$var" '>=%s' "$host_version"
  fi
done
for var in UBUNTU_VERSION NODE_MAJOR RUST_TOOLCHAIN CLAUDE_CODE_VERSION CODEX_VERSION CLAUDE_AGENT_ACP_VERSION CODEX_ACP_VERSION; do
  if [[ -n "${!var:-}" ]]; then args+=(--build-arg "$var=${!var}"); fi
done
# shellcheck disable=SC2206
extra=(${DOCKER_BUILD_EXTRA_ARGS:-})

echo "Building $image${repo_url:+ for $repo_url@$repo_ref}"
DOCKER_BUILDKIT=1 docker build "${args[@]}" "${extra[@]}" "$here"
echo
echo "Built $image. Verify with: tests/test-image.sh $image"
