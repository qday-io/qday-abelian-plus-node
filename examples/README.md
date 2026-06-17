# Mainnet-Equivalent (Docker)

```bash
# Tier 1 — EL auto-mining (no genesis ceremony)
docker compose -f examples/docker-compose-main.yml --profile dev up -d
bash scripts/healthcheck.sh --el-only

# Tier 2 — full PoS (from repo root)
bash examples/docker-setup-genesis.sh
docker compose -f examples/docker-compose-main.yml --profile full up -d
bash scripts/healthcheck.sh

# Stop
docker compose -f examples/docker-compose-main.yml --profile dev --profile full down
```

Reset: `FORCE=1 bash examples/docker-setup-genesis.sh`

## Files

| File | Purpose |
| --- | --- |
| `docker-setup-genesis.sh` | One-time mainnet-equivalent PoS genesis |
| `docker-compose-main.yml` | Tier 1: Reth `--dev`; Tier 2: Reth + Lighthouse BN + Validator |
| `genesis.mainnet-equivalent.json` | EL genesis |
| `vars.mainnet-equivalent.env` | Paths & chain params |

See [`docs/MAINNET_EQUIVALENT.md`](../docs/MAINNET_EQUIVALENT.md).
