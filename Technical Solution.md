# Technical Solution

Private Ethereum L1 devnet — architecture and design decisions.

> **Deployment:** Docker Compose only. No local `reth` / `lighthouse` / `lcli` binaries
> required. See [`README.md`](README.md) for quick start.

---

## 1. Overview

This project provides a **minimal Ethereum L1 devnet** suitable for rollup / bridge /
smart contract development. It runs a full or partial Ethereum stack in Docker
containers with reproducible, idempotent genesis.

### Use cases

- Rollup / CDK development (Polygon CDK, OP Stack)
- Smart contract deployment and testing
- Cross-chain bridge testing
- Local L1 simulation with custom chain parameters

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Docker Compose                     │
│                                                      │
│  ┌──────────┐  Engine API (1551)  ┌──────────────┐  │
│  │          │◄───────────────────►│              │
│  │   Reth   │      jwt.hex       │  Lighthouse  │
│  │   (EL)   │                     │  Beacon (CL) │
│  │          │                     │              │
│  └────┬─────┘                     └──────┬───────┘
│       │ RPC (1545)                      │ REST      │
│       │ WS (1546)                       │ (1052)    │
│       ▼                                  ▼           │
│  ┌──────────┐                     ┌──────────────┐  │
│  │  Host /  │                     │  Validator   │  │
│  │  Wallet  │                     │  (lighthouse │  │
│  │          │                     │   vc)        │  │
│  └──────────┘                     └──────────────┘  │
│                                                      │
└─────────────────────────────────────────────────────┘
```

### Two-tier deployment

| Tier | Profile | Stack | Use case |
| --- | --- | --- | --- |
| 1 | `dev` | Reth `--dev` auto-mining | Fast EVM development, no PoS |
| 2 | `full` | Reth + Lighthouse BN + Validator | Real PoS consensus |

Tier 1 is a single `docker compose --profile dev up -d`. Tier 2 requires a one-time
genesis ceremony (`docker-setup-genesis.sh`) before starting the full stack.

---

## 3. Design Decisions

### Docker-only runtime

No local binaries. Everything — `reth`, `lighthouse`, `lcli` — runs in containers.
This eliminates toolchain installation (Rust, Cargo, build from source) and guarantees
reproducible environments.

### Genesis rendered, not hand-edited

Pre-funded accounts are configured in `vars.env` (mnemonic + balances) and rendered
into `genesis.json` by `scripts/render-genesis.sh` before every start. This avoids
drift between config files and runtime state — account 0's private key is always
derivable from the mnemonic.

### `--env-file` for compose variables

Docker Compose reads image tags and other interpolation variables from `.env` files
via `docker compose --env-file .env`. Copy `.env.example` to `.env` to get started.
Shell scripts (`docker-setup-genesis.sh`, `render-genesis.sh`) source `vars.env`
for configuration that cannot be expressed as Compose interpolation.

### Profile-based compose

A single `docker-compose.yml` serves both Tier 1 (`--profile dev`) and Tier 2
(`--profile full`). Services declare their profile membership; healthchecks enforce
startup ordering (beacon waits for Reth, validator waits for beacon).

### Pinned images

`RETH_IMAGE`, `LIGHTHOUSE_IMAGE`, `LCLI_IMAGE` are pinned in `vars.env` for
reproducibility. Bump intentionally when upgrading.

---

## 4. Genesis Ceremony (Tier 2)

The PoS genesis ceremony runs entirely in Docker containers. Steps:

```
0. Render genesis alloc     scripts/render-genesis.sh
   ↓
1. Generate JWT secret      openssl rand -hex 32 → jwt.hex
   ↓
2. reth init                docker run reth init → genesis block hash
   ↓                          (RPC fallback if hash extraction fails)
3. Probe genesis hash       temp Reth node → eth_getBlockByNumber(0x0)
   ↓
4. lcli new-testnet         Lighthouse CL testnet config (fork epochs, TTD=0)
   ↓                          Links CL genesis to EL genesis block hash
5. lcli interop-genesis     Beacon chain interop genesis state
   ↓
6. lcli insecure-validators Validator keystores → node_1/validators + secrets/
```

The EL genesis block hash is embedded into the CL genesis. If EL genesis changes
(e.g. account balances), the CL must be regenerated (`FORCE=1 docker-setup-genesis.sh`).

---

## 5. Configuration Model

### Docker Compose

```
.env.example ──► copy to .env ──► docker compose --env-file .env up -d
                    │
                    └── RETH_IMAGE, LIGHTHOUSE_IMAGE, FEE_RECIPIENT, ports, ...
```

Simple `KEY=VALUE` file. Ports and block time have defaults in the YAML.

### Shell scripts

```
vars.env
  │
  ├─ source-vars.sh ────► export RPC_URL, BEACON_URL, CHAIN_ID, ...
  │                        (used by healthcheck, check, send-tx-test)
  │
  └─ render-genesis.sh ─► MNEMONIC → HD derivation → genesis.json alloc
                           (preserves non-mnemonic entries)
```

Override: export any variable before calling a script.  
Select mainnet-eq profile: `VARS_ENV=examples/vars.mainnet-equivalent.env`.

---

## 6. Components

| Component | Container Image | Role |
| --- | --- | --- |
| Reth | `ghcr.io/paradigmxyz/reth:v2.3.0` | Execution layer: EVM, JSON-RPC, Engine API |
| Lighthouse BN | `sigp/lighthouse:v8.2.0` | Consensus layer: slot production, fork choice |
| Lighthouse VC | `sigp/lighthouse:v8.2.0` | Validator: attestations, block proposals |
| lcli | `abelian-lcli:latest` (built from `docker/Dockerfile.lcli`) | Lighthouse tooling: testnet genesis, validator key generation |

### Helper scripts

| Script | Type | Purpose |
| --- | --- | --- |
| `docker-setup-genesis.sh` | One-shot | Tier 2 genesis ceremony |
| `scripts/render-genesis.sh` | Genesis | MNEMONIC → genesis.json alloc |
| `scripts/healthcheck.sh` | Verify | PASS/FAIL EL + CL assertions |
| `scripts/check.sh` | Verify | Quick RPC + chainId + block check |
| `scripts/send-tx-test.sh` | Verify | 0.01 ETH value transfer smoke test |
| `scripts/reset-dev.sh` | Maintenance | Wipe Tier 1 volume + restart |
| `scripts/clean-data.sh` | Maintenance | Remove runtime data dirs |

---

## 7. Profiles

### Dev profile (`vars.env`, chainId 12345)

Default for local development. Familiar Hardhat/Anvil test mnemonic and account #0.

| Tier | Command | Genesis |
| --- | --- | --- |
| 1 | `docker compose --env-file .env --profile dev up -d` | `render-genesis.sh` |
| 2 | `bash docker-setup-genesis.sh` + `docker compose --env-file .env --profile full up -d` | Full ceremony |

### Mainnet-equivalent profile (`examples/vars.mainnet-equivalent.env`, chainId 31337)

Includes Prague fork, `blobSchedule`, separate data directories to avoid collision
with dev stack.

| Tier | Command |
| --- | --- |
| 1 | `docker compose --env-file examples/.env -f examples/docker-compose-main.yml --profile dev up -d` |
| 2 | `bash examples/docker-setup-genesis.sh` + same as Tier 1 but `--profile full` |

---

## 8. Fork Activation (dev genesis)

All historical Ethereum forks are active from genesis (`0` block / `0` timestamp):

| Fork | Activation |
| --- | --- |
| Homestead → Constantinople | `*Block: 0` |
| Petersburg, Istanbul, Berlin, London | `*Block: 0` |
| Paris (The Merge) | `mergeNetsplitBlock: 0`, `terminalTotalDifficulty: 0` |
| Shanghai (withdrawals) | `shanghaiTime: 0` |
| Cancun (blobs) | `cancunTime: 0` |

The chain starts **post-Merge** — no PoW mining phase. All EVM features through Cancun
are available from block 0.

Mainnet-equivalent adds `pragueTime` and `blobSchedule`. See
[`docs/GENESIS.md`](docs/GENESIS.md) for full field reference.

---

## 9. Endpoints

| Service | URL | Auth |
| --- | --- | --- |
| JSON-RPC (HTTP) | `http://localhost:1545` | None |
| JSON-RPC (WebSocket) | `ws://localhost:1546` | None |
| Engine API | `http://localhost:1551` | JWT (jwt.hex) |
| Beacon REST | `http://localhost:1052` | None |

Dev chainId **12345**, mainnet-equivalent **31337**.

---

## 10. File Layout

```
├── docker-compose.yml              # dev services (profiles: dev, full)
├── docker-setup-genesis.sh         # Tier 2 genesis ceremony
├── vars.env                        # dev config
├── genesis.json                    # dev EL genesis (alloc rendered)
├── requirements.txt                # Python deps
├── .env.example                    # all 22 variables
├── scripts/                        # helper scripts
├── examples/                       # mainnet-equivalent profile
│   ├── docker-setup-genesis.sh
│   ├── docker-compose-main.yml
│   ├── genesis.mainnet-equivalent.json
│   └── vars.mainnet-equivalent.env
├── docker/                         # Dockerfiles
│   └── Dockerfile.lcli
├── docs/                           # detailed documentation
│   ├── DOCKER.md
│   ├── GENESIS.md
│   ├── SCRIPTS.md
│   ├── MAINNET_EQUIVALENT.md
│   └── USAGE.md
└── Technical Solution.md           # this document
```

---

## See also

- [`README.md`](README.md) — quick start
- [`docs/DOCKER.md`](docs/DOCKER.md) — deployment guide
- [`docs/GENESIS.md`](docs/GENESIS.md) — genesis field reference
- [`docs/SCRIPTS.md`](docs/SCRIPTS.md) — script reference
- [`.env.example`](.env.example) — configuration variables
