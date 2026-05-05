#!/usr/bin/env bash
# setup-dev.sh — one-time setup inside a cc-dev container
# Run: docker exec -u claude cc-dev-<instance> /opt/cc/scripts/setup-dev.sh
# Fully non-interactive: deploy key is added to GitHub automatically via gh API.

set -euo pipefail

FORK_SSH="git@github.com:${FORK_REPO_PATH}.git"
WORKSPACE="/home/claude/workspace"

echo "==> gh CLI will use GITHUB_TOKEN from environment automatically"

if docker info &>/dev/null 2>&1; then
    echo "==> Logging into container registry"
    echo "${GITHUB_TOKEN}" | docker login ghcr.io -u "${GITHUB_USER}" --password-stdin
else
    echo "==> Skipping registry login (no Docker socket available)"
fi

echo "==> Configuring git identity"
git config --global user.name  "${GIT_AUTHOR_NAME}"
git config --global user.email "${GIT_AUTHOR_EMAIL}"
git config --global init.defaultBranch main

echo "==> Generating SSH key pair (if not already present)"
if [ ! -f /home/claude/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -C "${GIT_AUTHOR_EMAIL}" -f /home/claude/.ssh/id_ed25519 -N ""
fi

KEY_TITLE="cc-dev-$(hostname)"
PUB_KEY="$(cat /home/claude/.ssh/id_ed25519.pub)"
KEY_MATERIAL="$(echo "${PUB_KEY}" | awk '{print $1, $2}')"

echo "==> Adding deploy key '${KEY_TITLE}' to ${FORK_REPO_PATH}"
# Remove any key with the same title OR same key material (handles container hostname changes)
while IFS= read -r key_id; do
    [ -z "${key_id}" ] && continue
    echo "    Removing existing key (id=${key_id})"
    gh api -X DELETE "repos/${FORK_REPO_PATH}/keys/${key_id}"
done < <(gh api "repos/${FORK_REPO_PATH}/keys" \
    --jq ".[] | select(.title == \"${KEY_TITLE}\" or (.key | startswith(\"${KEY_MATERIAL}\"))) | .id" \
    2>/dev/null || true)
gh api "repos/${FORK_REPO_PATH}/keys" \
    -f title="${KEY_TITLE}" \
    -f key="${PUB_KEY}" \
    -F read_only=false
echo "    Deploy key added."

echo "==> Cloning fork (if workspace is empty)"
if [ ! -d "${WORKSPACE}/.git" ]; then
    git clone "${FORK_SSH}" "${WORKSPACE}"
fi

echo "==> Adding upstream remote (if not already set)"
cd "${WORKSPACE}"
if ! git remote | grep -q upstream; then
    git remote add upstream "${UPSTREAM_URL}"
fi

echo "==> Fetching upstream and syncing main"
git fetch upstream
git checkout main
git merge --ff-only upstream/main || {
    echo "WARNING: fast-forward failed — fork has local commits ahead of upstream."
    echo "         Review with: git log upstream/main..HEAD"
}

echo "==> Installing nanobot (editable) with uv"
uv venv --quiet --allow-existing "${WORKSPACE}/.venv"
VIRTUAL_ENV="${WORKSPACE}/.venv" uv pip install --no-cache -e "${WORKSPACE}"

echo "==> Rendering CLAUDE.md from template"
envsubst < /opt/cc/CLAUDE.md.template > /home/claude/CLAUDE.md

echo ""
echo "==> Setup complete. Run 'claude' to start Claude Code."
