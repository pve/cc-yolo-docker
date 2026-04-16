# Claude Code — Isolated Dev Framework

This repo is a generic framework for running Claude Code in isolated Docker containers on a remote host, with separate dev, acceptance, and production environments.

## What this repo is

Infrastructure only — no application code lives here. The target project (the repo CC develops) is configured via `.env.dev` and referenced by the scripts inside `dev/`.

## Structure

```
dev/                        Active: Phase 1
  Dockerfile.cc-dev         Image definition for cc-dev containers
  docker-compose.dev.yml    Container spec (used by spawn-dev.sh)
  .env.dev.example          Configuration template
  scripts/
    entrypoint.sh           Container init (authorized_keys + sshd)
    spawn-dev.sh            Create a named dev instance
    ls-dev.sh               List running instances + ports
    setup-dev.sh            One-time setup inside a container
    package.sh              Build + push image to registry

acc/                        Phase 2 (not yet implemented)
prod/                       Phase 3 (not yet implemented)
```

## Design principles

- **Isolation**: dev, acc, prod run on separate Docker networks with separate volumes
- **CC inside containers**: Claude Code runs inside cc-dev, not on the host
- **SSH access**: users SSH directly into cc-dev containers (port range 2222–2299)
- **Multiple instances**: several cc-dev containers can run simultaneously (one per branch)
- **Fully automated setup**: `setup-dev.sh` requires no manual steps (deploy key via gh API)
- **Generic**: target project, registry, and upstream are all configured via env vars

## When working on this repo

- Changes to scripts are only active after rebuilding the cc-dev image (`docker build`)
- The PRD files (`PRD-overall.md`, `PRD-phase1.md`) are the source of truth for design decisions — update them when making architectural changes
- Test script changes by spawning a fresh instance with `scripts/spawn-dev.sh test`
