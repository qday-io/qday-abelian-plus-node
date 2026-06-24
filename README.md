# Docker-only L1

Private Ethereum L1 devnet running Reth + Lighthouse in **Docker Compose**.
No local binaries required.

## Quick Start

```bash
# 1. Install dependencies + copy env file
pip install -r requirements.txt
cp .env.example .env

# 2. Tier 1 — EL auto-mining (fastest)
docker compose --env-file .env --profile dev up -d
bash scripts/healthcheck.sh --el-only --tx

# 3. Tier 2 — full PoS (genesis ceremony + start)
bash docker-setup-genesis.sh
docker compose --env-file .env --profile full up -d
bash scripts/healthcheck.sh
```

Mainnet-equivalent: see [below](#mainnet-equivalent).

---

## Dependencies

| Tool | Version | Required | Purpose |
| --- | --- | --- | --- |
| Docker Engine | ≥ 24 | **Yes** | Run Reth + Lighthouse containers |
| Docker Compose | v2 | **Yes** | Service orchestration (profiles, healthchecks) |
| `python3` | ≥ 3.10 | **Yes** | Genesis rendering, tx tests, JSON parsing |
| `eth-account` | ≥ 0.10 | **Yes** | HD wallet derivation (genesis alloc) + tx signing |
| `curl` | any | Optional | RPC health checks from host |
| `openssl` | any | Optional | JWT generation (pre-installed on macOS) |

```bash
pip install -r requirements.txt    # eth-account
docker compose pull                # pre-fetch images (optional, first run)
```

---

## Configuration

### Pre-funded accounts

Set in `vars.env` (dev) or `examples/vars.mainnet-equivalent.env`:

```bash
MNEMONIC="test test test test test test test test test test test junk"
GENESIS_ACCOUNT_COUNT=4
GENESIS_ACCOUNT_BALANCES_ETH="1000000,1000000,1000000,1000000"
```

Addresses derived at `m/44'/60'/0'/0/N` (Hardhat / Anvil path). Rendered into
`genesis.json` → `alloc` by `scripts/render-genesis.sh`.

### Key variables

| Variable | Default | Description |
| --- | --- | --- |
| `CHAIN_ID` | `12345` (dev) / `31337` (mainnet-eq) | EVM chain ID |
| `VALIDATOR_COUNT` | `1` | PoS validators |
| `SECONDS_PER_SLOT` | `12` | Beacon slot time |
| `GENESIS_DELAY` | `30` | Seconds from ceremony to CL genesis |
| `FEE_RECIPIENT` | Hardhat account #0 | Block reward recipient |
| `RETH_IMAGE` | `ghcr.io/paradigmxyz/reth:v2.3.0` | Execution client image |
| `LIGHTHOUSE_IMAGE` | `sigp/lighthouse:v8.1.3` | Consensus client image |

Full reference: [`.env.example`](.env.example) (22 fields with defaults and descriptions).

---

## Deploy

Copy `.env.example` to `.env` before first use. Compose reads image tags and ports
from `.env` via `--env-file`.

### Tier 1 — EL auto-mining

Single Reth `--dev` node. No consensus layer. Best for contract / rollup development.

```bash
docker compose --env-file .env --profile dev up -d
```

No genesis ceremony required. After changing accounts:

```bash
docker compose --env-file .env --profile dev down -v
docker compose --env-file .env --profile dev up -d
```

### Tier 2 — full PoS

Reth + Lighthouse Beacon + Validator over the Engine API.

```bash
# One-time genesis ceremony (creates jwt.hex, testnet/, node_1/)
bash docker-setup-genesis.sh

# Start within GENESIS_DELAY seconds (default 30s)
docker compose --env-file .env --profile full up -d
```

The ceremony: render genesis alloc → JWT secret → `reth init` → probe genesis hash
→ lcli testnet → interop genesis → validator keystores. Details: top comment in
`docker-setup-genesis.sh`.

Regenerate from scratch: `FORCE=1 bash docker-setup-genesis.sh`

### Mainnet-equivalent

Chain ID `31337`, Prague EVM rules.

```bash
# Tier 1
docker compose --env-file examples/.env \
  -f examples/docker-compose-main.yml --profile dev up -d

# Tier 2
bash examples/docker-setup-genesis.sh
docker compose --env-file examples/.env \
  -f examples/docker-compose-main.yml --profile full up -d
```

See [`docs/MAINNET_EQUIVALENT.md`](docs/MAINNET_EQUIVALENT.md).

### Stop

```bash
docker compose --profile dev --profile full down
docker compose -f examples/docker-compose-main.yml --profile dev --profile full down

# Wipe runtime data
bash scripts/clean-data.sh --all
```

---

## Verify

```bash
bash scripts/check.sh                        # quick: RPC + block height

bash scripts/healthcheck.sh --el-only        # Tier 1: EL checks
bash scripts/healthcheck.sh --el-only --tx   # Tier 1: EL + tx smoke test
bash scripts/healthcheck.sh                  # Tier 2: EL + CL + validators

bash scripts/send-tx-test.sh                 # standalone 0.01 ETH transfer
```

Mainnet-equivalent:

```bash
VARS_ENV=examples/vars.mainnet-equivalent.env bash scripts/healthcheck.sh --el-only
```

---

## Endpoints

| Service | URL | Notes |
| --- | --- | --- |
| JSON-RPC | `http://localhost:1545` | Dev chainId **12345**, mainnet-eq **31337** |
| Engine API | `http://localhost:1551` | CL↔EL, JWT-authenticated (Tier 2) |
| Beacon REST | `http://localhost:1052` | Lighthouse API (Tier 2) |

---

## Project Layout

```
├── docker-compose.yml              # dev services (profiles: dev, full)
├── docker-setup-genesis.sh         # one-time dev PoS genesis ceremony
├── .env                            # dev compose env (copy from .env.example)
├── .env.example                    # compose env template with all variables
├── vars.env                        # dev: paths, chainId, mnemonic, accounts
├── genesis.json                    # dev EL genesis (alloc rendered)
├── requirements.txt                # Python deps (eth-account)
├── scripts/
│   ├── README.md                   # script catalog
│   ├── render-genesis.sh           # mnemonic → genesis.json alloc
│   ├── source-vars.sh              # export vars for host-side scripts
│   ├── lib.sh                      # shared RPC helpers
│   ├── check.sh                    # quick RPC + chainId + block check
│   ├── healthcheck.sh              # PASS/FAIL EL + CL assertions
│   ├── send-tx-test.sh             # value-transfer smoke test
│   ├── reset-dev.sh                # wipe Tier 1 volume + restart
│   └── clean-data.sh               # remove runtime data dirs
├── examples/
│   ├── README.md                   # examples overview
│   ├── .env                        # mainnet-eq compose env
│   ├── docker-setup-genesis.sh     # mainnet-eq PoS genesis ceremony
│   ├── docker-compose-main.yml     # mainnet-equivalent stack
│   ├── genesis.mainnet-equivalent.json
│   └── vars.mainnet-equivalent.env # mainnet-eq config
└── docs/
    ├── DOCKER.md                   # deployment guide
    ├── GENESIS.md                  # genesis field reference
    ├── SCRIPTS.md                  # shell scripts reference
    ├── MAINNET_EQUIVALENT.md       # mainnet-equivalent stack
    └── USAGE.md                    # operations + troubleshooting
```

---

## Docs

- [`docs/DOCKER.md`](docs/DOCKER.md) — deployment guide
- [`docs/GENESIS.md`](docs/GENESIS.md) — genesis field reference
- [`docs/SCRIPTS.md`](docs/SCRIPTS.md) — shell scripts reference
- [`docs/MAINNET_EQUIVALENT.md`](docs/MAINNET_EQUIVALENT.md) — mainnet-equivalent stack
- [`docs/USAGE.md`](docs/USAGE.md) — operations + troubleshooting
- [`.env.example`](.env.example) — all configuration variables
- [`scripts/README.md`](scripts/README.md) — script catalog
