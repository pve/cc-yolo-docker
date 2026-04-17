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
           GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL; do
    if [ -n "${!var:-}" ]; then
        echo "${var}=${!var}" >> /root/.ssh/environment
    fi
done
chmod 600 /root/.ssh/environment

# Generate host keys if not already present (needed on first start)
ssh-keygen -A

exec /usr/sbin/sshd -D
