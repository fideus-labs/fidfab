#!/usr/bin/env bash
# litellm-proxy.sh — run the local LiteLLM proxy that gives Fabro Gemini on Vertex AI.
#
# Usage:
#   scripts/litellm-proxy.sh init PROJECT_ID [KEY_FILE]  create ~/.config/fidfab-litellm/proxy.env
#   scripts/litellm-proxy.sh start    start (or recreate) the proxy container
#   scripts/litellm-proxy.sh stop     stop and remove the container
#   scripts/litellm-proxy.sh status   container state and liveliness probe
#   scripts/litellm-proxy.sh test     one chat completion per model through the proxy
#   scripts/litellm-proxy.sh logs     follow the container logs
#
# KEY_FILE is the file name of the service-account key inside the config
# directory (default litellm-proxy.json). See docs/vertex-ai-litellm.md for the
# Google Cloud side (project, service account, key) and the security model.
#
# Environment overrides:
#   FIDFAB_LITELLM_DIR    config directory (default ~/.config/fidfab-litellm)
#   FIDFAB_LITELLM_PORT   host port, bound to 127.0.0.1 only (default 4000)
#   FIDFAB_LITELLM_IMAGE  image reference, pinned by digest (default below)
#   FIDFAB_LITELLM_DNS    DNS server for the container, if Docker's default
#                         resolver cannot resolve googleapis.com (e.g. 1.1.1.1)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="${FIDFAB_LITELLM_DIR:-$HOME/.config/fidfab-litellm}"
port="${FIDFAB_LITELLM_PORT:-4000}"
name="fidfab-litellm"
config="$here/docker/litellm/config.yaml"
# LiteLLM v1.109.1, non-root variant (runs as uid 65534 unless --user is given).
# Pin by digest: LiteLLM releases and Docker tags were compromised in March and
# October 2026. Verify a new digest with cosign before changing it here
# (https://docs.litellm.ai/docs/proxy/docker_image_security).
image="${FIDFAB_LITELLM_IMAGE:-ghcr.io/berriai/litellm-non_root@sha256:e9e15fe17b66fc8cda6ff7e18914e1d452785ca404fa20336ec447152f86daba}"

note() { printf '  %s\n' "$*"; }
die() { printf 'litellm-proxy: %s\n' "$*" >&2; exit 1; }
env_value() { # name -> value from proxy.env
  sed -n "s/^$1=//p" "$dir/proxy.env" | tail -1
}

cmd_init() {
  local project="${1:-}" key="${2:-litellm-proxy.json}"
  [[ -n "$project" ]] || die "usage: $0 init PROJECT_ID [KEY_FILE]"
  [[ "$key" != */* ]] || die "KEY_FILE is a file name inside $dir, not a path"
  mkdir -p "$dir"; chmod 700 "$dir"
  if [[ -f "$dir/proxy.env" ]]; then
    note "$dir/proxy.env already exists; leaving it unchanged"
  else
    (umask 077; cat > "$dir/proxy.env" <<EOF
# fidfab LiteLLM proxy: read by scripts/litellm-proxy.sh (docker --env-file).
LITELLM_MASTER_KEY=sk-$(openssl rand -hex 32)
VERTEX_PROJECT=$project
VERTEX_CREDENTIALS_FILE=/secrets/$key
EOF
    )
    note "wrote $dir/proxy.env (mode 600) with a new LITELLM_MASTER_KEY"
  fi
  if [[ -f "$dir/$key" ]]; then
    chmod 600 "$dir/$key"
  else
    note "next: create the service-account key at $dir/$key (docs/vertex-ai-litellm.md)"
  fi
}

cmd_start() {
  [[ -f "$dir/proxy.env" ]] || die "$dir/proxy.env missing; run: $0 init PROJECT_ID"
  local key; key="$(basename "$(env_value VERTEX_CREDENTIALS_FILE)")"
  [[ -f "$dir/$key" ]] || die "service-account key $dir/$key missing"
  local args=(
    -d --name "$name" --restart unless-stopped
    # Run as the invoking user so the container can read the 600 key file.
    --user "$(id -u):$(id -g)"
    # Only this machine can reach the proxy.
    -p "127.0.0.1:$port:4000"
    # The container sees the key directory and the config, both read-only.
    -v "$dir:/secrets:ro"
    -v "$config:/etc/fidfab-litellm/config.yaml:ro"
    --env-file "$dir/proxy.env"
  )
  [[ -n "${FIDFAB_LITELLM_DNS:-}" ]] && args+=(--dns "$FIDFAB_LITELLM_DNS")
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker run "${args[@]}" "$image" --config /etc/fidfab-litellm/config.yaml --port 4000 >/dev/null
  note "started $name on http://127.0.0.1:$port/v1"
  local _
  for _ in $(seq 1 30); do
    if curl -fsS "http://127.0.0.1:$port/health/liveliness" >/dev/null 2>&1; then
      note "proxy is live"; return 0
    fi
    sleep 2
  done
  docker logs --tail 30 "$name" >&2 || true
  die "proxy did not become live; see the logs above"
}

cmd_stop() {
  if docker rm -f "$name" >/dev/null 2>&1; then note "removed $name"; else note "$name is not running"; fi
}

cmd_status() {
  docker ps -a --filter "name=^${name}$" --format '  {{.Names}}  {{.Status}}  {{.Image}}'
  if curl -fsS "http://127.0.0.1:$port/health/liveliness" >/dev/null 2>&1; then
    note "liveliness: ok (http://127.0.0.1:$port)"
  else
    note "liveliness: no answer on 127.0.0.1:$port"
  fi
}

cmd_test() {
  [[ -f "$dir/proxy.env" ]] || die "$dir/proxy.env missing"
  local master model status=0
  master="$(env_value LITELLM_MASTER_KEY)"
  for model in gemini-3.8-flash gemini-4-carbon; do
    local reply
    if reply="$(curl -fsS "http://127.0.0.1:$port/v1/chat/completions" \
        -H "Authorization: Bearer $master" -H "Content-Type: application/json" \
        -d "{\"model\": \"$model\", \"messages\": [{\"role\": \"user\", \"content\": \"Reply with the word ready.\"}]}")"; then
      note "$model: $(printf '%s' "$reply" | sed -n 's/.*"content":"\([^"]*\)".*/\1/p')"
    else
      note "$model: failed"; status=1
    fi
  done
  return $status
}

case "${1:-}" in
  init)   shift; cmd_init "$@" ;;
  start)  cmd_start ;;
  stop)   cmd_stop ;;
  status) cmd_status ;;
  test)   cmd_test ;;
  logs)   docker logs -f "$name" ;;
  -h|--help|"") sed -n '2,22p' "$0" ;;
  *) die "unknown command: $1 (see --help)" ;;
esac
