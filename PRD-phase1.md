# PRD: Phase 1 — Dev Environment

## Overview
A containerized dev environment on a single remote arm64 host (e.g. Hetzner, Ubuntu 24.04) where Claude Code lives inside `cc-dev`, has full control over the nanobot codebase, and packages built images to ghcr.io for downstream environments.

---

## Workflow

```
cc-dev container (remote host)
  │
  ├── edit code in /workspace (nanobot fork)
  ├── docker build → nanobot-dev image
  ├── docker run → ephemeral nanobot-dev-* containers (test/verify)
  ├── read all logs (build logs, container stdout/stderr, nanobot app logs)
  ├── fix, rebuild, re-test
  ├── git commit + push → user's fork on GitHub
  ├── gh pr create → upstream PR
  └── docker push → ghcr.io/<user>/nanobot:<tag>
                         │
                    [Phase 2: acc pulls this image]
```

---

## Container: cc-dev

### Base image
`ubuntu:24.04` (arm64 — target host is Hetzner arm64)

### Tools installed in image
| Tool | Purpose |
|------|---------|
| Claude Code CLI (`claude`) | AI coding agent |
| docker CLI | Build images, run/stop/inspect containers, read logs |
| git | Version control |
| gh CLI | GitHub PRs, releases, repo management |
| curl, jq | Scripting and API calls |
| vim | In-container file editing fallback |
| openssh-client | Git over SSH to GitHub |

> Note: Only the Docker **client** binary is installed. The host Docker daemon socket is mounted in.

### Mounts / Volumes
| Mount | Type | Path in container | Purpose |
|-------|------|-------------------|---------|
| `cc-dev-<instance>_workspace` | named volume | `/home/claude/workspace` | Nanobot fork source code (persists across rebuilds) |
| `cc-dev-<instance>_home` | named volume | `/home/claude/.claude` | CC config, credentials, `.claude.json`, settings |
| `cc-dev-<instance>_ssh` | named volume | `/home/claude/.ssh` | SSH key pair for GitHub auth |
| `cc-dev-<instance>_data` | named volume | `/home/claude/.nanobot` | Nanobot config and state |

### Environment variables (passed at runtime)
| Variable | Purpose |
|----------|---------|
| `GITHUB_TOKEN` | GitHub classic PAT with `repo` + `packages:write` + `read:packages` scope. Used by gh CLI and docker login to ghcr.io |
| `GITHUB_USER` | GitHub username; used for ghcr.io login |
| `FORK_REPO_PATH` | `user/repo` format, e.g. `pve/nanobot-ai` |
| `UPSTREAM_URL` | HTTPS URL of the upstream repo to sync from |
| `REGISTRY` | ghcr.io image path without tag, e.g. `ghcr.io/pve/nanobot-ai` |
| `GIT_AUTHOR_NAME` | Git commit identity |
| `GIT_AUTHOR_EMAIL` | Git commit identity |
| `SSH_AUTHORIZED_KEY` | User's local public key — written to `/home/claude/.ssh/authorized_keys` at startup |
| `CLAUDE_CODE_OAUTH_TOKEN` | OAuth token for Claude Code auth. Generated once via `claude setup-token` on the local machine. Bypasses macOS Keychain (unavailable in containers/SSH). Forwarded to SSH sessions via `/home/claude/.ssh/environment`. On fresh volumes, `entrypoint.sh` bootstraps `/home/claude/.claude/.credentials.json` so the interactive TUI opens without a browser flow. |

### Network
- Attached to `nanobot-dev-net` only
- No access to `nanobot-acc-net` or `nanobot-prod-net`

### Startup
Container runs persistently via `sshd -D`. User enters directly via SSH — no `docker exec` needed:
```bash
ssh nanobot-main   # or nanobot-<instance>
```

---

## Nanobot in Dev (Phase 1)

In Phase 1, nanobot is **not containerized**. CC runs nanobot directly in the workspace (`/home/claude/workspace`) rather than inside ephemeral Docker containers. This avoids complexity and keeps the focus on getting CC itself running correctly.

Nanobot config and state live in `/home/claude/.nanobot/`, backed by the `cc-dev-<instance>_data` named volume (persists across rebuilds).

> Containerized nanobot (`nanobot-dev-*` ephemeral containers) is deferred to a later phase.

---

## Docker Network
- Name: `nanobot-dev-net`
- Driver: `bridge`
- Scope: dev environment only
- Members: `cc-dev`, `nanobot-dev-*` containers

---

## Auth

### SSH key (for git push/pull to GitHub)

- Generated once inside the container and stored in the `ssh` named volume (persists across rebuilds)
- Public key registered as a deploy key on the fork via `gh api` — done automatically by `setup-dev.sh`
- `git remote` uses `git@github.com:<user>/nanobot-ai.git`

### GITHUB_TOKEN (for gh CLI + GHCR)

- Classic PAT — required scopes: `repo`, `packages:write`, `read:packages`
- Passed as env var; `gh` CLI picks it up automatically, no `gh auth login` needed
- `setup-dev.sh` runs `docker login ghcr.io` using the token on first setup

### CLAUDE_CODE_OAUTH_TOKEN (for Claude Code)

- Generated once on the local machine: `claude setup-token`
- Stored in `.env.dev` (gitignored); copied to the remote host via `scp` (see Deployment Workflow)
- Injected as env var at container startup and forwarded to SSH sessions via `/home/claude/.ssh/environment`
- On fresh volumes, `entrypoint.sh` bootstraps `/home/claude/.claude/.credentials.json` from this token so the interactive TUI opens without a browser auth flow
- Survives container rebuilds — no interactive `claude` login ever needed inside the container
- `/home/claude/.claude.json` (CC config) is symlinked to inside the `home` volume so it persists across rebuilds

---

## Image Packaging (ghcr.io)

After code is working and tests pass, CC packages the image:

```bash
# Tag with git short SHA for traceability
GIT_SHA=$(git -C /workspace rev-parse --short HEAD)

docker build -t ghcr.io/<user>/nanobot:dev-${GIT_SHA} /workspace
docker push ghcr.io/<user>/nanobot:dev-${GIT_SHA}

# Also update floating :dev tag
docker tag ghcr.io/<user>/nanobot:dev-${GIT_SHA} ghcr.io/<user>/nanobot:dev
docker push ghcr.io/<user>/nanobot:dev
```

Tags:
- `ghcr.io/<user>/nanobot:dev-<sha>` — immutable, per-commit
- `ghcr.io/<user>/nanobot:dev` — floating, always latest dev build
- `ghcr.io/<user>/nanobot:<semver>` — (future) stable release for acc/prod

---

## What CC Can See in Dev

| Capability | How |
|-----------|-----|
| Nanobot source code | `/workspace` (full read/write) |
| Build logs | `docker build` stdout |
| Container stdout/stderr | `docker logs nanobot-dev-test-*` |
| Nanobot app logs | Written to `/home/claude/.nanobot/` (backed by `data` volume); readable directly from the filesystem |
| Docker events | `docker events --filter name=nanobot-dev-*` |
| Container state | `docker inspect`, `docker ps` |
| Git history | `git log`, `git diff` in `/workspace` |

---

## Files to Create

| File | Purpose |
|------|---------|
| `cc-yolo-docker/Dockerfile.cc-dev` | cc-dev container image |
| `cc-yolo-docker/docker-compose.dev.yml` | Orchestrates cc-dev + networking + volumes |
| `cc-yolo-docker/.env.dev.example` | Template for required env vars |
| `cc-yolo-docker/scripts/setup-dev.sh` | One-time remote host setup (create network, volumes, clone fork, init SSH key) |
| `cc-yolo-docker/scripts/package.sh` | Image build + tag + push to ghcr.io (run by CC inside cc-dev) |

---

## Deployment Workflow

### First-time host setup (run once)

```bash
# 1. On remote host: clone the framework repo
ssh hetznerhost.griddlejuiz.com
git clone https://github.com/pve/cc-yolo-docker.git /root/cc-yolo-docker
exit

# 2. On local machine: generate Claude Code OAuth token (opens browser once)
claude setup-token
# Copy the printed token

# 3. On local machine: fill in .env.dev
cp dev/.env.dev.example dev/.env.dev
# Edit dev/.env.dev — fill in GITHUB_TOKEN, CLAUDE_CODE_OAUTH_TOKEN, and other vars

# 4. Copy .env.dev to the remote host (.env.dev is gitignored — never committed)
scp dev/.env.dev hetznerhost.griddlejuiz.com:/root/cc-yolo-docker/dev/.env.dev

# 5. On local machine: add entry to ~/.ssh/config
# Host nanobot-main
#   HostName hetznerhost.griddlejuiz.com
#   Port 2222
#   User claude
#   IdentityFile ~/.ssh/id_ecdsa
```

### Spawning a dev instance (run once per instance)

```bash
# On local machine: spawn the instance (builds image on remote host via ssh-forwarded Docker context,
# or run spawn-dev.sh directly on the host)
ssh hetznerhost.griddlejuiz.com 'cd /root/cc-yolo-docker/dev && bash scripts/spawn-dev.sh main'

# One-time setup inside the container (clones fork, adds deploy key, renders CLAUDE.md)
ssh hetznerhost.griddlejuiz.com 'docker exec -u claude cc-dev-main /opt/cc/scripts/setup-dev.sh'

# SSH in
ssh nanobot-dev
```

### Updating the framework (code changes to scripts/Dockerfile/compose)

```bash
# 1. On local machine: commit and push changes
git add <files>
git commit -m "..."
git push origin main

# 2. On remote host: pull latest
ssh hetznerhost.griddlejuiz.com 'cd /root/cc-yolo-docker && git pull'

# 3. Take down and respawn (rebuilds the image with updated scripts/Dockerfile)
ssh hetznerhost.griddlejuiz.com \
  'cd /root/cc-yolo-docker/dev && \
   docker compose -p cc-dev-main down && \
   bash scripts/spawn-dev.sh main'
```

> Volumes (`workspace`, `ssh`, `home`, `data`) are preserved across respawn — named volumes are not removed by `docker compose down` without `-v`.

### Updating secrets (.env.dev changes)

`.env.dev` is gitignored and never committed. When secrets change (token rotation, new var added):

```bash
# Edit locally
vi dev/.env.dev

# Copy to remote host
scp dev/.env.dev hetznerhost.griddlejuiz.com:/root/cc-yolo-docker/dev/.env.dev

# Respawn to pick up new env vars
ssh hetznerhost.griddlejuiz.com \
  'cd /root/cc-yolo-docker/dev && \
   docker compose -p cc-dev-main down && \
   bash scripts/spawn-dev.sh main'
```

---

## Acceptance Criteria for Phase 1

- [ ] `cc-dev` container starts and stays running
- [ ] CC can edit files in `/workspace` and see changes persist after container restart
- [ ] `docker build` of nanobot succeeds from inside cc-dev
- [ ] Ephemeral `nanobot-dev-*` container runs and CC can read its logs
- [ ] `git push` to fork succeeds from inside cc-dev
- [ ] `gh pr create` works from inside cc-dev
- [ ] `docker push` to ghcr.io succeeds with correct tags
- [ ] cc-dev has no network path to `nanobot-acc-net` or `nanobot-prod-net`

---

## Open Questions / Decisions Deferred to Phase 2

- Nanobot config (provider + API key) for the dev volume — set up during onboard
- Promotion trigger: how acc picks up a new `:dev` tag from ghcr.io
- Whether `nanobot-dev-data` is pre-seeded from acc/prod config or starts fresh
