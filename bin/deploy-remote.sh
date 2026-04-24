#!/usr/bin/env bash
# Run by bin/deploy inside an instance directory on the server.
# Assumes the caller has already fast-forwarded to origin/main.
set -euo pipefail

cd "$(dirname "$0")/.."
instance="$(basename "$PWD")"

log() { printf '[%s] %s\n' "$instance" "$*"; }

# Per-instance overrides (container names, ports, …). Read specific keys by
# regex rather than sourcing .env — that file sets bash built-ins like UID/GID
# which are readonly and would explode a naive `source`.
read_env() {
  [[ -f .env ]] || return 0
  grep -E "^$1=" .env | tail -1 | cut -d= -f2-
}
DDBJ_VALIDATOR_APP_CONTAINER_NAME="$(read_env DDBJ_VALIDATOR_APP_CONTAINER_NAME)"
DDBJ_VALIDATOR_APP_PORT="$(read_env DDBJ_VALIDATOR_APP_PORT)"

log "HEAD $(git log -1 --format='%h %s')"

# Always build. If nothing changed, podman's layer cache makes this cheap;
# if Gemfile.lock moved, rebuilding is the only way to avoid Bundler::GemNotFound
# at unicorn boot.
log 'podman-compose build app'
podman-compose build app

# podman-compose 1.0.6 will silently keep the existing container (and old image
# ID) on `up -d` if it thinks the service is already up. --force-recreate is
# mandatory here.
log 'podman-compose up -d --force-recreate app'
podman-compose up -d --force-recreate app

cname="${DDBJ_VALIDATOR_APP_CONTAINER_NAME:-ddbj_validator_app}"
port="${DDBJ_VALIDATOR_APP_PORT:-}"

# Wait for the container to stabilize in `running`.
for _ in $(seq 1 30); do
  status="$(podman inspect "$cname" --format '{{.State.Status}}' 2>/dev/null || echo not-found)"
  [[ "$status" == running ]] && break
  sleep 1
done

if [[ "$status" != running ]]; then
  log "container is $status — dumping logs"
  podman logs --tail 60 "$cname" 2>&1 || true
  exit 1
fi

# Probe the monitoring endpoint, which runs a full biosample validation cycle
# end-to-end — anything less than a 2xx means unicorn is up but something in
# the pipeline is broken, which is the signal we want.
#
# --retry-all-errors retries on both transport errors (connect refused while
#   unicorn is still booting, timeouts from the kgio/unicorn SEGV that slipped
#   past the old probe) and HTTP 4xx/5xx when paired with --fail.
# --retry-max-time bounds total wall-clock across retries; --max-time caps
#   one attempt so a hung worker can't swallow the entire window.
if [[ -n "$port" ]]; then
  url="http://localhost:$port/api/monitoring"
  log "probing $url"
  if code=$(curl --fail --silent --output /dev/null --write-out '%{http_code}' \
                --max-time 90 --retry 10 --retry-all-errors --retry-delay 2 --retry-max-time 180 \
                "$url"); then
    log "HTTP $code"
  else
    log 'monitoring probe failed — dumping logs'
    podman logs --tail 60 "$cname" 2>&1 || true
    exit 1
  fi
fi

log 'deploy ok'
