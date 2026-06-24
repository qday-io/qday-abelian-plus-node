#!/usr/bin/env bash
# Mainnet-equivalent genesis ceremony via Docker (no local reth/lighthouse/lcli).
# Writes jwt, testnet/, validator keys, and initialises reth datadir on the host.
#
# Steps:
#   0. Render execution genesis alloc from vars.env + MNEMONIC → genesis.json
#   1. Generate JWT hex secret (Engine API auth between EL and CL)
#   2. reth init — initialise reth datadir with custom genesis, extract genesis block hash
#   3. (RPC fallback) Start a temporary reth node and query eth_getBlockByNumber(0x0)
#      to obtain the genesis block hash if step 2 failed to produce one
#   4. lcli new-testnet — create Lighthouse testnet config (fork epochs, TTD=0, validators)
#   5. lcli interop-genesis — generate beacon chain interop genesis state
#   6. lcli insecure-validators — generate insecure validator keystores under $LCLI_VALIDATORS_BASE
#
# Usage (from repo root):
#   bash examples/docker-setup-genesis.sh
#   FORCE=1 bash examples/docker-setup-genesis.sh
#
# Usage (from examples/):
#   bash docker-setup-genesis.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/vars.mainnet-equivalent.env"
export VARS_ENV="$SCRIPT_DIR/vars.mainnet-equivalent.env"

ensure_lcli_image() {
  if docker image inspect "$LCLI_IMAGE" >/dev/null 2>&1; then
    return 0
  fi
  if ! docker image inspect "${LIGHTHOUSE_IMAGE:-sigp/lighthouse:latest}" >/dev/null 2>&1; then
    echo "ERROR: need ${LIGHTHOUSE_IMAGE:-sigp/lighthouse:latest} locally before building lcli" >&2
    echo "       docker pull ${LIGHTHOUSE_IMAGE:-sigp/lighthouse:latest}" >&2
    exit 1
  fi
  echo "==> Building $LCLI_IMAGE (uses cached Lighthouse image; first run may take several minutes)"
  echo "    Needs network: rustup + github.com (not Docker Hub base images)"
  if ! docker build \
    --build-arg "LIGHTHOUSE_IMAGE=${LIGHTHOUSE_IMAGE:-sigp/lighthouse:latest}" \
    -t "$LCLI_IMAGE" -f "$ROOT_DIR/docker/Dockerfile.lcli" "$ROOT_DIR/docker"; then
    echo "ERROR: lcli image build failed (check GitHub/rust-lang network access)" >&2
    exit 1
  fi
}

PROBE_CONTAINER="${PROBE_CONTAINER:-abelian-reth-probe-mainnet-eq}"

abs_path() {
  python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$1"
}

GENESIS_FILE="$(abs_path "$GENESIS_FILE")"
JWT_FILE="$(abs_path "$JWT_FILE")"
RETH_DATADIR="$(abs_path "$RETH_DATADIR")"
TESTNET_DIR="$(abs_path "$TESTNET_DIR")"
LCLI_BASE="$(abs_path "${LCLI_VALIDATORS_BASE:-$ROOT_DIR}")"
mkdir -p "$TESTNET_DIR" "$RETH_DATADIR" "$(dirname "$JWT_FILE")" "$LCLI_BASE"

if [[ "${FORCE:-0}" = "1" ]]; then
  echo "==> FORCE=1: wiping previous mainnet-equivalent state"
  rm -rf "$RETH_DATADIR" "$TESTNET_DIR" \
         "${BEACON_DATADIR:-}" "${VC_DATADIR:-}" \
         "$LCLI_BASE/node_1"
fi

echo "==> Mainnet-equivalent Docker genesis setup"
echo "    Reth image:       $RETH_IMAGE"
echo "    Lighthouse image: $LIGHTHOUSE_IMAGE"
echo "    LCLI image:       $LCLI_IMAGE"
echo "    Genesis:          $GENESIS_FILE"
echo "    chainId:          $CHAIN_ID"

# --- 0. Render execution genesis alloc from vars.env ---
bash "$ROOT_DIR/scripts/render-genesis.sh"

# --- 1. JWT ---
if [[ ! -f "$JWT_FILE" ]]; then
  echo "==> Generating JWT -> $JWT_FILE"
  docker run --rm alpine sh -c 'apk add --no-cache openssl >/dev/null && openssl rand -hex 32' >"$JWT_FILE"
fi

# --- 2. reth init + genesis hash ---
echo "==> reth init"
if ! RETH_INIT_OUT=$(docker run --rm \
  -v "$GENESIS_FILE:/genesis.json:ro" \
  -v "$RETH_DATADIR:/data" \
  "$RETH_IMAGE" \
  init --chain /genesis.json --datadir /data 2>&1); then
  echo "$RETH_INIT_OUT" >&2
  exit 1
fi
echo "$RETH_INIT_OUT"
GENESIS_HASH=$(echo "$RETH_INIT_OUT" | sed 's/\x1b\[[0-9;]*m//g' \
  | grep 'Genesis block written' | grep -oE '0x[0-9a-fA-F]{64}' | head -1)

# --- 3. Genesis block hash (RPC fallback) ---
if [[ -z "$GENESIS_HASH" ]]; then
  echo "==> Reading execution genesis block hash (RPC fallback)"
  docker rm -f "$PROBE_CONTAINER" >/dev/null 2>&1 || true
  docker run -d --name "$PROBE_CONTAINER" \
    -p "127.0.0.1:${RETH_HTTP_PORT}:${RETH_HTTP_PORT}" \
    -v "$GENESIS_FILE:/genesis.json:ro" \
    -v "$RETH_DATADIR:/data" \
    -v "$JWT_FILE:/jwt.hex:ro" \
    "$RETH_IMAGE" \
    node --chain /genesis.json --datadir /data \
    --http --http.addr 0.0.0.0 --http.port "$RETH_HTTP_PORT" --http.api eth \
    --disable-discovery --authrpc.jwtsecret /jwt.hex >/dev/null

  cleanup_probe() { docker rm -f "$PROBE_CONTAINER" >/dev/null 2>&1 || true; }
  trap cleanup_probe EXIT

  for _ in $(seq 1 30); do
    RESP=$(curl -sf --connect-timeout 2 --max-time 5 \
      "http://127.0.0.1:${RETH_HTTP_PORT}" \
      -X POST -H 'Content-Type: application/json' \
      -d '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["0x0",false],"id":1}' \
      2>/dev/null) || RESP=""
    GENESIS_HASH=$(echo "$RESP" | sed -n 's/.*"hash":"\(0x[0-9a-fA-F]*\)".*/\1/p')
    [[ -n "$GENESIS_HASH" ]] && break
    sleep 1
  done
  cleanup_probe
  trap - EXIT
fi

if [[ -z "$GENESIS_HASH" ]]; then
  echo "ERROR: could not read genesis hash from reth container" >&2
  exit 1
fi
echo "    genesis hash = $GENESIS_HASH"

# --- 4. lcli testnet + interop genesis + validator keys ---
ensure_lcli_image
GENESIS_TIME=$(($(date +%s) + GENESIS_DELAY))
echo "==> lcli new-testnet (genesis at +${GENESIS_DELAY}s)"
docker run --rm \
  -v "$TESTNET_DIR:/testnet" \
  "$LCLI_IMAGE" \
  new-testnet \
  --spec mainnet \
  --testnet-dir /testnet \
  --min-genesis-active-validator-count "$VALIDATOR_COUNT" \
  --validator-count "$VALIDATOR_COUNT" \
  --min-genesis-time "$GENESIS_TIME" \
  --genesis-delay "$GENESIS_DELAY" \
  --altair-fork-epoch 0 \
  --bellatrix-fork-epoch 0 \
  --capella-fork-epoch 0 \
  --deneb-fork-epoch 0 \
  --ttd 0 \
  --eth1-block-hash "$GENESIS_HASH" \
  --eth1-id "$CHAIN_ID" \
  --eth1-follow-distance 1 \
  --seconds-per-slot "$SECONDS_PER_SLOT" \
  --seconds-per-eth1-block "$SECONDS_PER_SLOT" \
  --force

echo "==> lcli interop-genesis"
docker run --rm \
  -v "$TESTNET_DIR:/testnet" \
  "$LCLI_IMAGE" \
  interop-genesis \
  --spec mainnet \
  --genesis-time "$GENESIS_TIME" \
  --testnet-dir /testnet \
  "$VALIDATOR_COUNT"

echo "==> lcli insecure-validators"
docker run --rm \
  -v "$LCLI_BASE:/base" \
  "$LCLI_IMAGE" \
  insecure-validators \
  --count "$VALIDATOR_COUNT" \
  --base-dir /base \
  --node-count 1

echo
echo "==> Mainnet-equivalent genesis setup complete."
echo "    Start within ${GENESIS_DELAY}s:"
echo "    Mainnet-eq PoS: docker compose -f examples/docker-compose-main.yml --profile full up -d"
echo "    Mainnet-eq EL:   docker compose -f examples/docker-compose-main.yml --profile dev up -d"
