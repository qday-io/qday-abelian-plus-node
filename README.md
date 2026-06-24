# Docker-only L1

Private Ethereum L1 devnet running Reth + Lighthouse in Docker Compose.
No local binaries required.

## Quick Start

### Tier 1 — EL auto-mining (Reth `--dev`)

```bash
# Required — first time only
cp examples/env.example examples/.env    # compose image tags

# Required — every start
docker compose --env-file examples/.env \
  -f examples/docker-compose-main.yml --profile dev up -d

# Optional — verify
bash scripts/healthcheck.sh --env examples/vars.mainnet-equivalent.env --el-only --tx
```

> Pre-funded accounts are hardcoded in `examples/genesis.mainnet-equivalent.json`.

### Tier 2 — full PoS

```bash
# Required — first time only
cp examples/env.example examples/.env

# Required — one-time genesis ceremony
bash examples/docker-setup-genesis.sh

# Required — start within GENESIS_DELAY (30s)
docker compose --env-file examples/.env \
  -f examples/docker-compose-main.yml --profile full up -d

# Optional — verify
bash scripts/healthcheck.sh --env examples/vars.mainnet-equivalent.env
```

> Reset PoS state: `FORCE=1 bash examples/docker-setup-genesis.sh`
> Details: [`examples/README.md`](examples/README.md)

---

## Dependencies

| Tool | Why |
| --- | --- |
| Docker Engine & Compose v2 | Run Reth + Lighthouse containers |
| `cast` (Foundry) | Healthcheck EL assertions & tx smoke test |

Install Foundry: `curl -L https://foundry.paradigm.xyz | bash && foundryup`

---

## Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `CHAIN_ID` | `31337` | EVM chain ID |
| `RETH_IMAGE` | `ghcr.io/paradigmxyz/reth:v2.3.0` | Execution client |
| `LIGHTHOUSE_IMAGE` | `sigp/lighthouse:v8.1.3` | Consensus client |

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
bash scripts/healthcheck.sh --env examples/vars.mainnet-equivalent.env --el-only        # Tier 1
bash scripts/healthcheck.sh --env examples/vars.mainnet-equivalent.env --el-only --tx   # Tier 1 + tx
bash scripts/healthcheck.sh --env examples/vars.mainnet-equivalent.env                  # Tier 2
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
│   ├── docker-compose-main.yml        # mainnet-equivalent stack
│   ├── docker-setup-genesis.sh        # PoS genesis ceremony
│   ├── vars.mainnet-equivalent.env    # chain config
│   ├── env.example                    # compose env template
│   ├── genesis.mainnet-equivalent.json # EL genesis (alloc + Prague fork)
│   └── README.md                      # scenario guide
├── scripts/
│   ├── healthcheck.sh                 # EL + CL assertions
│   ├── verify.sh                      # interactive chain verification
│   └── README.md                      # script catalog
├── docs/                              # detailed guides
├── docker/                            # Dockerfile.lcli
└── README.md
```

## Docs

- [`docs/DOCKER.md`](docs/DOCKER.md) — deployment guide
- [`docs/USAGE.md`](docs/USAGE.md) — operations & troubleshooting
- [`scripts/README.md`](scripts/README.md) — script catalog
- [`examples/README.md`](examples/README.md) — Tier 1 & Tier 2 scenarios
