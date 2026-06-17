#!/usr/bin/env bash
# Send a value transfer and confirm receipt + balance change.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/source-vars.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

FROM_PK="${FROM_PK:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
TO_ADDR="${TO_ADDR:-0x70997970C51812dc3A010C7d01b50e0d17dc79C8}"
VALUE_WEI="${VALUE_WEI:-10000000000000000}"  # 0.01 ETH

PASSED=0
FAILED=0

echo "== Transaction test ($RPC_URL) =="

if ! python3 -c 'import eth_account' 2>/dev/null; then
  echo "ERROR: python3 package eth-account required (pip install eth-account)" >&2
  exit 1
fi

out=$(RPC_URL="$RPC_URL" FROM_PK="$FROM_PK" TO_ADDR="$TO_ADDR" VALUE_WEI="$VALUE_WEI" python3 <<'PY'
import json, os, subprocess, sys, time
from eth_account import Account

rpc_url = os.environ["RPC_URL"]
pk = os.environ["FROM_PK"]
to = os.environ["TO_ADDR"]
value = int(os.environ["VALUE_WEI"])
acct = Account.from_key(pk)

def rpc(method, params):
    body = json.dumps({"jsonrpc": "2.0", "method": method, "params": params, "id": 1})
    proc = subprocess.run(
        ["curl", "-sf", "--connect-timeout", "3", "--max-time", "15", rpc_url,
         "-X", "POST", "-H", "Content-Type: application/json", "-d", body],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr or proc.stdout or "curl failed")
    data = json.loads(proc.stdout)
    if "error" in data:
        raise RuntimeError(data["error"])
    return data["result"]

nonce = int(rpc("eth_getTransactionCount", [acct.address, "latest"]), 16)
gas_price = int(rpc("eth_gasPrice", []), 16)
chain_id = int(rpc("eth_chainId", []), 16)
bal_before = int(rpc("eth_getBalance", [to, "latest"]), 16)

tx = {
    "nonce": nonce,
    "gasPrice": gas_price,
    "gas": 21000,
    "to": to,
    "value": value,
    "data": b"",
    "chainId": chain_id,
}
signed = Account.sign_transaction(tx, pk)
raw = signed.raw_transaction.hex()
if not raw.startswith("0x"):
    raw = "0x" + raw
tx_hash = rpc("eth_sendRawTransaction", [raw])

receipt = None
for _ in range(15):
    time.sleep(1)
    receipt = rpc("eth_getTransactionReceipt", [tx_hash])
    if receipt:
        break
if not receipt:
    raise RuntimeError(f"no receipt for {tx_hash}")

bal_after = int(rpc("eth_getBalance", [to, "latest"]), 16)
print(json.dumps({
    "from": acct.address,
    "to": to,
    "tx_hash": tx_hash,
    "status": receipt.get("status"),
    "balance_before": bal_before,
    "balance_after": bal_after,
    "delta": bal_after - bal_before,
}))
PY
) || {
  fail "send raw transaction"
  summary
  exit 1
}

tx_hash=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["tx_hash"])' <<<"$out")
status=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])' <<<"$out")
delta=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["delta"])' <<<"$out")

echo "  from:  $(python3 -c 'import json,sys; print(json.load(sys.stdin)["from"])' <<<"$out")"
echo "  to:    $(python3 -c 'import json,sys; print(json.load(sys.stdin)["to"])' <<<"$out")"
echo "  tx:    $tx_hash"
echo "  delta: $delta wei"

if [[ "$status" == "0x1" && "$delta" == "$VALUE_WEI" ]]; then
  pass "value transfer ($VALUE_WEI wei)"
else
  fail "value transfer (status=$status delta=$delta)"
fi

summary
