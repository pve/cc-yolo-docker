# PRD: Isolated Dev/Acc/Prod Environment with Claude Code

> **This repo is a generic framework.** Target project details are configuration, not code.  
> Current deployment: `pve/nanobot-ai` (fork of `HKUDS/nanobot`)

**Date:** 2026-04-16  
**Framework repo:** `cc-yolo-docker` (this repo, no application code)  
**Target fork:** https://github.com/pve/nanobot-ai  
**Upstream:** https://github.com/HKUDS/nanobot  
**Registry:** ghcr.io/pve/nanobot-ai  
**Host:** Single remote arm64 Linux host (Hetzner, Ubuntu 24.04), accessed via SSH

---

## Goal

A fully isolated, Docker-based environment where Claude Code can develop, deploy, and monitor nanobot across three lifecycle stages. Each environment is independently isolated. CC has maximum power in dev, observation-only access in acceptance, and read-only access in prod.

---

## Core Principle

> Code always runs in a container on the remote host. Claude Code runs inside the container alongside it.

- **Dev**: CC writes code, tests it, reads all logs, fixes issues, packages the result to an external registry.
- **Acceptance**: CC observes only — reads logs and runtime behavior of the packaged image. Cannot modify code or manage container lifecycle.
- **Prod**: CC reads logs only. No exec, no modification.

---

## Environment Summary

| | Dev | Acceptance | Prod |
|--|-----|------------|------|
| **CC placement** | Inside `cc-dev-<instance>` container, running as non-root user `claude` | Inside `cc-acc` container | Inside `cc-prod` container |
| **CC capabilities** | Full: code, build, run, logs, git, gh, push | Monitor + diagnose: logs, inspect, exec diagnostics | Read-only: logs, inspect |
| **Nanobot mode** | Run directly on host (not containerized in Phase 1) | Persistent gateway | Persistent gateway |
| **Image source** | Built from `/workspace` (fork source) | Pulled from `ghcr.io/pve/nanobot-ai:<tag>` | Pulled from `ghcr.io/pve/nanobot-ai:<tag>` |
| **Docker network** | `nanobot-dev-net` | `nanobot-acc-net` | `nanobot-prod-net` |
| **Workspace volume** | `cc-dev-<instance>_workspace` (fork source, one per instance) | n/a | n/a |
| **Data volume** | `cc-dev-<instance>_data` (`~/.nanobot`, separate per instance) | `cc-acc_data` | `cc-prod_data` |
| **CC home volume** | `cc-dev-<instance>_home` (`~/.claude`, separate per instance) | `cc-acc_home` | `cc-prod_home` |
| **SSH volume** | `cc-dev-<instance>_ssh` (`~/.ssh`, keypair for GitHub) | `cc-acc_ssh` | `cc-prod_ssh` |
| **SSH port on host** | 2222–2299 (auto-assigned per instance) | 2300 | 2301 |

---

## Multiple Dev Instances

Multiple `cc-dev` containers can run simultaneously on the same host — one per feature branch or experiment. Each instance is fully independent:

- **Container name**: `cc-dev-<instance>` (e.g. `cc-dev-main`, `cc-dev-feature-x`)
- **Workspace volume**: `cc-dev-<instance>-workspace` — own branch checked out
- **Data volume**: `cc-dev-<instance>-data` — separate nanobot config per instance
- **SSH port**: auto-assigned from range 2222–2299, recorded as Docker label `cc.ssh.port`
- **Network**: all instances share `nanobot-dev-net`

Managed via `spawn-dev.sh <instance>` (creates) and `ls-dev.sh` (lists running instances + ports).

Local `~/.ssh/config` entry per instance:
```
Host nanobot-<instance>
  HostName remote-host
  Port <assigned-port>
  User root
```

---

## Artifact Flow

```
pve/nanobot-ai (GitHub fork)
        │
        │  CC edits code, commits, pushes
        ▼
   cc-dev-<instance>
        │
        │  docker build + test
        │  docker push
        ▼
ghcr.io/pve/nanobot-ai
        │         │
        │  :acc-<sha>    :prod-<sha>
        ▼         ▼
  nanobot-acc   nanobot-prod
  (gateway)     (gateway)
        │
        │  CC observes logs + behavior
        ▼
  cc-acc (monitor only)
```

---

## Environment Isolation

Each environment is isolated at three layers:

1. **Docker network**: bridge networks with no cross-environment routing
2. **Named volumes**: separate data volumes per environment and per dev instance
3. **Docker socket access**:
   - `cc-dev-*`: raw Docker socket (full access)
   - `cc-acc`: filtered via **Tecnativa docker-socket-proxy** (GET + exec only)
   - `cc-prod`: filtered (GET only, no exec)

```
Remote Host
├── nanobot-dev-net
│   ├── cc-dev-main          (CC + full Docker socket, port 2222)
│   ├── cc-dev-feature-x     (CC + full Docker socket, port 2223)
│   └── nanobot-dev-*        (ephemeral test containers)
│
├── nanobot-acc-net
│   ├── docker-socket-proxy-acc   (Tecnativa, GET + exec)
│   ├── cc-acc               (CC + restricted socket, port 2300)
│   └── nanobot-acc-gateway  (persistent nanobot gateway)
│
└── nanobot-prod-net
    ├── docker-socket-proxy-prod  (Tecnativa, GET only)
    ├── cc-prod              (CC + read-only socket, port 2301)
    └── nanobot-prod-gateway (persistent nanobot gateway)
```

> SSH port ranges: dev instances 2222–2299, cc-acc 2300, cc-prod 2301.

---

## User Access

Users SSH directly into the CC container — one hop from local machine to CC.

```bash
ssh nanobot-main        # enters cc-dev-main
ssh nanobot-feature-x   # enters cc-dev-feature-x
ssh nanobot-acc         # enters cc-acc
```

VS Code Remote-SSH connects using the same `~/.ssh/config` entries, giving a full IDE experience inside each container.

---

## Auth

| Tool | Method |
|------|--------|
| git (push/pull) | SSH keypair in `cc-dev-<instance>-ssh` volume; public key = deploy key on `pve/nanobot-ai` |
| gh CLI | `GITHUB_TOKEN` env var (PAT with `repo` + `packages:write`) |
| ghcr.io (docker push) | Same `GITHUB_TOKEN`, via `docker login ghcr.io` |
| Claude Code | `CLAUDE_CODE_OAUTH_TOKEN` env var — OAuth token generated via `claude setup-token` on the host; injected into the container and forwarded to SSH sessions via `/home/claude/.ssh/environment`. On fresh volumes, `entrypoint.sh` bootstraps `.credentials.json` from this token so the interactive TUI opens without a browser flow. |

---

## Image Tagging Convention

| Tag | Meaning |
|-----|---------|
| `ghcr.io/pve/nanobot-ai:dev-<sha>` | Immutable build from a specific commit |
| `ghcr.io/pve/nanobot-ai:dev` | Floating — latest dev build |
| `ghcr.io/pve/nanobot-ai:acc-<sha>` | Promoted to acceptance |
| `ghcr.io/pve/nanobot-ai:acc` | Floating — currently deployed in acceptance |
| `ghcr.io/pve/nanobot-ai:latest` | Currently deployed in prod |

---

## Promotion Pipeline

### Dev → Acceptance
1. CC in dev: tests pass, `docker push` to `ghcr.io/pve/nanobot-ai:dev-<sha>`
2. CC opens PR to `pve/nanobot-ai`
3. **User manually approves** and merges PR
4. User re-tags image as `:acc-<sha>` and `:acc`, triggers acc container restart
5. cc-acc observes and reports

### Acceptance → Prod
1. User reviews cc-acc diagnostics + logs
2. **User manually approves** promotion
3. User re-tags `:acc-<sha>` as `:latest`, triggers prod container restart
4. cc-prod observes

> Automation of promotion (webhooks, GitHub Actions) deferred to a later phase.

---

## Automation in Dev

Tasks CC handles automatically (no manual steps required):

| Task | How |
|------|-----|
| Add GitHub deploy key | `gh api repos/${FORK_REPO_PATH}/keys` — runs in `setup-dev.sh`, no browser needed |
| Clone + sync fork with upstream | `setup-dev.sh` clones fork and fast-forwards to upstream/main |
| gh CLI + ghcr.io auth | `setup-dev.sh` logs in using `GITHUB_TOKEN` env var |
| Build + tag + push image | `package.sh` — CC runs this after tests pass |
| Image promotion tagging | `promote.sh` (Phase 2) — re-tags dev→acc or acc→prod on ghcr.io |

Tasks that remain manual (by design):

| Task | Why |
|------|-----|
| Update local `~/.ssh/config` | CC runs on remote host, cannot touch user's local machine |
| Approve and merge PRs | Human gate — intentional |
| Approve promotion dev→acc, acc→prod | Human gate — intentional |
| Provide `GITHUB_TOKEN` | Secret — user supplies at setup time |
| Provide `CLAUDE_CODE_OAUTH_TOKEN` | Generated once via `claude setup-token` on host; stored in `.env.dev` |

---

## File Structure

```
cc-yolo-docker/
├── PRD-overall.md                  ← this file
├── PRD-phase1.md                   ← detailed Phase 1 PRD
│
├── dev/
│   ├── README.md                   ← setup instructions + overview
│   ├── Dockerfile.cc-dev           ← cc-dev image (shared across all instances)
│   ├── docker-compose.dev.yml      ← container spec; spawn-dev.sh sets project name + port
│   ├── .env.dev.example            ← required env vars template
│   └── scripts/
│       ├── entrypoint.sh           ← starts sshd, injects authorized_keys
│       ├── spawn-dev.sh            ← create named instance (wraps docker compose -p)
│       ├── ls-dev.sh               ← list running dev instances + ports
│       ├── setup-dev.sh            ← one-time: deploy key, clone, auth, render CLAUDE.md
│       └── package.sh              ← build + tag + push to ghcr.io
│   └── CLAUDE.md.template          ← rendered into /home/claude/CLAUDE.md by setup-dev.sh
│
├── acc/
│   ├── README.md                   ← acc setup instructions (Phase 2)
│   ├── Dockerfile.cc-acc           ← cc-acc image (Phase 2)
│   └── docker-compose.acc.yml      ← acc environment (Phase 2)
│
└── prod/
    ├── README.md                   ← prod setup instructions (Phase 3)
    ├── Dockerfile.cc-prod          ← cc-prod image (Phase 3)
    └── docker-compose.prod.yml     ← prod environment (Phase 3)
```

---

## Implementation Phases

### Phase 1: Dev environment ← current
- `Dockerfile.cc-dev`: Ubuntu 24.04 + Claude Code + docker CLI + git + gh CLI + sshd
- `spawn-dev.sh`: create a named dev instance (auto-assign port, create volumes, start container)
- `ls-dev.sh`: list running instances with ports
- `setup-dev.sh`: clone fork, configure git, gh auth, deploy key, ghcr.io login, render CLAUDE.md
- `CLAUDE.md.template`: generic infrastructure context, rendered with env vars into `/home/claude/CLAUDE.md`
- `package.sh`: build nanobot image, tag with SHA, push to ghcr.io
- `dev/README.md`: setup instructions and overview

### Phase 2: Acceptance environment
- `Dockerfile.cc-acc`: CC image with restricted tooling
- docker-socket-proxy for acc (GET + exec only)
- `docker-compose.acc.yml`: cc-acc, socket proxy, nanobot-acc-gateway
- `setup-acc.sh`: pull image from ghcr.io, configure nanobot for acc, start gateway

### Phase 3: Prod environment
- Mirror of acceptance with stricter proxy (GET only, no exec)
- Stable image tag convention enforced

### Phase 4: Promotion automation (future)
- GitHub Action: on PR merge to `pve/nanobot-ai`, auto-push `:acc` tag
- Webhook-based container restart in acc/prod on new image push

---

## Backlog

- **Docker credential store warning**: `docker login ghcr.io` warns that credentials are stored unencrypted in `/root/.docker/config.json`. Configure a credential helper (e.g. `pass`) or accept the risk given the container is ephemeral and access-controlled.
- **Fork ahead of origin**: After upstream sync, workspace main is ahead of `origin/main` by the upstream commits. A `git push origin main` should follow the merge to keep the fork current on GitHub.

---

## Open Questions (to be decided during implementation)

- Which AI provider + API key for each nanobot environment config?
- Remote host SSH user + hostname (needed to run setup)
- Should `nanobot-dev-<instance>-data` be pre-seeded or built fresh via `nanobot onboard`?
- GitHub PAT: fine-grained (per-repo) or classic? Expiry policy?
