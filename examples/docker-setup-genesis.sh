#!/usr/bin/env bash
# Mainnet-equivalent genesis ceremony via Docker (no local reth/lighthouse/lcli).
# Writes jwt, testnet/, validator keys, and initialises reth datadir on the host.
#
# Steps:
#   1. Generate JWT hex secret (Engine API auth between EL and CL)
#   2. reth init — initialise reth datadir with custom genesis, extract genesis block hash
#   3. (RPC fallback) Start a temporary reth node and query eth_getBlockByNumber(0x0)
#      to obtain the genesis block hash if step 2 failed to produce one
#   4. Write testnet config.yaml (spec overrides, fork epochs, TTD=0, EL genesis hash)
#   5. lcli generate-bootnode-enr — create pre-genesis boot node ENR
#   6. lcli mnemonic-validators — generate validator keystores from mnemonic
#
# Usage:
#   bash examples/docker-setup-genesis.sh
#   bash examples/docker-setup-genesis.sh --env examples/vars.custom.env
#   FORCE=1 bash examples/docker-setup-genesis.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse --env flag, then source default if not provided
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) VARS_ENV="$2"; shift 2 ;;
    --env=*) VARS_ENV="${1#*=}"; shift ;;
    -h|--help)
      echo "Usage: $0 [--env <path>]"
      echo "  FORCE=1 $0 [--env <path>]  (wipe and regenerate)"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "${VARS_ENV:-}" ]]; then
  VARS_ENV="$SCRIPT_DIR/vars.mainnet-equivalent.env"
fi
if [[ "$VARS_ENV" != /* ]]; then
  VARS_ENV="$ROOT_DIR/$VARS_ENV"
fi
# shellcheck disable=SC1090
source "$VARS_ENV"
export VARS_ENV

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

if [[ "${FORCE:-0}" = "1" ]]; then
  echo "==> FORCE=1: wiping previous mainnet-equivalent state"
  rm -rf "$RETH_DATADIR" "$TESTNET_DIR" \
         "${BEACON_DATADIR:-}" "${VC_DATADIR:-}" \
         "$LCLI_BASE/node_1"
fi

mkdir -p "$TESTNET_DIR" "$RETH_DATADIR" "$(dirname "$JWT_FILE")" "$LCLI_BASE"

echo "==> Mainnet-equivalent Docker genesis setup"
echo "    Reth image:       $RETH_IMAGE"
echo "    Lighthouse image: $LIGHTHOUSE_IMAGE"
echo "    LCLI image:       $LCLI_IMAGE"
echo "    Genesis:          $GENESIS_FILE"
echo "    chainId:          $CHAIN_ID"

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

# --- 4. Write testnet config.yaml ---
ensure_lcli_image
GENESIS_TIME=$(($(date +%s) + GENESIS_DELAY))
echo "==> Writing testnet config (genesis at +${GENESIS_DELAY}s)"
cat > "$TESTNET_DIR/config.yaml" <<YAML
CONFIG_NAME: mainnet
PRESET_BASE: mainnet
MIN_GENESIS_ACTIVE_VALIDATOR_COUNT: $VALIDATOR_COUNT
MIN_GENESIS_TIME: $GENESIS_TIME
GENESIS_DELAY: $GENESIS_DELAY
GENESIS_FORK_VERSION: "0x00000001"
ALTAIR_FORK_VERSION: "0x01000001"
ALTAIR_FORK_EPOCH: 0
BELLATRIX_FORK_VERSION: "0x02000001"
BELLATRIX_FORK_EPOCH: 0
CAPELLA_FORK_VERSION: "0x03000001"
CAPELLA_FORK_EPOCH: 0
DENEB_FORK_VERSION: "0x04000001"
DENEB_FORK_EPOCH: 0
MIN_VALIDATOR_WITHDRAWABILITY_DELAY: 256
SHARD_COMMITTEE_PERIOD: 256
TERMINAL_TOTAL_DIFFICULTY: 0
TERMINAL_TOTAL_DIFFICULTY_PASSED: true
DEPOSIT_CHAIN_ID: $CHAIN_ID
DEPOSIT_NETWORK_ID: $CHAIN_ID
DEPOSIT_CONTRACT_ADDRESS: "0x4242424242424242424242424242424242424242"
ETH1_FOLLOW_DISTANCE: 1
SECONDS_PER_SLOT: $SECONDS_PER_SLOT
SECONDS_PER_ETH1_BLOCK: $SECONDS_PER_SLOT
YAML
echo "0" > "$TESTNET_DIR/deposit_contract_block.txt"
echo "0" > "$TESTNET_DIR/deposit_contract_deploy_block.txt"
echo "0x0000000000000000000000000000000000000000000000000000000000000000" > "$TESTNET_DIR/deposit_contract_block_hash.txt"
echo "    testnet files written"
ls -la "$TESTNET_DIR/"

# --- 5. Generate boot node ENR ---
echo "==> lcli generate-bootnode-enr"
docker run --rm \
  -v "$TESTNET_DIR:/testnet" \
  "$LCLI_IMAGE" \
  generate-bootnode-enr \
  --testnet-dir /testnet \
  --ip 127.0.0.1 \
  --port 9000 \
  --output-dir /testnet 2>/dev/null || true

# --- 6. Generate validator keystores ---
echo "==> lcli mnemonic-validators"
docker run --rm \
  -v "$LCLI_BASE:/base" \
  "$LCLI_IMAGE" \
  mnemonic-validators \
  --count "$VALIDATOR_COUNT" \
  --base-dir /base \
  --mnemonic-phrase "$MNEMONIC" \
  --node-count 1

echo
echo "==> Mainnet-equivalent genesis setup complete."
echo "    Start within ${GENESIS_DELAY}s:"
echo "    Mainnet-eq PoS: docker compose -f examples/docker-compose-main.yml --profile full up -d"
echo "    Mainnet-eq EL:   docker compose -f examples/docker-compose-main.yml --profile dev up -d"
