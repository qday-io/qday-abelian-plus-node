# Docker-only L1

Run everything with **Docker Compose**. No local `reth` / `lighthouse` / `lcli` binaries.

Helper scripts:

| Script | When |
| --- | --- |
| `docker-up.sh` | Start nodes — renders genesis from `vars.env`, then runs compose |
| `docker-setup-genesis.sh` | One-time PoS genesis ceremony (Tier 2 only) |
| `scripts/reset-dev.sh` | Reset Tier 1 — wipe dev volume, re-render genesis, restart |
| `scripts/clean-data.sh` | Remove local runtime data dirs (after `docker compose down`) |

Full reference: [`docs/DOCKER.md`](docs/DOCKER.md)

## Prerequisites

- Docker Engine + Docker Compose v2
- `curl` (verify RPC from host)
- `python3` + dependencies for genesis rendering & tx tests:

```bash
pip install -r requirements.txt
```

```bash
docker compose pull    # optional, first run
```

## Pre-funded accounts

Configure in `vars.env` (or `examples/vars.mainnet-equivalent.env`):

```bash
MNEMONIC="test test test test test test test test test test test junk"
GENESIS_ACCOUNT_COUNT=4
GENESIS_ACCOUNT_BALANCES_ETH="1000000,1000000,1000000,1000000"
```

Addresses are derived via `m/44'/60'/0'/0/N` (Hardhat / Anvil path). Before every
`docker-up.sh` run, `scripts/render-genesis.sh` writes them into `genesis.json` → `alloc`.

See [`docs/GENESIS.md`](docs/GENESIS.md) for field reference.

## Commands

### Dev — Tier 1 (EL auto-mining)

```bash
bash docker-up.sh --profile dev up -d
```

No `docker-setup-genesis.sh` required. After changing balances or mnemonic, reset Tier 1:

```bash
bash scripts/reset-dev.sh
```

Or manually:

```bash
docker compose --profile dev down -v
bash docker-up.sh --profile dev up -d
```

### Dev — Tier 2 (full PoS)

```bash
bash docker-setup-genesis.sh   # includes render-genesis + reth init + lcli
bash docker-up.sh --profile full up -d
```

Start within **30s** after genesis setup (`GENESIS_DELAY`).

### Mainnet-equivalent

```bash
# Tier 1 — EL auto-mining
VARS_ENV=examples/vars.mainnet-equivalent.env bash docker-up.sh \
  -f examples/docker-compose-main.yml --profile dev up -d

# Tier 2 — full PoS
bash examples/docker-setup-genesis.sh
VARS_ENV=examples/vars.mainnet-equivalent.env bash docker-up.sh \
  -f examples/docker-compose-main.yml --profile full up -d
```

Reset genesis: `FORCE=1 bash examples/docker-setup-genesis.sh`

### Stop

```bash
docker compose --profile dev --profile full down
docker compose -f examples/docker-compose-main.yml --profile dev --profile full down
```

> Use `bash docker-up.sh …` instead of bare `docker compose up` so genesis `alloc` stays
> in sync with `vars.env`. To render only: `bash scripts/render-genesis.sh`.

## Verify

After `up -d`, from repo root:

```bash
# Quick: RPC + block height
bash scripts/check.sh

# Tier 1 — full EL checks (+ optional tx test)
bash scripts/healthcheck.sh --el-only
bash scripts/healthcheck.sh --el-only --tx

# Tier 2 — EL + beacon + validators
bash scripts/healthcheck.sh

# Send 0.01 ETH (needs: pip install eth-account)
bash scripts/send-tx-test.sh
```

Mainnet-equivalent (`chainId` 31337):

```bash
VARS_ENV=examples/vars.mainnet-equivalent.env bash scripts/healthcheck.sh --el-only
```

## Endpoints

| Service | URL |
| --- | --- |
| JSON-RPC | `http://localhost:8545` |
| Beacon REST (PoS) | `http://localhost:5052` |

Dev `chainId` **12345**; mainnet-equivalent **31337**.

## Layout

```
docker-compose.yml                # dev services (profiles: dev, full)
docker-up.sh                      # render genesis + docker compose
docker-setup-genesis.sh           # one-time dev PoS genesis
vars.env                          # dev paths, chainId, mnemonic, balances
genesis.json                      # dev EL genesis (alloc rendered from vars.env)
scripts/
├── render-genesis.sh             # MNEMONIC → genesis.json alloc
├── compose-env.sh                # export image tags / FEE_RECIPIENT for compose
├── reset-dev.sh                  # wipe Tier 1 volume + restart
├── clean-data.sh                 # remove local runtime data dirs
├── check.sh                      # quick RPC / block check
├── healthcheck.sh                # PASS/FAIL deployment checks
└── send-tx-test.sh               # value-transfer smoke test
requirements.txt                  # python deps (eth-account)
.env.example                      # compose env reference (optional)
examples/
├── docker-setup-genesis.sh       # one-time mainnet-equivalent PoS genesis
├── docker-compose-main.yml       # mainnet-equivalent stack
├── genesis.mainnet-equivalent.json
├── vars.mainnet-equivalent.env   # mainnet paths / chainId / accounts
└── README.md
```

## Docs

- [`docs/SCRIPTS.md`](docs/SCRIPTS.md) — shell scripts reference (purpose & usage)
- [`docs/DOCKER.md`](docs/DOCKER.md) — deployment guide
- [`docs/GENESIS.md`](docs/GENESIS.md) — genesis field reference & account config
- [`docs/MAINNET_EQUIVALENT.md`](docs/MAINNET_EQUIVALENT.md) — mainnet-equivalent stack
- [`docs/USAGE.md`](docs/USAGE.md) — operations & troubleshooting
