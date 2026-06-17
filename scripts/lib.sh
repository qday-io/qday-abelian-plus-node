# shellcheck shell=bash
# Shared helpers for RPC verification scripts.

rpc_call() {
  local method="$1"
  local params="${2:-[]}"
  curl -sf --connect-timeout 3 --max-time 10 "$RPC_URL" \
    -X POST \
    -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}"
}

rpc_result() {
  python3 -c 'import json,sys; r=json.load(sys.stdin).get("result"); print("false" if r is False else ("true" if r is True else r))' <<<"$1"
}

hex_to_int() {
  python3 -c 'import sys; print(int(sys.argv[1], 16))' "$1"
}

pass() {
  echo "  PASS $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo "  FAIL $1"
  FAILED=$((FAILED + 1))
}

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
