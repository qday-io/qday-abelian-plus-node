# Mainnet-Equivalent (Docker)

Chain ID `31337`, Prague EVM rules.

---

## Scenario 1: Tier 1 — EL auto-mining

Single Reth `--dev` node. No consensus layer, no genesis ceremony.
Best for contract / rollup development.

### Steps

**1. Setup (first time only)**

```bash
cp examples/env.example examples/.env    # compose image tags
pip install -r requirements.txt          # eth-account (for render-genesis)
bash scripts/render-genesis.sh            # populate pre-funded accounts in genesis.json
```

> Rerun `render-genesis.sh` only when changing mnemonic or account balances.

**2. Start the EL node (every start)**

```bash
docker compose --env-file examples/.env \
  -f examples/docker-compose-main.yml --profile dev up -d
```

Launches Reth with `--dev` auto-mining mode, exposing JSON-RPC on `:1545`.

**3. Verify (optional)**

```bash
bash scripts/healthcheck.sh --env examples/vars.mainnet-equivalent.env --el-only --tx
```

Checks RPC reachability, chain ID, block production, pre-funded balance, and runs a value-transfer smoke test.

---

## Scenario 2: Tier 2 — full PoS

Reth + Lighthouse Beacon + Validator over the Engine API.

### Steps

**1. Setup (first time only)**

```bash
cp examples/env.example examples/.env
pip install -r requirements.txt
```

**2. Genesis ceremony (one-time)**

```bash
bash examples/docker-setup-genesis.sh
```

6 sub-steps in one command:
- Render genesis `alloc` from mnemonic
- Generate JWT secret (`jwt.mainnet-eq.hex`)
- `reth init` the datadir, extract genesis block hash
- `lcli new-testnet` — create Lighthouse testnet config
- `lcli interop-genesis` — beacon chain interop genesis state
- `lcli insecure-validators` — generate validator keystores

**3. Start the full stack (every start)**

```bash
docker compose --env-file examples/.env \
  -f examples/docker-compose-main.yml --profile full up -d
```

Launches Reth, Lighthouse BN, and Lighthouse VC. Must start within `GENESIS_DELAY` (30s) of step 2.

**4. Verify (optional)**

```bash
bash scripts/healthcheck.sh --env examples/vars.mainnet-equivalent.env
```

Checks EL health (RPC, chain ID, sync, blocks, balance) + CL health (beacon reachable, slots advancing, finality, active validators).

---

## Operate

| Action | Command |
| --- | --- |
| Stop | `docker compose -f examples/docker-compose-main.yml --profile dev --profile full down` |
| Reset Tier 1 | `docker compose -f examples/docker-compose-main.yml --profile dev down -v` |
| Reset Tier 2 | `FORCE=1 bash examples/docker-setup-genesis.sh` |

---

## Files

| File | Purpose |
| --- | --- |
| `env.example` | Compose env template: Reth v2.3.0, Lighthouse v8.2.0, FEE_RECIPIENT |
| `.env` | Actual compose env (copied from `env.example`; gitignored) |
| `docker-setup-genesis.sh` | One-time PoS genesis ceremony |
| `docker-compose-main.yml` | Tier 1: Reth `--dev`; Tier 2: Reth + BN + VC |
| `genesis.mainnet-equivalent.json` | EL genesis template (Prague fork, blobSchedule) |
| `vars.mainnet-equivalent.env` | Shell-sourced config for scripts (paths, chainId, accounts, images) |

## See also

- [`docs/MAINNET_EQUIVALENT.md`](../docs/MAINNET_EQUIVALENT.md) — full guide
- [`docs/DOCKER.md`](../docs/DOCKER.md) — deployment guide
