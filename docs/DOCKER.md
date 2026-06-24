# Docker Deployment

**Docker Compose only** — no local `reth`, `lighthouse`, or `lcli` required.

## What you need

| Item | Required? |
| --- | --- |
| `docker-compose.yml` | **Yes** — runs all services |
| `docker-up.sh` | **Yes** — renders genesis from `vars.env`, then starts compose |
| `docker-setup-genesis.sh` | **Yes** for PoS — one-time genesis ceremony in containers |
| `vars.env` / `examples/vars.mainnet-equivalent.env` | **Yes** — paths, chainId, mnemonic, account balances |
| `.env.example` | Optional — full variable reference with defaults and descriptions |
| `scripts/README.md` | Optional — script catalog with usage examples |
| `scripts/render-genesis.sh` | Called by `docker-up.sh` and `docker-setup-genesis.sh` |
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

**Tier 1:** `docker-up.sh` renders genesis, then Reth `--dev` mounts `genesis.json`.

**Tier 2:** `docker-setup-genesis.sh` renders genesis first, then `reth init` and `lcli`.

After changing mnemonic or balances on an **existing** Tier 1 node, wipe the dev volume:

```bash
docker compose --profile dev down -v
bash docker-up.sh --profile dev up -d
```

Tier 2 requires `FORCE=1 bash docker-setup-genesis.sh` to re-bind the consensus layer.

## Profiles

| Profile | Stack | Genesis ceremony | Start |
| --- | --- | --- | --- |
| `dev` | Dev Reth `--dev` (Tier 1) | render only (`docker-up.sh`) | `bash docker-up.sh --profile dev up -d` |
| `full` | Dev PoS (Tier 2) | `bash docker-setup-genesis.sh` | `bash docker-up.sh --profile full up -d` |
| `dev` (mainnet) | Mainnet-eq Reth `--dev` | render via `VARS_ENV=… docker-up.sh` | see below |
| `full` (mainnet) | Mainnet-equivalent PoS | `bash examples/docker-setup-genesis.sh` | see below |

## Examples

**Dev Tier 1**

```bash
bash docker-up.sh --profile dev up -d
bash scripts/healthcheck.sh --el-only --tx
```

**Dev Tier 2**

```bash
bash docker-setup-genesis.sh
bash docker-up.sh --profile full up -d
bash scripts/healthcheck.sh
```

**Mainnet-equivalent Tier 1**

```bash
VARS_ENV=examples/vars.mainnet-equivalent.env bash docker-up.sh \
  -f examples/docker-compose-main.yml --profile dev up -d
VARS_ENV=examples/vars.mainnet-equivalent.env bash scripts/healthcheck.sh --el-only
```

**Mainnet-equivalent Tier 2**

```bash
bash examples/docker-setup-genesis.sh
VARS_ENV=examples/vars.mainnet-equivalent.env bash docker-up.sh \
  -f examples/docker-compose-main.yml --profile full up -d
VARS_ENV=examples/vars.mainnet-equivalent.env bash scripts/healthcheck.sh
```

**Custom account balances (example)**

```bash
GENESIS_ACCOUNT_BALANCES_ETH="500000,250000,100000,50000" \
  bash docker-up.sh --profile dev up -d
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

## Why two helper scripts

| Script | Role |
| --- | --- |
| `docker-up.sh` | (1) Source compose env vars → (2) render genesis alloc → (3) `docker compose`. Keeps `genesis.json` in sync with `vars.env` on every start. |
| `docker-setup-genesis.sh` | One-shot PoS ceremony in 7 steps: (0) render genesis alloc → (1) generate JWT secret → (2) `reth init` + extract genesis block hash → (3) RPC fallback to probe genesis hash → (4) `lcli new-testnet` — CL testnet config → (5) `lcli interop-genesis` — beacon genesis state → (6) `lcli insecure-validators` — validator keystores. Writes `jwt.hex`, `testnet/`, `reth-data/` on the host for volume mounts. |

Compose alone cannot express the Tier 2 ceremony; Tier 1 still needs genesis rendering
before the Reth container mounts `genesis.json`.

Full variable reference: see [`.env.example`](../.env.example). Script catalog: see [`scripts/README.md`](../scripts/README.md).

## Images

Pinned in `vars.env` for reproducibility (override by exporting before scripts):

- `RETH_IMAGE` (default `ghcr.io/paradigmxyz/reth:v2.3.0`)
- `LIGHTHOUSE_IMAGE` (default `sigp/lighthouse:v8.1.3`)
- `LCLI_IMAGE` (default `abelian-lcli:latest`)
- `FEE_RECIPIENT` — passed to validator `--suggested-fee-recipient` via compose

`docker-up.sh` exports these (and ports, paths, network params) from `vars.env` via
`compose-env.sh` before `docker compose`. Full variable reference: see [`.env.example`](../.env.example).

Compose services include healthchecks; Tier 2 beacon/validator wait for EL/BN readiness.

## Troubleshooting

| Issue | Fix |
| --- | --- |
| `eth-account` import error | `pip install -r requirements.txt` |
| Image pull fails | Retry `docker compose pull` when network is stable |
| Port 1545 in use | `docker compose … down`, stop other stacks |
| Pre-funded balance wrong / stale | Tier 1: `down -v` then `docker-up.sh`; Tier 2: `FORCE=1 docker-setup-genesis.sh` |
| Used `docker compose up` directly | Run `bash scripts/render-genesis.sh` first, or use `docker-up.sh` |
| Missed CL genesis | `FORCE=1` re-run `docker-setup-genesis.sh`, then `docker-up.sh` within 30s |
| `lcli` flag error | Pin `LIGHTHOUSE_IMAGE` to a compatible version |
