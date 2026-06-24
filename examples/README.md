# Mainnet-Equivalent (Docker)

Use `--env-file examples/.env` to pass required compose variables. Copy from
`.env.example` if the file doesn't exist:

```bash
cp .env.example examples/.env
```

## Commands

```bash
# Tier 1 — EL auto-mining (no genesis ceremony)
docker compose --env-file examples/.env \
  -f examples/docker-compose-main.yml --profile dev up -d
VARS_ENV=examples/vars.mainnet-equivalent.env bash scripts/healthcheck.sh --el-only

# Tier 2 — full PoS (from repo root)
bash examples/docker-setup-genesis.sh
docker compose --env-file examples/.env \
  -f examples/docker-compose-main.yml --profile full up -d
VARS_ENV=examples/vars.mainnet-equivalent.env bash scripts/healthcheck.sh

# Stop
docker compose -f examples/docker-compose-main.yml --profile dev --profile full down

# Wipe and reset
FORCE=1 bash examples/docker-setup-genesis.sh
```

## Files

| File | Purpose |
| --- | --- |
| `.env` | Compose interpolation variables (RETH_IMAGE, LIGHTHOUSE_IMAGE, FEE_RECIPIENT) |
| `docker-setup-genesis.sh` | One-time PoS genesis ceremony (6 steps: render genesis → JWT → reth init → lcli testnet → interop-genesis → validator keys) |
| `docker-compose-main.yml` | Tier 1: Reth `--dev`; Tier 2: Reth + Lighthouse BN + Validator |
| `genesis.mainnet-equivalent.json` | EL genesis template with Prague fork + blobSchedule |
| `vars.mainnet-equivalent.env` | Shell-sourced paths & chain params (chainId 31337) |

## See also

- [`docs/MAINNET_EQUIVALENT.md`](../docs/MAINNET_EQUIVALENT.md) — full guide
- [`.env.example`](../.env.example) — all configuration variables
