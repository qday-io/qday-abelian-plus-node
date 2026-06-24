# Scripts

Shell scripts for managing the Ethereum L1 devnet (Reth + optional Lighthouse PoS).

## Verification & Testing

### `healthcheck.sh`

Runs PASS/FAIL health assertions against the Execution Layer (Reth) and optionally the Consensus Layer (Lighthouse). EL checks use `cast` (Foundry), CL checks use `curl`. Checks RPC reachability, chain ID, sync status, block production, pre-funded balance, and gas price. When CL checks are enabled, validates beacon node health, slot advancement, sync status, finality, and active validators.

Exits with non-zero if any assertion fails.

**Usage:**

```bash
bash scripts/healthcheck.sh                                                    # full stack (EL + CL)
bash scripts/healthcheck.sh --el-only                                          # execution layer only (Tier 1)
bash scripts/healthcheck.sh --tx                                               # value-transfer test via cast send
bash scripts/healthcheck.sh --env examples/vars.mainnet-equivalent.env --el-only --tx
```

---

### `verify.sh`

Interactive menu for chain verification and interaction. Supports chain info, account queries, contract calls, transactions, and network health checks.

**Usage:**

```bash
bash scripts/verify.sh --rpc http://localhost:1545
bash scripts/verify.sh --rpc http://localhost:1545 --verbose
```
