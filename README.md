# Docker-only L1

Private Ethereum L1 devnet running Reth + Lighthouse in Docker Compose.
No local binaries required.

## Quick Start

### Tier 1 — EL auto-mining (Reth `--dev`)

```bash
# Required — first time only
cp examples/env.example examples/.env    # compose image tags
pip install -r requirements.txt          # eth-account (for render-genesis)
bash scripts/render-genesis.sh            # populate pre-funded accounts in genesis.json

# Required — every start
docker compose --env-file examples/.env \
  -f examples/docker-compose-main.yml --profile dev up -d

# Optional — verify
bash scripts/healthcheck.sh --el-only --tx
```

> Rerun `render-genesis.sh` only when changing mnemonic or account balances.
> `pip install` is one-time unless `requirements.txt` changes.

### Tier 2 — full PoS

```bash
# Required — first time only
cp examples/env.example examples/.env
pip install -r requirements.txt

# Required — one-time genesis ceremony
bash examples/docker-setup-genesis.sh

# Required — start within GENESIS_DELAY (30s)
docker compose --env-file examples/.env \
  -f examples/docker-compose-main.yml --profile full up -d

# Optional — verify
bash scripts/healthcheck.sh
```

> Reset PoS state: `FORCE=1 bash examples/docker-setup-genesis.sh`
> Details: [`examples/README.md`](examples/README.md)

---

## Dependencies

| Tool | Why |
| --- | --- |
| Docker Engine & Compose v2 | Run Reth + Lighthouse containers |
| `python3` ≥ 3.10 | `pip install -r requirements.txt` — genesis rendering, tx signing |
| `cast` (Foundry) | Healthcheck EL assertions & tx smoke test |

Install Foundry: `curl -L https://foundry.paradigm.xyz | bash && foundryup`

---

## Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `CHAIN_ID` | `31337` | EVM chain ID |
| `GENESIS_ACCOUNT_COUNT` | `4` | Pre-funded HD accounts |
| `GENESIS_ACCOUNT_BALANCES_ETH` | `1000000` | Balance per account (ETH) |
| `MNEMONIC` | Hardhat test phrase | Derives at `m/44'/60'/0'/0/N` |
| `RETH_IMAGE` | `ghcr.io/paradigmxyz/reth:v2.3.0` | Execution client |
| `LIGHTHOUSE_IMAGE` | `sigp/lighthouse:v8.2.0` | Consensus client |

See [`examples/vars.mainnet-equivalent.env`](examples/vars.mainnet-equivalent.env) for full config.

---

## Endpoints

| Service | URL |
| --- | --- |
| JSON-RPC | `http://localhost:1545` |
| Engine API | `http://localhost:1551` (Tier 2) |
| Beacon REST | `http://localhost:1052` (Tier 2) |

---

## Verify

```bash
bash scripts/healthcheck.sh --el-only        # Tier 1: EL assertions
bash scripts/healthcheck.sh --el-only --tx   # Tier 1: EL + tx smoke test
bash scripts/healthcheck.sh                  # Tier 2: EL + CL + validators
```

---

## Operate

```bash
docker compose -f examples/docker-compose-main.yml --profile dev --profile full down
FORCE=1 bash examples/docker-setup-genesis.sh   # reset Tier 2 state
```

---

## Project Layout

```
├── examples/
│   ├── docker-compose-main.yml     # mainnet-equivalent stack
│   ├── docker-setup-genesis.sh     # PoS genesis ceremony
│   ├── vars.mainnet-equivalent.env # chain config
│   ├── env.example                 # compose env template
│   └── README.md                   # scenario guide
├── scripts/
│   ├── render-genesis.sh           # mnemonic → genesis.json
│   ├── healthcheck.sh              # EL + CL assertions
│   └── README.md                   # script catalog
├── docs/                           # detailed guides
├── docker/                         # Dockerfile.lcli
├── requirements.txt                # Python deps
└── README.md
```

## Docs

- [`docs/DOCKER.md`](docs/DOCKER.md) — deployment guide
- [`docs/USAGE.md`](docs/USAGE.md) — operations & troubleshooting
- [`scripts/README.md`](scripts/README.md) — script catalog
- [`examples/README.md`](examples/README.md) — Tier 1 & Tier 2 scenarios
