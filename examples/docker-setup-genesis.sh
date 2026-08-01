#!/usr/bin/env bash
# Mainnet-equivalent genesis ceremony via Docker (no local reth/lighthouse/lcli).
# Writes jwt, testnet/, validator keys, and initialises reth datadir on the host.
#
# Steps:
#   1. Generate JWT hex secret (Engine API auth between EL and CL)
#   2. Render EL genesis — MNEMONIC + GENESIS_ACCOUNT_* → alloc (+ sync chainId)
#   3. reth init — initialise reth datadir with custom genesis, extract genesis block hash
#   4. (RPC fallback) Start a temporary reth node and query eth_getBlockByNumber(0x0)
#      to obtain the genesis block hash if step 3 failed to produce one
#   5. Write testnet config.yaml (spec overrides, fork epochs, TTD=0) + deposit metadata
#   6. eth-genesis-state-generator — build genesis.ssz (EL block hash embedded from genesis.json)
#   7. lcli mnemonic-validators — generate validator keystores from mnemonic
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

ensure_image() {
  local image="$1"
  if docker image inspect "$image" >/dev/null 2>&1; then
    return 0
  fi
  echo "==> Pulling $image"
  if ! docker pull "$image"; then
    echo "ERROR: failed to pull $image" >&2
    exit 1
  fi
}

PROBE_CONTAINER="${PROBE_CONTAINER:-abelian-reth-probe-mainnet-eq}"

abs_path() {
  python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$1"
}

# Prior docker steps write files as root; remove via container so non-root hosts can re-run.
# Mount the parent dir — deleting a bind-mount root (/target) itself returns "Resource busy".
docker_rm_rf() {
  local target parent name
  [[ -n "${1:-}" ]] || return 0
  target="$(abs_path "$1")"
  [[ -e "$target" ]] || return 0
  parent="$(dirname "$target")"
  name="$(basename "$target")"
  docker run --rm -v "${parent}:/parent" alpine sh -c "rm -rf '/parent/${name}'"
}

docker_rm_under() {
  [[ -n "${1:-}" && -n "${2:-}" ]] || return 0
  docker_rm_rf "${1}/${2}"
}

# Prefer local cast (already required by healthcheck); fall back to Foundry image.
cast_cmd() {
  if command -v cast >/dev/null 2>&1; then
    cast "$@"
  else
    docker run --rm ghcr.io/foundry-rs/foundry:latest cast "$@"
  fi
}

# Render EL genesis from template:
#   - fund GENESIS_ACCOUNT_COUNT addresses from MNEMONIC (m/44'/60'/0'/0/N)
#   - preserve non-mnemonic alloc entries (e.g. 0x…00ff)
#   - sync config.chainId with CHAIN_ID
render_el_genesis() {
  local template="$1"
  local output="$2"
  if [[ ! -f "$template" ]]; then
    echo "ERROR: EL genesis template not found: $template" >&2
    exit 1
  fi
  if ! command -v cast >/dev/null 2>&1 && ! docker info >/dev/null 2>&1; then
    echo "ERROR: need 'cast' (Foundry) or Docker to derive MNEMONIC addresses" >&2
    echo "  Install: curl -L https://foundry.paradigm.xyz | bash && foundryup" >&2
    exit 1
  fi

  GENESIS_ACCOUNT_COUNT="${GENESIS_ACCOUNT_COUNT:-4}"
  GENESIS_ACCOUNT_BALANCE_ETH="${GENESIS_ACCOUNT_BALANCE_ETH:-1000000}"
  GENESIS_ACCOUNT_BALANCES_ETH="${GENESIS_ACCOUNT_BALANCES_ETH:-}"

  # Export for the Python helper below (cast_cmd is a bash function — derive in bash).
  local -a addrs=()
  local i addr
  # Strip up to 64 prior mnemonic indices from this phrase so COUNT shrinks / re-runs stay clean.
  local strip_to=64
  if (( GENESIS_ACCOUNT_COUNT > strip_to )); then
    strip_to="$GENESIS_ACCOUNT_COUNT"
  fi
  for ((i = 0; i < strip_to; i++)); do
    addr="$(cast_cmd wallet address --mnemonic "$MNEMONIC" --mnemonic-index "$i" | tr -d '[:space:]')"
    if [[ ! "$addr" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
      echo "ERROR: failed to derive address for mnemonic index $i (got: $addr)" >&2
      exit 1
    fi
    addrs+=("$addr")
  done

  MNEMONIC_ADDRS="$(printf '%s\n' "${addrs[@]}")" \
  GENESIS_ACCOUNT_COUNT="$GENESIS_ACCOUNT_COUNT" \
  GENESIS_ACCOUNT_BALANCE_ETH="$GENESIS_ACCOUNT_BALANCE_ETH" \
  GENESIS_ACCOUNT_BALANCES_ETH="$GENESIS_ACCOUNT_BALANCES_ETH" \
  CHAIN_ID="$CHAIN_ID" \
  python3 - "$template" "$output" <<'PY'
import json, os, sys

template_path, output_path = sys.argv[1], sys.argv[2]
count = int(os.environ["GENESIS_ACCOUNT_COUNT"])
default_bal = os.environ.get("GENESIS_ACCOUNT_BALANCE_ETH", "1000000").strip()
balances_raw = os.environ.get("GENESIS_ACCOUNT_BALANCES_ETH", "").strip()
chain_id = int(os.environ["CHAIN_ID"])
addrs = [a.strip() for a in os.environ["MNEMONIC_ADDRS"].splitlines() if a.strip()]

if balances_raw:
    balances = [b.strip() for b in balances_raw.split(",") if b.strip() != ""]
else:
    balances = []
if len(balances) < count:
    balances.extend([default_bal] * (count - len(balances)))
balances = balances[:count]

with open(template_path, encoding="utf-8") as f:
    genesis = json.load(f)

managed = {a.lower() for a in addrs}
new_alloc = {}
for addr, entry in (genesis.get("alloc") or {}).items():
    if addr.lower() not in managed:
        new_alloc[addr] = entry

for i in range(count):
    wei = int(balances[i]) * 10**18
    new_alloc[addrs[i]] = {"balance": hex(wei)}

genesis["alloc"] = new_alloc
genesis.setdefault("config", {})["chainId"] = chain_id

with open(output_path, "w", encoding="utf-8") as f:
    json.dump(genesis, f, indent=2)
    f.write("\n")
PY

  echo "    rendered $output"
  echo "    accounts: $GENESIS_ACCOUNT_COUNT (from MNEMONIC), chainId=$CHAIN_ID"
}

GENESIS_TEMPLATE="$(abs_path "${GENESIS_TEMPLATE:-$GENESIS_FILE}")"
JWT_FILE="$(abs_path "$JWT_FILE")"
RETH_DATADIR="$(abs_path "$RETH_DATADIR")"
TESTNET_DIR="$(abs_path "$TESTNET_DIR")"
LCLI_BASE="$(abs_path "${LCLI_VALIDATORS_BASE:-$ROOT_DIR}")"

if [[ "${FORCE:-0}" = "1" ]]; then
  echo "==> FORCE=1: wiping previous mainnet-equivalent state"
  docker_rm_rf "$RETH_DATADIR"
  docker_rm_rf "$TESTNET_DIR"
  docker_rm_rf "${BEACON_DATADIR:-}"
  docker_rm_rf "${VC_DATADIR:-}"
  docker_rm_under "$LCLI_BASE" "node_1"
fi

mkdir -p "$TESTNET_DIR" "$RETH_DATADIR" "$(dirname "$JWT_FILE")" "$LCLI_BASE"

# Rendered genesis consumed by reth init / CL genesis / compose --profile full.
GENESIS_FILE="$TESTNET_DIR/genesis.json"

echo "==> Mainnet-equivalent Docker genesis setup"
echo "    Reth image:           $RETH_IMAGE"
echo "    Lighthouse image:     $LIGHTHOUSE_IMAGE"
echo "    LCLI image:           $LCLI_IMAGE"
echo "    Beacon-genesis image: $BEACON_GENESIS_IMAGE"
echo "    Genesis template:     $GENESIS_TEMPLATE"
echo "    Genesis (rendered):   $GENESIS_FILE"
echo "    chainId:              $CHAIN_ID"

# --- 1. JWT ---
if [[ ! -f "$JWT_FILE" ]]; then
  echo "==> Generating JWT -> $JWT_FILE"
  docker run --rm alpine sh -c 'apk add --no-cache openssl >/dev/null && openssl rand -hex 32' >"$JWT_FILE"
fi

# --- 2. Render EL genesis (MNEMONIC → alloc) ---
echo "==> Rendering EL genesis from MNEMONIC"
render_el_genesis "$GENESIS_TEMPLATE" "$GENESIS_FILE"

# --- 3. reth init + genesis hash ---
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

# --- 4. Genesis block hash (RPC fallback) ---
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

# Build helper images before setting MIN_GENESIS_TIME (genesis window starts after step 5).
ensure_image "$LCLI_IMAGE"
ensure_image "$BEACON_GENESIS_IMAGE"

CL_CONFIG_TEMPLATE="${CL_CONFIG_TEMPLATE:-$SCRIPT_DIR/cl-config.mainnet-equivalent.yaml}"
if [[ ! -f "$CL_CONFIG_TEMPLATE" ]]; then
  echo "ERROR: CL config template not found: $CL_CONFIG_TEMPLATE" >&2
  exit 1
fi

# --- 5. Write testnet config.yaml + deposit metadata ---
GENESIS_TIME=$(($(date +%s) + GENESIS_DELAY))
echo "==> Writing testnet config (genesis at +${GENESIS_DELAY}s)"
sed \
  -e "s/__MIN_GENESIS_ACTIVE_VALIDATOR_COUNT__/${VALIDATOR_COUNT}/g" \
  -e "s/__MIN_GENESIS_TIME__/${GENESIS_TIME}/g" \
  -e "s/__GENESIS_DELAY__/${GENESIS_DELAY}/g" \
  -e "s/__DEPOSIT_CHAIN_ID__/${CHAIN_ID}/g" \
  -e "s/__DEPOSIT_NETWORK_ID__/${CHAIN_ID}/g" \
  -e "s/__SECONDS_PER_SLOT__/${SECONDS_PER_SLOT}/g" \
  -e "s/__SECONDS_PER_ETH1_BLOCK__/${SECONDS_PER_SLOT}/g" \
  "$CL_CONFIG_TEMPLATE" > "$TESTNET_DIR/config.yaml"
echo "0" > "$TESTNET_DIR/deposit_contract_block.txt"
echo "0" > "$TESTNET_DIR/deposit_contract_deploy_block.txt"
echo "$GENESIS_HASH" > "$TESTNET_DIR/deposit_contract_block_hash.txt"
echo "[]" > "$TESTNET_DIR/bootstrap_nodes.yaml"
echo "    testnet config written"
ls -la "$TESTNET_DIR/"

# --- 6. Generate CL genesis.ssz (embeds EL genesis block hash from genesis.json) ---
echo "==> eth-genesis-state-generator beaconchain -> genesis.ssz"
cat > "$TESTNET_DIR/mnemonics.yaml" <<YAML
- mnemonic: "${MNEMONIC}"
  start: 0
  count: ${VALIDATOR_COUNT}
YAML
if ! docker run --rm \
  -v "$TESTNET_DIR:/testnet" \
  -v "$GENESIS_FILE:/genesis.json:ro" \
  "$BEACON_GENESIS_IMAGE" \
  beaconchain \
  --eth1-config /genesis.json \
  --config /testnet/config.yaml \
  --mnemonics /testnet/mnemonics.yaml \
  --state-output /testnet/genesis.ssz \
  --quiet; then
  echo "ERROR: failed to generate genesis.ssz" >&2
  exit 1
fi
if [[ ! -s "$TESTNET_DIR/genesis.ssz" ]]; then
  echo "ERROR: genesis.ssz missing or empty after generation" >&2
  exit 1
fi
echo "    genesis.ssz written ($(wc -c < "$TESTNET_DIR/genesis.ssz" | tr -d ' ') bytes)"

# --- 7. Generate validator keystores ---
echo "==> lcli mnemonic-validators"
# lcli refuses to overwrite existing keystore dirs; always regenerate after new genesis.ssz.
docker_rm_under "$LCLI_BASE" "node_1"
mkdir -p "$LCLI_BASE/node_1"
docker run --rm --user "$(id -u):$(id -g)" \
  -v "$LCLI_BASE:/base" \
  "$LCLI_IMAGE" \
  mnemonic-validators \
  --count "$VALIDATOR_COUNT" \
  --base-dir /base \
  --mnemonic-phrase "$MNEMONIC" \
  --node-count 1

# Stale beacon DB from a prior run can prevent loading the new testnet dir.
if [[ -n "${BEACON_DATADIR:-}" ]]; then
  docker_rm_rf "$BEACON_DATADIR"
fi

echo
echo "==> Mainnet-equivalent genesis setup complete."
echo "    Start within ${GENESIS_DELAY}s:"
echo "    Mainnet-eq PoS: docker compose --env-file examples/.env \\"
echo "      -f examples/docker-compose-main.yml --profile full up -d"
echo "    Mainnet-eq EL:   docker compose --env-file examples/.env \\"
echo "      -f examples/docker-compose-main.yml --profile dev up -d"
