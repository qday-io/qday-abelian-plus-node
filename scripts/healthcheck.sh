#!/usr/bin/env bash
# PASS/FAIL health assertions for EL (+ optional CL). Exits non-zero on failure.
#
# Usage:
#   bash scripts/healthcheck.sh              # full stack (EL + CL)
#   bash scripts/healthcheck.sh --el-only    # execution layer only (Tier 1 dev)
#   bash scripts/healthcheck.sh --tx         # also run transaction test
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/source-vars.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

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

PASSED=0
FAILED=0
expected_chain_hex=$(python3 -c 'import sys; print(hex(int(sys.argv[1])))' "$CHAIN_ID")

echo "== Execution layer (Reth @ $RPC_URL) =="

resp=$(rpc_call web3_clientVersion || true)
if [[ -z "$resp" ]]; then
  fail "RPC reachable"
else
  ver=$(rpc_result "$resp")
  pass "RPC reachable ($ver)"
fi

chain_hex=$(rpc_result "$(rpc_call eth_chainId || echo '{}')")
if [[ "$chain_hex" == "$expected_chain_hex" ]]; then
  pass "chainId == $CHAIN_ID"
else
  fail "chainId == $CHAIN_ID (got $chain_hex)"
fi

syncing=$(rpc_result "$(rpc_call eth_syncing || echo '{}')")
if [[ "$syncing" == "false" || "$syncing" == "False" ]]; then
  pass "node is synced (eth_syncing=false)"
else
  fail "node is synced (eth_syncing=$syncing)"
fi

b1=$(rpc_result "$(rpc_call eth_blockNumber || echo '{}')")
b1_int=$(hex_to_int "$b1" 2>/dev/null || echo 0)
sleep 3
b2=$(rpc_result "$(rpc_call eth_blockNumber || echo '{}')")
b2_int=$(hex_to_int "$b2" 2>/dev/null || echo 0)
if [[ "$b2_int" -gt "$b1_int" ]]; then
  pass "block production (advanced $b1_int -> $b2_int)"
else
  fail "block production (stuck at $b1_int)"
fi

bal=$(rpc_result "$(rpc_call eth_getBalance "[\"$PREFUNDED_ACCOUNT\",\"latest\"]" || echo '{}')")
if [[ -n "$bal" && "$bal" != "0x0" && "$bal" != "0" ]]; then
  pass "pre-funded account $PREFUNDED_ACCOUNT has balance"
else
  fail "pre-funded account $PREFUNDED_ACCOUNT has balance"
fi

gas=$(rpc_result "$(rpc_call eth_gasPrice || echo '{}')")
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
    slot1=$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["data"]["header"]["message"]["slot"])' <<<"$head_json" 2>/dev/null || echo 0)
    sleep 3
    head2_json=$(curl -sf --connect-timeout 3 --max-time 10 "$BEACON_URL/eth/v1/beacon/headers/head" || true)
    slot2=$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["data"]["header"]["message"]["slot"])' <<<"$head2_json" 2>/dev/null || echo 0)
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
    is_syncing=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["is_syncing"])' <<<"$sync_json" 2>/dev/null || echo true)
    if [[ "$is_syncing" == "False" || "$is_syncing" == "false" ]]; then
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
    active=$(python3 -c '
import json,sys
vals=json.load(sys.stdin)["data"]
print(sum(1 for v in vals if v.get("status")=="active_ongoing"))
' <<<"$validators_json" 2>/dev/null || echo 0)
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
  if bash "$SCRIPT_DIR/send-tx-test.sh"; then
    : # send-tx-test prints its own summary
  else
    fail "transaction test script"
  fi
fi

summary
