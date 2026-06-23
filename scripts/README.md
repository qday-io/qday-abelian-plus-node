# Scripts

Shell scripts for managing the Ethereum L1 devnet (Reth + optional Lighthouse PoS). All scripts use `set -euo pipefail` and source configuration from `vars.env` in the repo root.

## Configuration & Setup

### `source-vars.sh`

Shared variable definitions sourced by other scripts. Reads `vars.env` and exports defaults for RPC URL, Beacon URL, chain ID, pre-funded account, mnemonic, and genesis account settings.

```bash
# Sourced internally — not invoked directly
```

### `compose-env.sh`

Sources `vars.env` (or `VARS_ENV`) and exports variables for Docker Compose interpolation (image tags, ports, fee recipient). Sourced by `reset-dev.sh` and `docker-up.sh`.

```bash
# Sourced internally — not invoked directly
```

### `render-genesis.sh`

Regenerates the `alloc` section of `genesis.json` from the mnemonic and balance settings in `vars.env`. Preserves any non-mnemonic alloc entries already in the file. Requires `eth-account` Python package.

**Usage:**

```bash
bash scripts/render-genesis.sh                             # uses vars.env
VARS_ENV=examples/vars.custom.env bash scripts/render-genesis.sh
```

---

## DevOps & Cleanup

### `reset-dev.sh`

Stops Tier 1 containers, removes the dev volume, re-renders genesis, and restarts the dev profile. Used to wipe chain state and start fresh.

**Usage:**

```bash
bash scripts/reset-dev.sh
```

### `clean-data.sh`

Removes local runtime data directories and Docker volumes. Supports targeted cleanup by profile.

**Usage:**

```bash
bash scripts/clean-data.sh --dev          # Tier 1 volume + runtime data
bash scripts/clean-data.sh --full         # Tier 1 + Tier 2 runtime data
bash scripts/clean-data.sh --mainnet-eq   # mainnet-equivalent artifacts
bash scripts/clean-data.sh --all          # everything
```

---

## Verification & Testing

### `healthcheck.sh`

Runs PASS/FAIL health assertions against the Execution Layer (Reth) and optionally the Consensus Layer (Lighthouse). Checks RPC reachability, chain ID, sync status, block production, pre-funded balance, and gas price. When CL checks are enabled, validates beacon node health, slot advancement, sync status, finality, and active validators.

Exits with non-zero if any assertion fails.

**Usage:**

```bash
bash scripts/healthcheck.sh               # full stack (EL + CL)
bash scripts/healthcheck.sh --el-only     # execution layer only (Tier 1)
bash scripts/healthcheck.sh --tx          # also run a value-transfer test
bash scripts/healthcheck.sh --el-only --tx
```

### `check.sh`

A lightweight one-shot check: RPC reachability, chain ID match, and block number advancing. Exits non-zero on any failure. Faster than `healthcheck.sh` for quick sanity checks.

**Usage:**

```bash
bash scripts/check.sh
```

### `send-tx-test.sh`

Sends a 0.01 ETH value transfer from a pre-funded account and waits for receipt confirmation. Validates that the recipient balance increases by the expected amount. Requires `eth-account` Python package.

**Usage:**

```bash
bash scripts/send-tx-test.sh
# Custom transfer:
FROM_PK=0x... TO_ADDR=0x... VALUE_WEI=5000000000000000 bash scripts/send-tx-test.sh
```

---

## Shared Libraries

### `lib.sh`

Helper functions sourced by verification scripts:

| Function | Purpose |
|---|---|
| `rpc_call <method> [params]` | Send a JSON-RPC call via curl |
| `rpc_result <json>` | Extract `result` from a JSON-RPC response |
| `hex_to_int <hex>` | Convert hex string to decimal integer |
| `pass <msg>` | Record a passing assertion |
| `fail <msg>` | Record a failing assertion |
| `summary` | Print pass/fail summary and exit with appropriate code |

```bash
# Sourced internally — not invoked directly
```
