#!/usr/bin/env bash
# entrypoint.sh — runs as PID 1 inside cc-dev
# Writes authorized_keys and environment for SSH sessions, then starts sshd.

set -euo pipefail

# Inject the user's public key so they can SSH straight into the container
if [ -n "${SSH_AUTHORIZED_KEY:-}" ]; then
    echo "${SSH_AUTHORIZED_KEY}" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
else
    echo "WARNING: SSH_AUTHORIZED_KEY is not set. You will not be able to SSH into this container."
fi

# Write env vars to ~/.ssh/environment so SSH sessions inherit them.
# Requires PermitUserEnvironment yes in sshd_config (set in Dockerfile).
rm -f /root/.ssh/environment
for var in GITHUB_TOKEN GITHUB_USER FORK_REPO_PATH UPSTREAM_URL REGISTRY \
           GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL \
           CLAUDE_CODE_OAUTH_TOKEN; do
    if [ -n "${!var:-}" ]; then
        echo "${var}=${!var}" >> /root/.ssh/environment
    fi
done
chmod 600 /root/.ssh/environment

# Persist /root/.claude.json inside the home volume so it survives rebuilds.
# Claude Code writes config here; the home volume covers /root/.claude/ (a directory)
# but not /root/.claude.json (a separate file). We store the real file inside the
# volume and symlink it back.
CLAUDE_JSON_STORE="/root/.claude/.claude.json"
CLAUDE_JSON_LINK="/root/.claude.json"
if [ -f "${CLAUDE_JSON_LINK}" ] && [ ! -L "${CLAUDE_JSON_LINK}" ]; then
    mv "${CLAUDE_JSON_LINK}" "${CLAUDE_JSON_STORE}"
fi
if [ -f "${CLAUDE_JSON_STORE}" ]; then
    ln -sf "${CLAUDE_JSON_STORE}" "${CLAUDE_JSON_LINK}"
fi

# Generate host keys if not already present (needed on first start)
ssh-keygen -A

exec /usr/sbin/sshd -D
