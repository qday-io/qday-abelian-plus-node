# Docker Deployment

**Docker Compose only** — no local `reth`, `lighthouse`, or `lcli` required.

## What you need

| Item | Required? |
| --- | --- |
| `examples/docker-compose-main.yml` | **Yes** — runs all services |
| `examples/docker-setup-genesis.sh` | **Yes** for PoS — one-time genesis ceremony in containers |
| `examples/vars.mainnet-equivalent.env` | **Yes** — paths, chainId, images |
| `examples/env.example` | **Yes** — copy to `examples/.env` for compose interpolation |
| `scripts/README.md` | Optional — script catalog with usage examples |
| `scripts/healthcheck.sh` | Optional — verify from host |

## Pre-funded accounts

Accounts are hardcoded in `genesis.json` (`alloc` field). To add or change accounts,
edit `examples/genesis.mainnet-equivalent.json` directly.

| Variable | Default | Description |
| --- | --- | --- |
| `PREFUNDED_ACCOUNT` | Hardhat account #0 | Account used for healthcheck balance check |

## Profiles

| Profile | Stack | Genesis ceremony | Start |
| --- | --- | --- | --- |
| `dev` | Dev Reth `--dev` (Tier 1) | none | `docker compose --env-file examples/.env -f examples/docker-compose-main.yml --profile dev up -d` |
| `full` | Dev PoS (Tier 2) | `bash examples/docker-setup-genesis.sh` | `docker compose --env-file examples/.env -f examples/docker-compose-main.yml --profile full up -d` |
| `dev` (mainnet) | Mainnet-eq Reth `--dev` | none | `docker compose --env-file examples/.env -f examples/docker-compose-main.yml --profile dev up -d` |
| `full` (mainnet) | Mainnet-equivalent PoS | `bash examples/docker-setup-genesis.sh` | `docker compose --env-file examples/.env -f examples/docker-compose-main.yml --profile full up -d` |

## Examples

**Dev Tier 1**

```bash
docker compose --env-file examples/.env \
  -f examples/docker-compose-main.yml --profile dev up -d
bash scripts/healthcheck.sh --env examples/vars.mainnet-equivalent.env --el-only --tx
```

**Dev Tier 2**

```bash
bash examples/docker-setup-genesis.sh
docker compose --env-file examples/.env \
  -f examples/docker-compose-main.yml --profile full up -d
bash scripts/healthcheck.sh --env examples/vars.mainnet-equivalent.env
```

**Mainnet-equivalent Tier 1**

```bash
docker compose --env-file examples/.env \
  -f examples/docker-compose-main.yml --profile dev up -d
bash scripts/healthcheck.sh --env examples/vars.mainnet-equivalent.env --el-only
```

**Mainnet-equivalent Tier 2**

```bash
bash examples/docker-setup-genesis.sh
docker compose --env-file examples/.env \
  -f examples/docker-compose-main.yml --profile full up -d
bash scripts/healthcheck.sh --env examples/vars.mainnet-equivalent.env
```

**Custom account balances (example)**

Edit `examples/genesis.mainnet-equivalent.json` alloc field directly.
**Verify**

```bash
bash scripts/healthcheck.sh --env examples/vars.mainnet-equivalent.env --el-only --tx   # Tier 1
bash scripts/healthcheck.sh --env examples/vars.mainnet-equivalent.env                  # Tier 2 (PoS)
```

**Stop**

```bash
docker compose --profile dev --profile full down
docker compose -f examples/docker-compose-main.yml down
```

## Images

Compose reads image tags from `examples/.env` via `--env-file`. Shell scripts source them from `examples/vars.mainnet-equivalent.env`:

- `RETH_IMAGE` (default `ghcr.io/paradigmxyz/reth:v2.3.0`)
- `LIGHTHOUSE_IMAGE` (default `sigp/lighthouse:v8.2.0`)
- `LCLI_IMAGE` (default `abelian-lcli:latest`)
- `FEE_RECIPIENT` — passed to validator `--suggested-fee-recipient` via compose

Full variable reference: see [`examples/env.example`](../examples/env.example).

Compose services include healthchecks; Tier 2 beacon/validator wait for EL/BN readiness.

## Troubleshooting

| Issue | Fix |
| --- | --- |
| Image pull fails | Retry `docker compose pull` when network is stable |
| Port 1545 in use | `docker compose … down`, stop other stacks |
| Pre-funded balance wrong | Tier 1: `down -v`, then `up -d`; Tier 2: `FORCE=1 examples/docker-setup-genesis.sh` |
| Missing `RETH_IMAGE` / `LIGHTHOUSE_IMAGE` | Use `--env-file examples/.env` or copy from `examples/env.example` |
| Missed CL genesis | `FORCE=1` re-run `examples/docker-setup-genesis.sh`, start within `GENESIS_DELAY` seconds |
| `lcli` flag error | Pin `LIGHTHOUSE_IMAGE` to a compatible version |
