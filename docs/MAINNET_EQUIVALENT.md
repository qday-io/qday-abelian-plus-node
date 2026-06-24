# Mainnet-Equivalent (Docker)

Private L1 with mainnet-grade EVM rules (Prague + `blobSchedule`). `chainId` **31337**.

Account configuration lives in `examples/vars.mainnet-equivalent.env` (same `MNEMONIC` /
`GENESIS_ACCOUNT_*` variables as dev `vars.env`).

## Commands

```bash
# Tier 1 — EL auto-mining
docker compose --env-file examples/.env \
  -f examples/docker-compose-main.yml --profile dev up -d
bash scripts/healthcheck.sh --env examples/vars.mainnet-equivalent.env --el-only

# Tier 2 — full PoS
bash examples/docker-setup-genesis.sh
docker compose --env-file examples/.env \
  -f examples/docker-compose-main.yml --profile full up -d
bash scripts/healthcheck.sh --env examples/vars.mainnet-equivalent.env
```

Reset: `FORCE=1 bash examples/docker-setup-genesis.sh`

Start within **30s** after genesis setup (`GENESIS_DELAY`).

After changing account balances on Tier 1:

```bash
docker compose -f examples/docker-compose-main.yml --profile dev down -v
docker compose --env-file examples/.env \
  -f examples/docker-compose-main.yml --profile dev up -d
```

## Files

| File | Purpose |
| --- | --- |
| `examples/docker-compose-main.yml` | Compose stack |
| `examples/genesis.mainnet-equivalent.json` | EL genesis template (alloc rendered from env) |
| `examples/vars.mainnet-equivalent.env` | Paths, chainId, mnemonic, balances |
| `examples/docker-setup-genesis.sh` | One-time PoS genesis ceremony (6 steps: render genesis → JWT → reth init → lcli testnet → interop-genesis → insecure-validators) |
| `render-genesis.sh` | Render genesis alloc (run manually or set `VARS_ENV`) |
| `.env.example` | Full variable reference for all profiles |

See [`docs/GENESIS.md`](GENESIS.md) for field reference, [`.env.example`](../.env.example) for variable reference, [`scripts/README.md`](../scripts/README.md) for script catalog.
