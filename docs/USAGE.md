# Usage & Deployment Guide

Docker-only guide for deploying, operating, verifying, and configuring the L1 devnet
(Reth ± Lighthouse + Validator).

- [1. Prerequisites](#1-prerequisites)
- [2. Deploy](#2-deploy)
  - [Tier 1 — EL auto-mining](#tier-1--el-auto-mining)
  - [Tier 2 — full PoS stack](#tier-2--full-pos-stack)
  - [Mainnet-equivalent](#mainnet-equivalent)
- [3. Pre-funded accounts](#3-pre-funded-accounts)
- [4. Verify the deployment](#4-verify-the-deployment)
- [5. Using the chain](#5-using-the-chain)
- [6. Configuration reference](#6-configuration-reference)
- [7. Customizing genesis](#7-customizing-genesis)
- [8. Operations](#8-operations)
- [9. Troubleshooting](#9-troubleshooting)

---

## 1. Prerequisites

| Tool | Why |
| --- | --- |
| Docker Engine + Compose v2 | runs Reth, Lighthouse, lcli in containers |
| `curl` | RPC checks from host |
| `python3` | JSON parsing in health scripts |
| `eth-account` | `pip install -r requirements.txt` — genesis rendering & tx smoke tests |
| `cast` (Foundry) | `curl -L https://foundry.paradigm.xyz \| bash && foundryup` — healthcheck EL assertions |


## Hardware: ~4 CPU / 8 GB RAM is comfortable for a single-node stack.

See also [`docs/DOCKER.md`](DOCKER.md).

---

## 2. Deploy

Copy env file before first use:

```bash
cp .env.example .env
```

Copy `.env.example` to `.env` before first use. Compose reads image tags and ports from `.env` via `--env-file`.

### Tier 1 — EL auto-mining

Single auto-mining execution node (`reth --dev`). No consensus layer. Best for contract /
rollup / bridge testing where you need a working EVM + RPC.

```bash
docker compose --env-file .env --profile dev up -d
bash scripts/healthcheck.sh --el-only --tx
```

No `docker-setup-genesis.sh` required.

### Tier 2 — full PoS stack

Real consensus driving the EL over the Engine API.

```bash
# 1. One-time ceremony: render genesis, reth init, jwt.hex, testnet/, validator keys
bash docker-setup-genesis.sh

# 2. Start Reth + Beacon + Validator
docker compose --env-file .env --profile full up -d
```

> ⏱️ Consensus genesis is scheduled at `now + GENESIS_DELAY` (default 30 s). Run
> `docker compose --env-file .env --profile full up -d` **promptly** after setup so
> all nodes are up before genesis fires.
> If you're too slow: `FORCE=1 bash docker-setup-genesis.sh`, then restart.

```bash
bash scripts/healthcheck.sh
```

### Mainnet-equivalent

```bash
# Tier 1
docker compose --env-file examples/.env \
  -f examples/docker-compose-main.yml --profile dev up -d

# Tier 2
bash examples/docker-setup-genesis.sh
docker compose --env-file examples/.env \
  -f examples/docker-compose-main.yml --profile full up -d
```

Details: [`docs/MAINNET_EQUIVALENT.md`](MAINNET_EQUIVALENT.md).

---

## 3. Pre-funded accounts

Configure in `vars.env` (dev) or `examples/vars.mainnet-equivalent.env`:

```bash
MNEMONIC="test test test test test test test test test test test junk"
GENESIS_ACCOUNT_COUNT=4
GENESIS_ACCOUNT_BALANCES_ETH="1000000,1000000,1000000,1000000"
```

| Variable | Default | Description |
| --- | --- | --- |
| `MNEMONIC` | Hardhat / Anvil test phrase | Derives addresses at `m/44'/60'/0'/0/N` |
| `GENESIS_ACCOUNT_COUNT` | `4` | Number of accounts to fund |
| `GENESIS_ACCOUNT_BALANCE_ETH` | `1000000` | Default ETH balance when list omitted |
| `GENESIS_ACCOUNT_BALANCES_ETH` | four × `1000000` | Per-account ETH balances (comma-separated) |

Rendering:

```bash
bash scripts/render-genesis.sh          # dev (uses vars.env)
bash scripts/render-genesis.sh --env examples/vars.mainnet-equivalent.env
```

**Tier 1:** render genesis manually before `compose up`. If
balances look stale, wipe the dev volume: `docker compose --profile dev down -v`.

**Tier 2:** rendered at the start of `docker-setup-genesis.sh`. After changes, run
`FORCE=1 bash docker-setup-genesis.sh`.

Default account #0 (also `FEE_RECIPIENT` and `PREFUNDED_ACCOUNT` in health checks):

- Address: `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`
- Private key (test only): `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`

Full list: [`docs/GENESIS.md`](GENESIS.md).

---

## 4. Verify the deployment

```bash
# Full stack (EL + CL):
bash scripts/healthcheck.sh

# Tier 1 / dev mode (skip consensus checks):
bash scripts/healthcheck.sh --el-only

# Include a value-transfer smoke test:
bash scripts/healthcheck.sh --el-only --tx
```

`healthcheck.sh` runs PASS/FAIL assertions and exits non-zero if any fail:

- **Execution layer:** RPC reachable, `chainId` matches config, node synced, block number
  advancing, pre-funded account has balance, `eth_gasPrice` responds.
- **Consensus layer (Tier 2):** beacon node reachable, not stuck syncing, head slot
  advancing, finalized epoch reported, at least one active validator.

Quick glance:

```bash
bash scripts/healthcheck.sh --el-only
```

Expected healthy output ends with:

```
== Summary ==
  N passed, 0 failed
  Deployment looks healthy.
```

---

## 5. Using the chain

**Endpoints**

| Endpoint | URL |
| --- | --- |
| JSON-RPC (HTTP) | `http://localhost:1545` |
| Engine API (auth, Tier 2) | `http://localhost:1551` |
| Beacon REST (Tier 2) | `http://localhost:1052` |

**Send a raw RPC call**

```bash
curl -s http://localhost:1545 -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

**Deploy a contract with Foundry**

```bash
export PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
forge create src/MyContract.sol:MyContract \
  --rpc-url http://localhost:1545 --private-key $PK --broadcast

cast send <ADDR> "set(uint256)" 42 --rpc-url http://localhost:1545 --private-key $PK
cast balance 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url http://localhost:1545
```

**Send a test transaction (built-in script)**

```bash
bash scripts/healthcheck.sh --tx
```

**MetaMask / wallet** — add a custom network: RPC `http://localhost:1545`, Chain ID `12345`
(dev) or `31337` (mainnet-equivalent), currency `ETH`.

---

## 6. Configuration reference

Scripts load vars via environment variables (defaults below).
Select mainnet-equivalent profile with `--env examples/vars.mainnet-equivalent.env`.

Full variable reference (all 22 fields with defaults and descriptions): [`.env.example`](../.env.example).

Override any value by exporting it before running a script:

```bash
CHAIN_ID=99999 GENESIS_ACCOUNT_BALANCES_ETH="100,100,100,100" bash scripts/render-genesis.sh
docker compose --env-file .env --profile dev up -d
```

| Variable | Default (dev) | Description |
| --- | --- | --- |
| **Docker images** | | |
| `RETH_IMAGE` | `ghcr.io/paradigmxyz/reth:v2.3.0` | Reth container image (pinned) |
| `LIGHTHOUSE_IMAGE` | `sigp/lighthouse:v8.2.0` | Lighthouse container image (pinned) |
| `LCLI_IMAGE` | `abelian-lcli:latest` | lcli image for CL genesis ceremony |
| **Network / chain** | | |
| `CHAIN_ID` | `12345` | EVM chain ID (rendered into genesis) |
| `VALIDATOR_COUNT` | `1` | Validators in CL genesis (Tier 2) |
| `SECONDS_PER_SLOT` | `12` | Beacon slot time |
| `GENESIS_DELAY` | `30` | Seconds between setup and CL genesis |
| `FEE_RECIPIENT` | account #0 | Block reward / fee recipient (wired into validator compose) |
| **Ports** | | |
| `RETH_HTTP_PORT` | `1545` | JSON-RPC HTTP port |
| `RETH_WS_PORT` | `1546` | WebSocket port |
| `AUTHRPC_PORT` | `1551` | Engine API port (EL↔CL) |
| `BN_HTTP_PORT` | `1052` | Beacon REST API port |
| **File paths** | | |
| `JWT_FILE` | `jwt.hex` | Shared EL↔CL auth secret (Tier 2) |
| `GENESIS_FILE` | `genesis.json` | Execution-layer genesis |
| `TESTNET_DIR` | `testnet/` | Generated consensus config (Tier 2) |
| `RETH_DATADIR` | `reth-data/` | Reth DB (Tier 2) |
| `BEACON_DATADIR` | `beacon-data/` | Lighthouse BN data |
| `VC_DATADIR` | `validator-data/` | Lighthouse VC data |
| **Genesis accounts** | | |
| `MNEMONIC` | Hardhat test mnemonic | Derives pre-funded accounts at `m/44'/60'/0'/0/N` |
| `GENESIS_ACCOUNT_COUNT` | `4` | Number of accounts to fund |
| `GENESIS_ACCOUNT_BALANCE_ETH` | `1000000` | Default ETH balance when per-account list omitted |
| `GENESIS_ACCOUNT_BALANCES_ETH` | four × `1000000` | Comma-separated per-account ETH balances |
| **Validator paths** | | |
| `LCLI_VALIDATORS_BASE` | `$ROOT_DIR` | Base dir containing `node_1/validators` and `node_1/secrets` |
| `VALIDATORS_DIR` | `node_1/validators` | Validator keystore directory |
| `SECRETS_DIR` | `node_1/secrets` | Validator secrets directory |

> `CHAIN_ID` is synced into `genesis.json` by `render-genesis.sh`. After changes,
> re-render and restart (Tier 1: `down -v`; Tier 2: `FORCE=1 docker-setup-genesis.sh`).

---

## 7. Customizing genesis

> **Field-by-field reference:** [`docs/GENESIS.md`](GENESIS.md)

**Pre-funded accounts** — edit `vars.env`, not `genesis.json`:

```bash
GENESIS_ACCOUNT_BALANCES_ETH="500000,250000,100000,50000"
bash scripts/render-genesis.sh
```

**Pre-deployed contracts** — add `code` (+ optional `storage`) to the genesis JSON
template; the renderer keeps entries whose addresses are not derived from `MNEMONIC`.

**Block gas limit** — edit `gasLimit` in the genesis template (default `0x1c9c380` = 30M).

**Fork activation** — timestamps like `cancunTime` are `0` (active from genesis) on dev;
mainnet-equivalent adds Prague — see `examples/genesis.mainnet-equivalent.json`.

After changes that affect the genesis block hash (Tier 2):

```bash
FORCE=1 bash docker-setup-genesis.sh
docker compose --env-file .env --profile full up -d
```

---

## 8. Operations

| Action | Command |
| --- | --- |
| Start Tier 1 | `docker compose --env-file .env --profile dev up -d` |
| Start Tier 2 | `docker compose --env-file .env --profile full up -d` (after setup) |
| Stop | `docker compose --profile dev --profile full down` |
| Verify health | `bash scripts/healthcheck.sh` |
| Render genesis only | `bash scripts/render-genesis.sh` |
| Reset Tier 1 state | `docker compose --env-file .env --profile dev down -v && docker compose --env-file .env --profile dev up -d` |
| Reset Tier 2 | `FORCE=1 bash docker-setup-genesis.sh` |

---

## 9. Troubleshooting

| Symptom | Likely cause / fix |
| --- | --- |
| `eth-account` import error | `pip install -r requirements.txt` |
| Pre-funded balance wrong | Tier 1: `down -v`, `render-genesis.sh`, then `up -d`; Tier 2: `FORCE=1 docker-setup-genesis.sh` |
| `healthcheck.sh`: RPC unreachable | Container not started — `docker compose ps`, check logs |
| Block number not advancing (Tier 2) | Beacon/validator not running, or missed genesis window — `FORCE=1 docker-setup-genesis.sh`, restart within 30s |
| Beacon rejects genesis hash | Genesis changed without regenerating CL — `FORCE=1 docker-setup-genesis.sh` |
| Missing `RETH_IMAGE` / `LIGHTHOUSE_IMAGE` | `docker compose` needs `--env-file .env` — copy from `.env.example` |
| Port already in use | `docker compose down`, or change ports in `.env` and `vars.env` |
| `lcli` flag error | Pin `LIGHTHOUSE_IMAGE` to a compatible version |

See also [`docs/DOCKER.md`](DOCKER.md) troubleshooting table.
