#!/usr/bin/env bash
# Reset Tier 1 dev state: stop containers, wipe dev volume, re-render genesis, restart.
#
# Usage:
#   bash scripts/reset-dev.sh
#   COMPOSE_FILE=examples/docker-compose-main.yml bash scripts/reset-dev.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT_DIR

COMPOSE_FILE_ARGS=()
ENV_FILE_ARGS=(--env-file "$ROOT_DIR/.env")
if [[ -n "${COMPOSE_FILE:-}" ]]; then
  COMPOSE_FILE_ARGS=(-f "$COMPOSE_FILE")
  ENV_FILE_ARGS=(--env-file "$ROOT_DIR/examples/.env")
fi

echo "==> Stopping Tier 1 (profile dev) and removing volumes..."
docker compose "${COMPOSE_FILE_ARGS[@]}" --profile dev down -v

echo "==> Restarting Tier 1..."
bash "$ROOT_DIR/scripts/render-genesis.sh"
docker compose "${ENV_FILE_ARGS[@]}" "${COMPOSE_FILE_ARGS[@]}" --profile dev up -d

echo "==> Tier 1 reset complete."
echo "    Verify: bash scripts/healthcheck.sh --el-only"
