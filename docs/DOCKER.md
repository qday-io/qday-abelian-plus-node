# Docker Deployment

**Docker Compose only** — no local `reth`, `lighthouse`, or `lcli` required.

## What you need

| Item | Required? |
| --- | --- |
| `docker-compose.yml` | **Yes** — runs all services |
| `docker-setup-genesis.sh` | **Yes** for PoS — one-time genesis ceremony in containers |
| `vars.env` / `examples/vars.mainnet-equivalent.env` | **Yes** — paths, chainId, mnemonic, account balances |
| `.env` / `.env.example` | **Yes** — copy `.env.example` to `.env` for compose interpolation |
| `scripts/README.md` | Optional — script catalog with usage examples |
| `scripts/render-genesis.sh` | Called by `docker-setup-genesis.sh` and run manually for Tier 1 |
| `scripts/healthcheck.sh` / `check.sh` | Optional — verify from host |
| `python3` + `eth-account` | **Yes** for genesis rendering (`pip install eth-account`) |

## Pre-funded accounts

Accounts are **not** hand-edited in `genesis.json` for day-to-day use. Set them in
`vars.env`:

| Variable | Default | Description |
| --- | --- | --- |
| `MNEMONIC` | `test test … junk` | BIP-39 mnemonic (Hardhat / Anvil default) |
| `GENESIS_ACCOUNT_COUNT` | `4` | Number of HD accounts to fund |
| `GENESIS_ACCOUNT_BALANCE_ETH` | `1000000` | Default balance per account (ETH) |
| `GENESIS_ACCOUNT_BALANCES_ETH` | `1000000,…` (×4) | Comma-separated per-account ETH balances |

`scripts/render-genesis.sh` derives addresses (`m/44'/60'/0'/0/N`) and writes `alloc`
into `GENESIS_FILE`. It also syncs `config.chainId` from `CHAIN_ID`.

**Tier 1:** run `render-genesis.sh` before compose, or `docker-setup-genesis.sh` for Tier 2.

**Tier 2:** `docker-setup-genesis.sh` renders genesis first, then `reth init` and `lcli`.

After changing mnemonic or balances on an **existing** Tier 1 node, wipe the dev volume:

```bash
docker compose --profile dev down -v
docker compose --env-file .env --profile dev up -d
```

Tier 2 requires `FORCE=1 bash docker-setup-genesis.sh` to re-bind the consensus layer.

## Profiles

| Profile | Stack | Genesis ceremony | Start |
| --- | --- | --- | --- |
| `dev` | Dev Reth `--dev` (Tier 1) | render only (`render-genesis.sh`) | `docker compose --env-file .env --profile dev up -d` |
| `full` | Dev PoS (Tier 2) | `bash docker-setup-genesis.sh` | `docker compose --env-file .env --profile full up -d` |
| `dev` (mainnet) | Mainnet-eq Reth `--dev` | render via `render-genesis.sh` | `docker compose --env-file examples/.env -f examples/docker-compose-main.yml --profile dev up -d` |
| `full` (mainnet) | Mainnet-equivalent PoS | `bash examples/docker-setup-genesis.sh` | `docker compose --env-file examples/.env -f examples/docker-compose-main.yml --profile full up -d` |

## Examples

**Dev Tier 1**

```bash
docker compose --env-file .env --profile dev up -d
bash scripts/healthcheck.sh --el-only --tx
```

**Dev Tier 2**

```bash
bash docker-setup-genesis.sh
docker compose --env-file .env --profile full up -d
bash scripts/healthcheck.sh
```

**Mainnet-equivalent Tier 1**

```bash
docker compose --env-file examples/.env \
  -f examples/docker-compose-main.yml --profile dev up -d
VARS_ENV=examples/vars.mainnet-equivalent.env bash scripts/healthcheck.sh --el-only
```

**Mainnet-equivalent Tier 2**

```bash
bash examples/docker-setup-genesis.sh
docker compose --env-file examples/.env \
  -f examples/docker-compose-main.yml --profile full up -d
VARS_ENV=examples/vars.mainnet-equivalent.env bash scripts/healthcheck.sh
```

**Custom account balances (example)**

```bash
GENESIS_ACCOUNT_BALANCES_ETH="500000,250000,100000,50000" \
  bash scripts/render-genesis.sh
docker compose --env-file .env --profile dev up -d
```

**Verify**

```bash
bash scripts/healthcheck.sh --el-only --tx   # Tier 1
bash scripts/healthcheck.sh                  # Tier 2 (PoS)
bash scripts/send-tx-test.sh                 # optional tx smoke test
```

**Stop**

```bash
docker compose --profile dev --profile full down
docker compose -f examples/docker-compose-main.yml down
```

## Images

Compose reads image tags from `.env` via `--env-file`. Shell scripts (`docker-setup-genesis.sh`, `render-genesis.sh`) source them from `vars.env`:

- `RETH_IMAGE` (default `ghcr.io/paradigmxyz/reth:v2.3.0`)
- `LIGHTHOUSE_IMAGE` (default `sigp/lighthouse:v8.2.0`)
- `LCLI_IMAGE` (default `abelian-lcli:latest`)
- `FEE_RECIPIENT` — passed to validator `--suggested-fee-recipient` via compose

Full variable reference: see [`.env.example`](../.env.example).

Compose services include healthchecks; Tier 2 beacon/validator wait for EL/BN readiness.

## Troubleshooting

| Issue | Fix |
| --- | --- |
| `eth-account` import error | `pip install -r requirements.txt` |
| Image pull fails | Retry `docker compose pull` when network is stable |
| Port 1545 in use | `docker compose … down`, stop other stacks |
| Pre-funded balance wrong / stale | Tier 1: `down -v`, `render-genesis.sh`, then `up -d`; Tier 2: `FORCE=1 docker-setup-genesis.sh` |
| Missing `RETH_IMAGE` env var | Use `--env-file .env` or copy from `.env.example` |
| Missed CL genesis | `FORCE=1` re-run `docker-setup-genesis.sh`, start within `GENESIS_DELAY` seconds |
| `lcli` flag error | Pin `LIGHTHOUSE_IMAGE` to a compatible version |
