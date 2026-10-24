#!/usr/bin/env bash
# build.sh — build the fidfab sandbox image locally.
#
# Usage:
#   docker/build.sh                                  # generic image (no baked repo)
#   docker/build.sh https://github.com/OWNER/REPO    # image specialised for a target repo
#   docker/build.sh https://github.com/OWNER/REPO main fidfab:ngff-zarr
#
# Environment overrides: FIDFAB_IMAGE (default fidfab:latest), UBUNTU_VERSION,
# NODE_MAJOR, RUST_TOOLCHAIN, CLAUDE_CODE_VERSION, CODEX_VERSION,
# CLAUDE_AGENT_ACP_VERSION, CODEX_ACP_VERSION, DOCKER_BUILD_EXTRA_ARGS.
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
for var in UBUNTU_VERSION NODE_MAJOR RUST_TOOLCHAIN CLAUDE_CODE_VERSION CODEX_VERSION CLAUDE_AGENT_ACP_VERSION CODEX_ACP_VERSION; do
  if [[ -n "${!var:-}" ]]; then args+=(--build-arg "$var=${!var}"); fi
done
# shellcheck disable=SC2206
extra=(${DOCKER_BUILD_EXTRA_ARGS:-})

echo "Building $image${repo_url:+ for $repo_url@$repo_ref}"
DOCKER_BUILDKIT=1 docker build "${args[@]}" "${extra[@]}" "$here"
echo
echo "Built $image. Verify with: tests/test-image.sh $image"
