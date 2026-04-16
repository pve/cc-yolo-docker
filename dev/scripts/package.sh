#!/usr/bin/env bash
# package.sh — build, tag, and push image to the container registry
# Run inside cc-dev: /root/scripts/package.sh [extra-tag]
# Example: /root/scripts/package.sh rc1

set -euo pipefail

WORKSPACE="/root/workspace"

cd "${WORKSPACE}"

GIT_SHA=$(git rev-parse --short HEAD)
EXTRA_TAG="${1:-}"

echo "==> Building image from ${WORKSPACE}"
docker build -t "${REGISTRY}:dev-${GIT_SHA}" .

echo "==> Tagging as :dev (floating latest dev)"
docker tag "${REGISTRY}:dev-${GIT_SHA}" "${REGISTRY}:dev"

if [ -n "${EXTRA_TAG}" ]; then
    echo "==> Tagging as :${EXTRA_TAG}"
    docker tag "${REGISTRY}:dev-${GIT_SHA}" "${REGISTRY}:${EXTRA_TAG}"
fi

echo "==> Pushing to registry"
docker push "${REGISTRY}:dev-${GIT_SHA}"
docker push "${REGISTRY}:dev"
if [ -n "${EXTRA_TAG}" ]; then
    docker push "${REGISTRY}:${EXTRA_TAG}"
fi

echo ""
echo "==> Packaged:"
echo "    ${REGISTRY}:dev-${GIT_SHA}"
echo "    ${REGISTRY}:dev"
[ -n "${EXTRA_TAG}" ] && echo "    ${REGISTRY}:${EXTRA_TAG}"
