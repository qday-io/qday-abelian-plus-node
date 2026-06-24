#!/usr/bin/env bash
# PASS/FAIL health assertions for EL (+ optional CL). Exits non-zero on failure.
#
# Requires cast (Foundry).
#
# Usage:
#   bash scripts/healthcheck.sh                              # full stack (EL + CL)
#   bash scripts/healthcheck.sh --el-only                    # execution layer only (Tier 1 dev)
#   bash scripts/healthcheck.sh --tx                         # also run transaction test
#   bash scripts/healthcheck.sh --env examples/vars.mainnet-equivalent.env --el-only
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ROOT_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"

ENV_FILE=""
EL_ONLY=0
RUN_TX=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_FILE="$2"; shift 2 ;;
    --env=*) ENV_FILE="${1#*=}"; shift ;;
    --el-only) EL_ONLY=1; shift ;;
    --tx) RUN_TX=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--env <path>] [--el-only] [--tx]"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# Load env file: --env flag > VARS_ENV > defaults
if [[ -n "$ENV_FILE" ]]; then
  if [[ "$ENV_FILE" != /* ]]; then
    ENV_FILE="$ROOT_DIR/$ENV_FILE"
  fi
  # shellcheck disable=SC1090
  source "$ENV_FILE"
elif [[ -n "${VARS_ENV:-}" ]]; then
  if [[ "$VARS_ENV" != /* ]]; then
    VARS_ENV="$ROOT_DIR/$VARS_ENV"
  fi
  if [[ -f "$VARS_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$VARS_ENV"
  fi
fi

RETH_HTTP_PORT="${RETH_HTTP_PORT:-1545}"
BN_HTTP_PORT="${BN_HTTP_PORT:-1052}"
CHAIN_ID="${CHAIN_ID:-12345}"
RPC_URL="${RPC_URL:-http://127.0.0.1:${RETH_HTTP_PORT}}"
BEACON_URL="${BEACON_URL:-http://127.0.0.1:${BN_HTTP_PORT}}"
PREFUNDED_ACCOUNT="${PREFUNDED_ACCOUNT:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}"

pass() { echo "  PASS $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL $1"; FAILED=$((FAILED + 1)); }
summary() {
  echo "== Summary =="
  echo "  $PASSED passed, $FAILED failed"
  if [[ "$FAILED" -eq 0 ]]; then
    echo "  Deployment looks healthy."
    return 0
  fi
  echo "  Deployment has failures."
  return 1
}

EL_ONLY=0
RUN_TX=0
for arg in "$@"; do
  case "$arg" in
    --el-only) EL_ONLY=1 ;;
    --tx) RUN_TX=1 ;;
    -h|--help)
      echo "Usage: $0 [--el-only] [--tx]"
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

if ! command -v cast &>/dev/null; then
  echo "ERROR: cast not found. Install Foundry:" >&2
  echo "  curl -L https://foundry.paradigm.xyz | bash && foundryup" >&2
  exit 1
fi

PASSED=0
FAILED=0
CAST="cast --rpc-url $RPC_URL"

echo "== Execution layer (Reth @ $RPC_URL) =="

# RPC reachability + client version
if ver=$($CAST client 2>/dev/null); then
  pass "RPC reachable ($ver)"
else
  fail "RPC reachable"
fi

# Chain ID
if chain=$($CAST chain-id 2>/dev/null); then
  if [[ "$chain" == "$CHAIN_ID" ]]; then
    pass "chainId == $CHAIN_ID"
  else
    fail "chainId == $CHAIN_ID (got $chain)"
  fi
else
  fail "chainId == $CHAIN_ID (RPC error)"
fi

# Sync status
if sync=$($CAST rpc eth_syncing 2>/dev/null); then
  if [[ "$sync" == "false" || "$sync" == "False" ]]; then
    pass "node is synced (eth_syncing=false)"
  else
    fail "node is synced (eth_syncing=$sync)"
  fi
else
  fail "node is synced (RPC error)"
fi

# Block production — two samples 3s apart
b1=$($CAST block-number 2>/dev/null || echo 0)
sleep 3
b2=$($CAST block-number 2>/dev/null || echo 0)
if [[ "$b2" -gt "$b1" ]]; then
  pass "block production (advanced $b1 -> $b2)"
else
  fail "block production (stuck at $b1)"
fi

# Pre-funded account balance
bal=$($CAST balance "$PREFUNDED_ACCOUNT" 2>/dev/null || echo 0)
if [[ "$bal" != "0" ]]; then
  pass "pre-funded account $PREFUNDED_ACCOUNT has balance ($bal wei)"
else
  fail "pre-funded account $PREFUNDED_ACCOUNT has balance"
fi

# Gas price
gas=$($CAST gas-price 2>/dev/null || echo "")
if [[ -n "$gas" ]]; then
  pass "eth_gasPrice responds ($gas wei)"
else
  fail "eth_gasPrice responds"
fi

if [[ "$EL_ONLY" -eq 0 ]]; then
  echo "== Consensus layer (Beacon @ $BEACON_URL) =="

  bn_health=$(curl -sf --connect-timeout 3 --max-time 10 "$BEACON_URL/eth/v1/node/health" || true)
  if [[ -n "$bn_health" ]]; then
    pass "beacon node reachable"
  else
    fail "beacon node reachable"
  fi

  head_json=$(curl -sf --connect-timeout 3 --max-time 10 "$BEACON_URL/eth/v1/beacon/headers/head" || true)
  if [[ -n "$head_json" ]]; then
    slot1=$(echo "$head_json" | sed -n 's/.*"slot":"\([0-9]*\)".*/\1/p' | head -1 || echo 0)
    sleep 3
    head2_json=$(curl -sf --connect-timeout 3 --max-time 10 "$BEACON_URL/eth/v1/beacon/headers/head" || true)
    slot2=$(echo "$head2_json" | sed -n 's/.*"slot":"\([0-9]*\)".*/\1/p' | head -1 || echo 0)
    if [[ "$slot2" -gt "$slot1" ]]; then
      pass "head slot advancing ($slot1 -> $slot2)"
    else
      fail "head slot advancing (stuck at $slot1)"
    fi
  else
    fail "beacon head slot query"
  fi

  sync_json=$(curl -sf --connect-timeout 3 --max-time 10 "$BEACON_URL/eth/v1/node/syncing" || true)
  if [[ -n "$sync_json" ]]; then
    is_syncing=$(echo "$sync_json" | grep -o '"is_syncing":[a-z]*' | cut -d: -f2 || echo true)
    if [[ "$is_syncing" == "false" ]]; then
      pass "beacon not stuck syncing"
    else
      fail "beacon not stuck syncing"
    fi
  else
    fail "beacon sync status"
  fi

  finality_json=$(curl -sf --connect-timeout 3 --max-time 10 "$BEACON_URL/eth/v1/beacon/states/head/finality_checkpoints" || true)
  if [[ -n "$finality_json" ]]; then
    pass "finalized epoch reported"
  else
    fail "finalized epoch reported"
  fi

  validators_json=$(curl -sf --connect-timeout 3 --max-time 10 "$BEACON_URL/eth/v1/beacon/states/head/validators" || true)
  if [[ -n "$validators_json" ]]; then
    active=$(echo "$validators_json" | grep -o '"status":"active_ongoing"' | wc -l | tr -d ' ' || echo 0)
    if [[ "$active" -ge 1 ]]; then
      pass "at least one active validator ($active)"
    else
      fail "at least one active validator"
    fi
  else
    fail "validator query"
  fi
fi

if [[ "$RUN_TX" -eq 1 ]]; then
  echo "== Transaction test =="
  FROM_PK="${FROM_PK:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
  TO_ADDR="${TO_ADDR:-0x70997970C51812dc3A010C7d01b50e0d17dc79C8}"
  VALUE_WEI="${VALUE_WEI:-10000000000000000}"

  bal_before=$($CAST balance "$TO_ADDR" 2>/dev/null || echo 0)
  tx_hash=$($CAST send "$TO_ADDR" \
    --value "$VALUE_WEI" \
    --private-key "$FROM_PK" \
    2>/dev/null || echo "")

  if [[ -z "$tx_hash" ]]; then
    fail "send transaction"
  else
    bal_after=$($CAST balance "$TO_ADDR" 2>/dev/null || echo 0)
    delta=$((bal_after - bal_before))

    echo "  from:  $(cast wallet address --private-key "$FROM_PK" 2>/dev/null)"
    echo "  to:    $TO_ADDR"
    echo "  tx:    $tx_hash"
    echo "  delta: $delta wei"

    if [[ "$delta" == "$VALUE_WEI" ]]; then
      pass "value transfer ($VALUE_WEI wei)"
    else
      fail "value transfer (delta=$delta)"
    fi
  fi
fi

summary
