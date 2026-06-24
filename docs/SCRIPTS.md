# Shell Scripts Reference

All scripts assume you run commands from the **repository root** unless noted otherwise.

> Quick catalog with usage examples: [`scripts/README.md`](../scripts/README.md)

Related config files:

| File | Role |
| --- | --- |
| `vars.env` | Dev stack defaults (chainId `12345`, paths, images, accounts) |
| `examples/vars.mainnet-equivalent.env` | Mainnet-equivalent profile (chainId `31337`) |
| `requirements.txt` | Python deps for `render-genesis.sh` and tx tests |

Select a profile for any script that reads env:

```bash
bash scripts/healthcheck.sh --env examples/vars.mainnet-equivalent.env --el-only
```

---

## Quick map

```
Tier 1 (EL only)                         Tier 2 (full PoS)
─────────────────                        ─────────────────
docker compose --env-file .env           docker-setup-genesis.sh   (one-time)
  --profile dev up -d                    docker compose --env-file .env
                                           --profile full up -d

After start ──────────────────────────── healthcheck
Config change (Tier 2) ───────────────── FORCE=1 docker-setup-genesis.sh
```

---

## Deployment

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
docker compose --env-file .env --profile full up -d
```

**Steps performed:**

0. Render genesis alloc from `vars.env` (via `render-genesis.sh`)
1. Generate `jwt.hex` (Engine API JWT secret, if missing)
2. `reth init` in a container — initialise datadir, extract execution genesis block hash
3. RPC fallback — start temp Reth node and query `eth_getBlockByNumber(0x0)` if step 2 failed to produce the hash
4. Build/use `abelian-lcli` image and run `lcli new-testnet` — CL testnet configuration
5. `lcli interop-genesis` — beacon chain interop genesis state
6. `lcli insecure-validators` — validator keystores under `$LCLI_VALIDATORS_BASE`

> Not needed for Tier 1 (`--profile dev`).

---

### `examples/docker-setup-genesis.sh`

**Role:** Same as `docker-setup-genesis.sh`, but for the **mainnet-equivalent** profile. Loads `examples/vars.mainnet-equivalent.env` and writes paths such as `jwt.mainnet-eq.hex`, `reth-data-mainnet-eq/`, `testnet-mainnet-eq/`, `l1-mainnet-eq/`.

**Usage:**

```bash
bash examples/docker-setup-genesis.sh
FORCE=1 bash examples/docker-setup-genesis.sh

docker compose --env-file examples/.env \
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
bash scripts/render-genesis.sh --env examples/vars.mainnet-equivalent.env

# Override balances for one run
GENESIS_ACCOUNT_BALANCES_ETH="500000,250000,100,0" bash scripts/render-genesis.sh
```

Usually called automatically by `docker-setup-genesis.sh`. Run manually when you only want to refresh `genesis.json` without starting containers.

---

## Verification (host-side)

These scripts load config from environment variables (defaults below).

### `scripts/healthcheck.sh`

**Role:** Structured PASS/FAIL checks for deployment health. EL checks use `cast` (Foundry), CL checks use `curl`.

| Mode | Checks |
| --- | --- |
| default | EL + Beacon + validators |
| `--el-only` | Execution layer only (Tier 1) |
| `--tx` | Also runs a value-transfer test via `cast send` |

**Usage:**

```bash
bash scripts/healthcheck.sh --el-only
bash scripts/healthcheck.sh --el-only --tx
bash scripts/healthcheck.sh              # Tier 2 full stack

bash scripts/healthcheck.sh --env examples/vars.mainnet-equivalent.env --el-only
```

Exits non-zero if any check fails.

---

## Typical workflows

### First time — Tier 1 (fastest)

```bash
pip install -r requirements.txt
cp .env.example .env
bash scripts/render-genesis.sh
docker compose --env-file .env --profile dev up -d
bash scripts/healthcheck.sh --el-only --tx
```

### First time — Tier 2 (PoS)

```bash
pip install -r requirements.txt
cp .env.example .env
bash docker-setup-genesis.sh
docker compose --env-file .env --profile full up -d    # within ~30s
bash scripts/healthcheck.sh
```

### Change pre-funded accounts (Tier 1)

```bash
# Edit vars.env (MNEMONIC / GENESIS_ACCOUNT_BALANCES_ETH)
docker compose --env-file .env --profile dev down -v
bash scripts/render-genesis.sh
docker compose --env-file .env --profile dev up -d
bash scripts/healthcheck.sh --el-only
```

### Change pre-funded accounts (Tier 2)

```bash
# Edit vars.env
FORCE=1 bash docker-setup-genesis.sh
docker compose --env-file .env --profile full up -d
bash scripts/healthcheck.sh
```

### Full teardown

```bash
docker compose -f examples/docker-compose-main.yml --profile dev --profile full down
```

---

## See also

- [`README.md`](../README.md) — quick start
- [`docs/DOCKER.md`](DOCKER.md) — deployment guide
- [`docs/USAGE.md`](USAGE.md) — operations & troubleshooting
- [`docs/GENESIS.md`](GENESIS.md) — genesis field reference
