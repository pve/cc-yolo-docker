This repo deploys a container on a remote host with Claude Code installed inside it.
So even your local Docker setup is not touched.

It was originally conceived for testing and developing nanobot instances with a dangerously running Claude Code.

# Dev Environment

Claude Code runs inside `cc-dev-<instance>` containers on the remote host. Multiple named instances can run simultaneously — one per feature branch or experiment.

There are three tiers of access. Each tier has a distinct role in setup and ongoing use.

---

## GitHub Token

Everything in the dev environment authenticates with a single GitHub Personal Access Token (PAT). It is stored in `.env.dev` on the remote host and injected into each container at startup.

### Creating the token

Use a **classic PAT** — fine-grained PATs do not yet fully support pushing to `ghcr.io`.

Go to **[github.com/settings/tokens/new](https://github.com/settings/tokens/new)** and select these scopes:

| Scope | Why |
|-------|-----|
| `repo` | Clone, push, PRs, and deploy key management via API |
| `write:packages` | Push images to `ghcr.io` |
| `read:packages` | Pull images from `ghcr.io` |

Set an expiry (90 days recommended) and add a calendar reminder to rotate it before it expires.

### Where it goes

Paste the generated token into `.env.dev` as `GITHUB_TOKEN`. It is passed to each container as an environment variable and used by:

- `gh auth login` — GitHub CLI
- `docker login ghcr.io` — container registry push/pull
- `gh api repos/.../keys` — deploy key management

`.env.dev` is listed in `.gitignore` and must never be committed.

---

## Tier 1 — Local machine (your laptop)

**Role:** SSH client only. Nothing runs here except your terminal and VS Code.

### One-time setup

Add entries to `~/.ssh/config` for each container instance you create:

```
# Access to the remote host itself (for bootstrapping only)
Host nanobot-host
  HostName <remote-host>
  User <user>
  IdentityFile ~/.ssh/id_ed25519

# Access directly into a cc-dev container (ongoing work)
Host nanobot-dev
  HostName <remote-host>
  Port 2222
  User root
  IdentityFile ~/.ssh/id_ed25519
```

After bootstrap, you only ever use the `nanobot-dev` (port 2222) entry — you SSH straight into the container, bypassing the host.

### Ongoing use

```bash
ssh nanobot-dev          # terminal into cc-dev-main
# or: open VS Code → Remote-SSH → nanobot-main
```

---

## Tier 2 — Remote host (port 22, bootstrap only)

**Role:** Docker daemon host. You log in here once to bootstrap the cc-dev image and first instance. After that, Claude Code manages everything from inside the container.

### Prerequisites

- Docker installed and running
- Ports 2222–2299 open in firewall

### One-time bootstrap

```bash
ssh hetznerhost.griddlejuiz.com

# Clone the infrastructure repo (public, no auth needed)
git clone https://github.com/pve/cc-docker-test.git /root/cc-docker-test
cd /root/cc-docker-test/dev

# Configure environment (copy example, fill in secrets)
cp .env.dev.example .env.dev
vim .env.dev    # fill in GITHUB_TOKEN, GIT_AUTHOR_NAME, GIT_AUTHOR_EMAIL, SSH_AUTHORIZED_KEY

# Build the cc-dev image
docker build -f Dockerfile.cc-dev -t cc-dev .

# Spawn the first dev instance
scripts/spawn-dev.sh main
```

`spawn-dev.sh` prints the assigned SSH port and the `~/.ssh/config` snippet to add locally.

To update the infrastructure later: `git pull` in `/root/cc-docker-test`, then rebuild the image.

That's all that happens on the remote host. From here on, Claude Code inside the container manages the dev environment.

---

## Tier 3 — Inside cc-dev container (port 2222, ongoing)

**Role:** Where all development happens. Claude Code has full control: code, Docker, git, gh CLI, package builds.

### One-time setup (first SSH session)

```bash
ssh nanobot-main
/root/scripts/setup-dev.sh
```

`setup-dev.sh` is fully automated — no browser, no manual steps:
- Generates SSH keypair, adds it as a deploy key to `pve/nanobot-ai` via GitHub API
- Clones the fork into `/root/workspace`, adds upstream remote, syncs with `HKUDS/nanobot`
- Authenticates gh CLI and logs into ghcr.io — both using `GITHUB_TOKEN`

After this, run `claude` and CC takes over.

### What Claude Code can do from inside the container

| Task | How |
|------|-----|
| Edit nanobot source | Full read/write on `/root/workspace` |
| Build + test nanobot | `docker build` + `docker run --rm` (via host Docker socket) |
| Read all logs | `docker logs`, files in `/root/.nanobot/` |
| Commit and push | `git` in `/root/workspace`, SSH key already configured |
| Open pull requests | `gh pr create` |
| Package image to registry | `/root/scripts/package.sh` → pushes to `ghcr.io/pve/nanobot-ai` |
| Spawn additional dev instances | `/root/scripts/spawn-dev.sh feature-x` (has Docker socket) |
| List running instances | `/root/scripts/ls-dev.sh` |
| Sync fork with upstream | `git fetch upstream && git merge --ff-only upstream/main` |

### Ongoing workflow

```bash
ssh nanobot-main
claude                              # start Claude Code

# CC works autonomously — edits code, runs tests, reads logs, fixes issues
# When ready to package:
/root/scripts/package.sh                 # builds + pushes ghcr.io/pve/nanobot-ai:dev-<sha>

# To work on a parallel branch, CC spawns a new instance:
/root/scripts/spawn-dev.sh feature-x    # creates cc-dev-feature-x, prints new port
```

---

## Instance management

```bash
# List all dev instances and their SSH ports
/root/scripts/ls-dev.sh

# Stop an instance (preserves volumes)
docker compose -p cc-dev-feature-x -f /path/to/docker-compose.dev.yml stop

# Remove an instance and all its data (destructive)
docker compose -p cc-dev-feature-x -f /path/to/docker-compose.dev.yml down -v
```

---

## File reference

| File | Used by | Purpose |
|------|---------|---------|
| `Dockerfile.cc-dev` | Remote host (build time) | cc-dev image definition |
| `docker-compose.dev.yml` | `spawn-dev.sh` | Declarative container spec |
| `.env.dev.example` | You | Template for secrets and identity |
| `scripts/entrypoint.sh` | Container (PID 1) | Injects `authorized_keys`, starts sshd |
| `scripts/spawn-dev.sh` | Remote host or CC in container | Create a named dev instance |
| `scripts/ls-dev.sh` | Remote host or CC in container | List instances + SSH ports |
| `scripts/setup-dev.sh` | CC in container (once) | Clone fork, auth, deploy key, render + commit CLAUDE.md — fully automated |
| `scripts/package.sh` | CC in container | Build + tag + push image to ghcr.io |
| `CLAUDE.md.template` | `setup-dev.sh` | Template rendered into `/root/workspace/CLAUDE.md` on first setup |
