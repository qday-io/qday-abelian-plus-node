#!/usr/bin/env bash
# Render genesis from vars.env, then run docker compose.
#
# Steps:
#   1. Source compose-env.sh — exports RETH_IMAGE, LIGHTHOUSE_IMAGE, ports, fee
#      recipient etc. for docker compose variable interpolation
#   2. Render genesis alloc — runs scripts/render-genesis.sh to ensure
#      genesis.json alloc matches the current vars.env (mnemonic, balances)
#   3. docker compose up — launches containers with the caller's arguments
#      (profile, detach mode, compose file override, etc.)
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
