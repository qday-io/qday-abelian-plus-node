#!/usr/bin/env bash
# Remove local runtime data directories. Stop containers first (docker compose down).
#
# Usage:
#   bash scripts/clean-data.sh --dev          # reth-dev volume + dev datadir hints
#   bash scripts/clean-data.sh --full         # dev Tier 2 artifacts
#   bash scripts/clean-data.sh --mainnet-eq  # mainnet-equivalent artifacts
#   bash scripts/clean-data.sh --all          # everything below
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT_DIR

usage() {
  echo "Usage: $0 [--dev | --full | --mainnet-eq | --all]" >&2
  exit 2
}

CLEAN_DEV=0
CLEAN_FULL=0
CLEAN_MAINNET=0

if [[ $# -eq 0 ]]; then
  usage
fi

for arg in "$@"; do
  case "$arg" in
    --dev) CLEAN_DEV=1 ;;
    --full) CLEAN_FULL=1 ;;
    --mainnet-eq) CLEAN_MAINNET=1 ;;
    --all) CLEAN_DEV=1; CLEAN_FULL=1; CLEAN_MAINNET=1 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $arg" >&2; usage ;;
  esac
done

remove_path() {
  local path="$1"
  if [[ -e "$path" ]]; then
    echo "  removing $path"
    rm -rf "$path"
  fi
}

if [[ "$CLEAN_DEV" -eq 1 ]]; then
  echo "==> Dev Tier 1 runtime data"
  docker compose --profile dev down -v 2>/dev/null || true
fi

if [[ "$CLEAN_FULL" -eq 1 ]]; then
  echo "==> Dev Tier 2 runtime data"
  docker compose --profile full down -v 2>/dev/null || true
  remove_path "$ROOT_DIR/reth-data"
  remove_path "$ROOT_DIR/testnet"
  remove_path "$ROOT_DIR/jwt.hex"
  remove_path "$ROOT_DIR/node_1"
  remove_path "$ROOT_DIR/beacon-data"
  remove_path "$ROOT_DIR/validator-data"
fi

if [[ "$CLEAN_MAINNET" -eq 1 ]]; then
  echo "==> Mainnet-equivalent runtime data"
  docker compose -f "$ROOT_DIR/examples/docker-compose-main.yml" --profile dev --profile full down -v 2>/dev/null || true
  remove_path "$ROOT_DIR/reth-data-mainnet-eq"
  remove_path "$ROOT_DIR/testnet-mainnet-eq"
  remove_path "$ROOT_DIR/jwt.mainnet-eq.hex"
  remove_path "$ROOT_DIR/l1-mainnet-eq"
  remove_path "$ROOT_DIR/beacon-data-mainnet-eq"
  remove_path "$ROOT_DIR/validator-data-mainnet-eq"
fi

echo "==> Clean complete."
