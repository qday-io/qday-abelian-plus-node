#!/usr/bin/env bash
# Render genesis from vars.env, then run docker compose.
#
# Usage:
#   bash docker-up.sh --profile dev up -d
#   VARS_ENV=examples/vars.mainnet-equivalent.env bash docker-up.sh \
#     -f examples/docker-compose-main.yml --profile full up -d
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROOT_DIR

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/compose-env.sh"

bash "$ROOT_DIR/scripts/render-genesis.sh"
exec docker compose "$@"
