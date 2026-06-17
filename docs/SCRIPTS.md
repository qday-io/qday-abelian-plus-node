# Shell Scripts Reference

All scripts assume you run commands from the **repository root** unless noted otherwise.

Related config files:

| File | Role |
| --- | --- |
| `vars.env` | Dev stack defaults (chainId `12345`, paths, images, accounts) |
| `examples/vars.mainnet-equivalent.env` | Mainnet-equivalent profile (chainId `31337`) |
| `requirements.txt` | Python deps for `render-genesis.sh` and tx tests |

Select a profile for any script that reads env:

```bash
VARS_ENV=examples/vars.mainnet-equivalent.env bash scripts/healthcheck.sh --el-only
```

---

## Quick map

```
Tier 1 (EL only)                         Tier 2 (full PoS)
─────────────────                        ─────────────────
docker-up.sh --profile dev up -d         docker-setup-genesis.sh   (one-time)
                                         docker-up.sh --profile full up -d

After start ──────────────────────────── check / healthcheck / send-tx-test
Config change (Tier 1) ───────────────── reset-dev.sh
Config change (Tier 2) ───────────────── FORCE=1 docker-setup-genesis.sh
Wipe runtime data ────────────────────── clean-data.sh
```

---

## Deployment

### `docker-up.sh`

**Role:** Render execution genesis from `vars.env`, export Compose variables, then run `docker compose` with the arguments you pass.

Always prefer this over bare `docker compose up` so `genesis.json` `alloc` stays in sync with `MNEMONIC` / balances.

**Usage:**

```bash
# Dev Tier 1
bash docker-up.sh --profile dev up -d

# Dev Tier 2 (after docker-setup-genesis.sh)
bash docker-up.sh --profile full up -d

# Mainnet-equivalent Tier 1
VARS_ENV=examples/vars.mainnet-equivalent.env bash docker-up.sh \
  -f examples/docker-compose-main.yml --profile dev up -d

# Any compose subcommand works (down, logs, ps, …)
bash docker-up.sh --profile dev down
bash docker-up.sh --profile full logs -f reth
```

**What it does internally:**

1. Sets `ROOT_DIR`
2. Sources `scripts/compose-env.sh` (image tags, `FEE_RECIPIENT`, ports)
3. Runs `scripts/render-genesis.sh`
4. `exec docker compose "$@"`

---

### `docker-setup-genesis.sh`

**Role:** One-time **Tier 2 (PoS)** genesis ceremony for the **dev** stack. Runs entirely in Docker — no local `reth` / `lighthouse` / `lcli` binaries.

**Writes on the host:**

| Artifact | Path (default) |
| --- | --- |
| JWT secret | `jwt.hex` |
| Reth datadir | `reth-data/` |
| CL testnet config | `testnet/` |
| Validator keys | `node_1/validators/`, `node_1/secrets/` |

**Usage:**

```bash
# First-time PoS setup
bash docker-setup-genesis.sh

# Wipe previous state and regenerate
FORCE=1 bash docker-setup-genesis.sh

# Then start within GENESIS_DELAY (default 30s)
bash docker-up.sh --profile full up -d
```

**Steps performed:**

1. Render genesis alloc (`render-genesis.sh`)
2. Generate `jwt.hex` (if missing)
3. `reth init` in a container
4. Read execution genesis block hash
5. Build/use `abelian-lcli` image and run `lcli new-testnet`, `interop-genesis`, `insecure-validators`

> Not needed for Tier 1 (`--profile dev`).

---

### `examples/docker-setup-genesis.sh`

**Role:** Same as `docker-setup-genesis.sh`, but for the **mainnet-equivalent** profile. Loads `examples/vars.mainnet-equivalent.env` and writes paths such as `jwt.mainnet-eq.hex`, `reth-data-mainnet-eq/`, `testnet-mainnet-eq/`, `l1-mainnet-eq/`.

**Usage:**

```bash
bash examples/docker-setup-genesis.sh
FORCE=1 bash examples/docker-setup-genesis.sh

VARS_ENV=examples/vars.mainnet-equivalent.env bash docker-up.sh \
  -f examples/docker-compose-main.yml --profile full up -d
```

---

## Genesis

### `scripts/render-genesis.sh`

**Role:** Derive pre-funded accounts from `MNEMONIC` and write them into the execution genesis file (`alloc`). Also syncs `config.chainId` from `CHAIN_ID`.

- Path: `m/44'/60'/0'/0/N` (Hardhat / Anvil HD path)
- Preserves non-mnemonic entries already in the genesis template (e.g. pre-deployed contracts)

**Requires:** `python3` + `eth-account` (`pip install -r requirements.txt`)

**Usage:**

```bash
# Dev (writes genesis.json)
bash scripts/render-genesis.sh

# Mainnet-equivalent
VARS_ENV=examples/vars.mainnet-equivalent.env bash scripts/render-genesis.sh

# Override balances for one run
GENESIS_ACCOUNT_BALANCES_ETH="500000,250000,100,0" bash scripts/render-genesis.sh
```

Usually called automatically by `docker-up.sh` and `docker-setup-genesis.sh`. Run manually when you only want to refresh `genesis.json` without starting containers.

---

## Verification (host-side)

These scripts load config via `scripts/source-vars.sh` and RPC helpers via `scripts/lib.sh`.

### `scripts/check.sh`

**Role:** Minimal smoke test — RPC reachable, correct `chainId`, block number advancing.

**Usage:**

```bash
bash scripts/check.sh

VARS_ENV=examples/vars.mainnet-equivalent.env bash scripts/check.sh
```

Exits non-zero on failure. No PASS/FAIL summary (use `healthcheck.sh` for that).

---

### `scripts/healthcheck.sh`

**Role:** Structured PASS/FAIL checks for deployment health.

| Mode | Checks |
| --- | --- |
| default | EL + Beacon + validators |
| `--el-only` | Execution layer only (Tier 1) |
| `--tx` | Also runs `send-tx-test.sh` |

**Usage:**

```bash
bash scripts/healthcheck.sh --el-only
bash scripts/healthcheck.sh --el-only --tx
bash scripts/healthcheck.sh              # Tier 2 full stack

VARS_ENV=examples/vars.mainnet-equivalent.env bash scripts/healthcheck.sh --el-only
```

Exits non-zero if any check fails.

---

### `scripts/send-tx-test.sh`

**Role:** Sign and send a **0.01 ETH** value transfer via JSON-RPC; confirm receipt and balance change.

**Requires:** `eth-account`  
**Defaults:** Hardhat account #0 → account #1

**Usage:**

```bash
bash scripts/send-tx-test.sh

# Custom transfer
FROM_PK=0x... TO_ADDR=0x... VALUE_WEI=10000000000000000 bash scripts/send-tx-test.sh
```

Also invoked by `healthcheck.sh --tx`.

---

## Maintenance

### `scripts/reset-dev.sh`

**Role:** Reset **Tier 1** state: stop dev profile, remove Docker volume, re-render genesis, restart.

Use after changing `MNEMONIC`, account balances, or `CHAIN_ID` on an existing Tier 1 node.

**Usage:**

```bash
bash scripts/reset-dev.sh

# Mainnet-equivalent Tier 1
VARS_ENV=examples/vars.mainnet-equivalent.env \
  COMPOSE_FILE=examples/docker-compose-main.yml \
  bash scripts/reset-dev.sh
```

Does not touch Tier 2 artifacts (`reth-data/`, `testnet/`, etc.). For Tier 2, use `FORCE=1 bash docker-setup-genesis.sh`.

---

### `scripts/clean-data.sh`

**Role:** Remove local runtime data directories. **Stop containers first** (script runs `docker compose down -v` where applicable).

**Usage:**

```bash
bash scripts/clean-data.sh --dev          # Tier 1 Docker volume only
bash scripts/clean-data.sh --full         # Dev Tier 2 host dirs + volumes
bash scripts/clean-data.sh --mainnet-eq   # Mainnet-equivalent artifacts
bash scripts/clean-data.sh --all          # Everything above
```

| Flag | Removes |
| --- | --- |
| `--dev` | `docker compose --profile dev down -v` |
| `--full` | `reth-data/`, `testnet/`, `jwt.hex`, `node_1/`, beacon/validator volumes |
| `--mainnet-eq` | `reth-data-mainnet-eq/`, `testnet-mainnet-eq/`, `jwt.mainnet-eq.hex`, `l1-mainnet-eq/`, … |

---

## Internal / library scripts

Not intended to be run directly. Sourced by other scripts.

### `scripts/compose-env.sh`

**Role:** Load `vars.env` (or `VARS_ENV`) and **export** Docker Compose interpolation variables.

| Exported var | Purpose |
| --- | --- |
| `RETH_IMAGE` | Reth container image (pinned in `vars.env`) |
| `LIGHTHOUSE_IMAGE` | Lighthouse container image |
| `FEE_RECIPIENT` | Validator `--suggested-fee-recipient` |
| `RETH_HTTP_PORT`, `BN_HTTP_PORT` | Host port mapping |

**Used by:** `docker-up.sh`, `scripts/reset-dev.sh`

---

### `scripts/source-vars.sh`

**Role:** Load `vars.env` (or `VARS_ENV`) and set **host-side verification** variables.

| Variable | Default | Purpose |
| --- | --- | --- |
| `RPC_URL` | `http://127.0.0.1:8545` | Reth JSON-RPC |
| `BEACON_URL` | `http://127.0.0.1:5052` | Lighthouse REST |
| `CHAIN_ID` | `12345` | Expected chain ID |
| `PREFUNDED_ACCOUNT` | Hardhat #0 | Balance check target |

**Used by:** `scripts/check.sh`, `scripts/healthcheck.sh`, `scripts/send-tx-test.sh`

---

### `scripts/lib.sh`

**Role:** Shared bash functions for verification scripts.

| Function | Purpose |
| --- | --- |
| `rpc_call` | JSON-RPC POST via `curl` |
| `rpc_result` | Parse `"result"` from JSON response |
| `hex_to_int` | Convert hex string to integer |
| `pass` / `fail` | Increment PASS/FAIL counters |
| `summary` | Print summary; exit 1 if any failure |

**Used by:** `scripts/check.sh`, `scripts/healthcheck.sh`, `scripts/send-tx-test.sh`

---

## Typical workflows

### First time — Tier 1 (fastest)

```bash
pip install -r requirements.txt
bash docker-up.sh --profile dev up -d
bash scripts/healthcheck.sh --el-only --tx
```

### First time — Tier 2 (PoS)

```bash
pip install -r requirements.txt
bash docker-setup-genesis.sh
bash docker-up.sh --profile full up -d    # within ~30s
bash scripts/healthcheck.sh
```

### Change pre-funded accounts (Tier 1)

```bash
# Edit vars.env (MNEMONIC / GENESIS_ACCOUNT_BALANCES_ETH)
bash scripts/reset-dev.sh
bash scripts/healthcheck.sh --el-only
```

### Change pre-funded accounts (Tier 2)

```bash
# Edit vars.env
FORCE=1 bash docker-setup-genesis.sh
bash docker-up.sh --profile full up -d
bash scripts/healthcheck.sh
```

### Full teardown

```bash
docker compose --profile dev --profile full down
bash scripts/clean-data.sh --all
```

---

## See also

- [`README.md`](../README.md) — quick start
- [`docs/DOCKER.md`](DOCKER.md) — deployment guide
- [`docs/USAGE.md`](USAGE.md) — operations & troubleshooting
- [`docs/GENESIS.md`](GENESIS.md) — genesis field reference
