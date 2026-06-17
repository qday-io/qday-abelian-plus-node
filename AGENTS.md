# Project Instructions

Docker-only Ethereum L1 devnet (Reth + optional Lighthouse PoS). No Rust application crate in this repo.

## Commands

| Task | Command |
| --- | --- |
| Start Tier 1 | `bash docker-up.sh --profile dev up -d` |
| Start Tier 2 | `bash docker-setup-genesis.sh` then `bash docker-up.sh --profile full up -d` |
| Reset Tier 1 | `bash scripts/reset-dev.sh` |
| Health check | `bash scripts/healthcheck.sh [--el-only] [--tx]` |
| Clean runtime data | `bash scripts/clean-data.sh --full` |

## Prerequisites

- Docker Engine + Compose v2
- Python 3 + `pip install -r requirements.txt`

## Guidelines

- Use `bash docker-up.sh` (not bare `docker compose up`) so genesis alloc stays in sync with `vars.env`
- Pin container images in `vars.env` (`RETH_IMAGE`, `LIGHTHOUSE_IMAGE`)
- `FEE_RECIPIENT` in `vars.env` drives validator `--suggested-fee-recipient` via compose
- Keep shell scripts POSIX-safe (`set -euo pipefail`); match existing script style

## Docs

- [`README.md`](README.md) — quick start
- [`docs/DOCKER.md`](docs/DOCKER.md) — deployment reference
- [`docs/USAGE.md`](docs/USAGE.md) — operations & troubleshooting
