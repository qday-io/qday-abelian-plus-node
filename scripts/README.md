# Scripts

Shell scripts for managing the Ethereum L1 devnet (Reth + optional Lighthouse PoS). All scripts use `set -euo pipefail`.

## Configuration & Setup

### `render-genesis.sh`

Regenerates the `alloc` section of `genesis.json` from the mnemonic and balance settings in `vars.env`. Preserves any non-mnemonic alloc entries already in the file. Requires `eth-account` Python package.

**Usage:**

```bash
bash scripts/render-genesis.sh                                       # defaults
bash scripts/render-genesis.sh --env examples/vars.mainnet-equivalent.env
```

---

## Verification & Testing

### `healthcheck.sh`

Runs PASS/FAIL health assertions against the Execution Layer (Reth) and optionally the Consensus Layer (Lighthouse). EL checks use `cast` (Foundry), CL checks use `curl`. Checks RPC reachability, chain ID, sync status, block production, pre-funded balance, and gas price. When CL checks are enabled, validates beacon node health, slot advancement, sync status, finality, and active validators.

Exits with non-zero if any assertion fails.

**Usage:**

```bash
bash scripts/healthcheck.sh                                                    # full stack (EL + CL)
bash scripts/healthcheck.sh --el-only                                          # execution layer only (Tier 1)
bash scripts/healthcheck.sh --tx                                               # also run a value-transfer test via cast send
bash scripts/healthcheck.sh --env examples/vars.mainnet-equivalent.env --el-only --tx
```
