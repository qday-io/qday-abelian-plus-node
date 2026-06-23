# Mainnet-Equivalent (Docker)

Private L1 with mainnet-grade EVM rules (Prague + `blobSchedule`). `chainId` **31337**.

Account configuration lives in `examples/vars.mainnet-equivalent.env` (same `MNEMONIC` /
`GENESIS_ACCOUNT_*` variables as dev `vars.env`).

## Commands

```bash
# Tier 1 — EL auto-mining
VARS_ENV=examples/vars.mainnet-equivalent.env bash docker-up.sh \
  -f examples/docker-compose-main.yml --profile dev up -d
VARS_ENV=examples/vars.mainnet-equivalent.env bash scripts/healthcheck.sh --el-only

# Tier 2 — full PoS
bash examples/docker-setup-genesis.sh
VARS_ENV=examples/vars.mainnet-equivalent.env bash docker-up.sh \
  -f examples/docker-compose-main.yml --profile full up -d
VARS_ENV=examples/vars.mainnet-equivalent.env bash scripts/healthcheck.sh
```

Reset: `FORCE=1 bash examples/docker-setup-genesis.sh`

Start within **30s** after genesis setup (`GENESIS_DELAY`).

After changing account balances on Tier 1:

```bash
docker compose -f examples/docker-compose-main.yml --profile dev down -v
VARS_ENV=examples/vars.mainnet-equivalent.env bash docker-up.sh \
  -f examples/docker-compose-main.yml --profile dev up -d
```

## Files

| File | Purpose |
| --- | --- |
| `examples/docker-compose-main.yml` | Compose stack |
| `examples/genesis.mainnet-equivalent.json` | EL genesis template (alloc rendered from env) |
| `examples/vars.mainnet-equivalent.env` | Paths, chainId, mnemonic, balances |
| `examples/docker-setup-genesis.sh` | One-time PoS genesis ceremony (6 steps: render genesis → JWT → reth init → lcli testnet → interop-genesis → insecure-validators) |
| `docker-up.sh` | Render genesis + compose (set `VARS_ENV` for this profile) |
| `.env.example` | Full variable reference for all profiles |

See [`docs/GENESIS.md`](GENESIS.md) for field reference, [`.env.example`](../.env.example) for variable reference, [`scripts/README.md`](../scripts/README.md) for script catalog.
