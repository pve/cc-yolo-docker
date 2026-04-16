#!/usr/bin/env bash
# spawn-dev.sh — create a named cc-dev instance
# Usage: spawn-dev.sh <instance-name>
# Example: spawn-dev.sh main
#          spawn-dev.sh feature-x

set -euo pipefail

INSTANCE="${1:-}"
if [ -z "${INSTANCE}" ]; then
    echo "Usage: spawn-dev.sh <instance-name>"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_DIR="$(dirname "${SCRIPT_DIR}")"
ENV_FILE="${DEV_DIR}/.env.dev"

if [ ! -f "${ENV_FILE}" ]; then
    echo "ERROR: ${ENV_FILE} not found. Copy .env.dev.example and fill it in."
    exit 1
fi

# Load env vars
set -a; source "${ENV_FILE}"; set +a

PROJECT="cc-dev-${INSTANCE}"
PORT_RANGE_START=2222
PORT_RANGE_END=2299

# Check instance doesn't already exist
if docker ps -a --filter "label=cc.instance=${INSTANCE}" --filter "label=cc.env=dev" \
        --format '{{.Names}}' | grep -q .; then
    echo "ERROR: Dev instance '${INSTANCE}' already exists."
    echo "  Start it:   docker compose -p ${PROJECT} -f ${DEV_DIR}/docker-compose.dev.yml start"
    echo "  Remove it:  docker compose -p ${PROJECT} -f ${DEV_DIR}/docker-compose.dev.yml down -v"
    exit 1
fi

# Auto-assign next free port in range
assign_port() {
    local used_ports
    used_ports=$(docker ps --filter "label=cc.env=dev" \
        --format '{{.Label "cc.ssh.port"}}' 2>/dev/null || true)

    for port in $(seq "${PORT_RANGE_START}" "${PORT_RANGE_END}"); do
        if ! echo "${used_ports}" | grep -qx "${port}" && \
           ! ss -tlnp 2>/dev/null | grep -q ":${port} "; then
            echo "${port}"
            return
        fi
    done
    echo "ERROR: No free ports in range ${PORT_RANGE_START}–${PORT_RANGE_END}" >&2
    exit 1
}

SSH_PORT=$(assign_port)

echo "==> Spawning cc-dev-${INSTANCE} on SSH port ${SSH_PORT}"

INSTANCE="${INSTANCE}" SSH_PORT="${SSH_PORT}" \
    docker compose \
        -p "${PROJECT}" \
        -f "${DEV_DIR}/docker-compose.dev.yml" \
        up -d --build

echo ""
echo "==> Add to your local ~/.ssh/config:"
echo ""
echo "    Host nanobot-${INSTANCE}"
echo "      HostName <remote-host>"
echo "      Port ${SSH_PORT}"
echo "      User root"
echo "      IdentityFile ~/.ssh/id_ed25519"
echo ""
echo "==> First time? Run one-time setup inside the container:"
echo "    docker exec cc-dev-${INSTANCE} /root/scripts/setup-dev.sh"
