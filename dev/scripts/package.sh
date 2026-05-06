#!/usr/bin/env bash
# package.sh — build, tag, and push image to the container registry
# Run inside cc-dev: /root/scripts/package.sh [extra-tag]
# Example: /root/scripts/package.sh rc1

set -euo pipefail

WORKSPACE="/home/claude/workspace"

cd "${WORKSPACE}"

GIT_SHA=$(git rev-parse --short HEAD)
EXTRA_TAG="${1:-}"

TAGS="-t ${REGISTRY}:dev-${GIT_SHA} -t ${REGISTRY}:dev"
[ -n "${EXTRA_TAG}" ] && TAGS="${TAGS} -t ${REGISTRY}:${EXTRA_TAG}"

echo "==> Building multiplatform image from ${WORKSPACE}"
# shellcheck disable=SC2086
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    ${TAGS} \
    --push \
    .

echo ""
echo "==> Pushed:"
echo "    ${REGISTRY}:dev-${GIT_SHA} (linux/amd64, linux/arm64)"
echo "    ${REGISTRY}:dev"
[ -n "${EXTRA_TAG}" ] && echo "    ${REGISTRY}:${EXTRA_TAG}"
