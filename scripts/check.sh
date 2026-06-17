#!/usr/bin/env bash
# Quick glance: RPC up, chainId, block number advancing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/source-vars.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

PASSED=0
FAILED=0

echo "== Quick check ($RPC_URL) =="

resp=$(rpc_call web3_clientVersion) || { echo "RPC unreachable at $RPC_URL"; exit 1; }
ver=$(rpc_result "$resp")
echo "client: $ver"

chain_hex=$(rpc_result "$(rpc_call eth_chainId)")
chain_int=$(hex_to_int "$chain_hex")
echo "chainId: $chain_int (expected $CHAIN_ID)"
[[ "$chain_int" -eq "$CHAIN_ID" ]] || exit 1

b1=$(rpc_result "$(rpc_call eth_blockNumber)")
b1_int=$(hex_to_int "$b1")
echo "block: $b1_int"
sleep 3
b2=$(rpc_result "$(rpc_call eth_blockNumber)")
b2_int=$(hex_to_int "$b2")
echo "block (+3s): $b2_int"
[[ "$b2_int" -gt "$b1_int" ]] || { echo "block number did not advance"; exit 1; }

echo "OK"
