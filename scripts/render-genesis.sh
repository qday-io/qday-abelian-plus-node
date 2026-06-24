#!/usr/bin/env bash
# Render genesis.json alloc from MNEMONIC + balance settings in vars.env.
# Preserves non-mnemonic alloc entries already present in the genesis file.
#
# Usage:
#   bash scripts/render-genesis.sh
#   bash scripts/render-genesis.sh --env examples/vars.mainnet-equivalent.env
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ROOT_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# Parse --env flag
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_FILE="$2"; shift 2 ;;
    --env=*) ENV_FILE="${1#*=}"; shift ;;
    -h|--help)
      echo "Usage: $0 [--env <path>]"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# Load env file: --env flag > VARS_ENV > defaults
if [[ -n "${ENV_FILE:-}" ]]; then
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

GENESIS_FILE="${GENESIS_FILE:-$ROOT_DIR/genesis.json}"
MNEMONIC="${MNEMONIC:-test test test test test test test test test test test junk}"
GENESIS_ACCOUNT_COUNT="${GENESIS_ACCOUNT_COUNT:-4}"
GENESIS_ACCOUNT_BALANCE_ETH="${GENESIS_ACCOUNT_BALANCE_ETH:-1000000}"
GENESIS_ACCOUNT_BALANCES_ETH="${GENESIS_ACCOUNT_BALANCES_ETH:-}"
CHAIN_ID="${CHAIN_ID:-12345}"

if [[ ! -f "$GENESIS_FILE" ]]; then
  echo "ERROR: genesis file not found: $GENESIS_FILE" >&2
  exit 1
fi

if ! python3 -c 'import eth_account' 2>/dev/null; then
  echo "ERROR: python3 package eth-account required (pip install eth-account)" >&2
  exit 1
fi

echo "==> Rendering genesis alloc -> $GENESIS_FILE"
echo "    chainId: $CHAIN_ID"
echo "    accounts: $GENESIS_ACCOUNT_COUNT (from MNEMONIC)"

MNEMONIC="$MNEMONIC" \
GENESIS_FILE="$GENESIS_FILE" \
CHAIN_ID="$CHAIN_ID" \
GENESIS_ACCOUNT_COUNT="$GENESIS_ACCOUNT_COUNT" \
GENESIS_ACCOUNT_BALANCE_ETH="$GENESIS_ACCOUNT_BALANCE_ETH" \
GENESIS_ACCOUNT_BALANCES_ETH="$GENESIS_ACCOUNT_BALANCES_ETH" \
python3 <<'PY'
import json
import os
from decimal import Decimal

from eth_account import Account

Account.enable_unaudited_hdwallet_features()

genesis_file = os.environ["GENESIS_FILE"]
chain_id = int(os.environ["CHAIN_ID"])
count = int(os.environ["GENESIS_ACCOUNT_COUNT"])
default_balance_eth = os.environ["GENESIS_ACCOUNT_BALANCE_ETH"]
balances_raw = os.environ.get("GENESIS_ACCOUNT_BALANCES_ETH", "").strip()
mnemonic = os.environ["MNEMONIC"]

if balances_raw:
    balance_eths = [part.strip() for part in balances_raw.split(",") if part.strip()]
else:
    balance_eths = [default_balance_eth] * count

if len(balance_eths) < count:
    balance_eths.extend([balance_eths[-1]] * (count - len(balance_eths)))
elif len(balance_eths) > count:
    balance_eths = balance_eths[:count]

with open(genesis_file, encoding="utf-8") as fh:
    genesis = json.load(fh)

genesis.setdefault("config", {})["chainId"] = chain_id

derived = {}
for index, balance_eth in enumerate(balance_eths):
    acct = Account.from_mnemonic(
        mnemonic,
        account_path=f"m/44'/60'/0'/0/{index}",
    )
    wei = int(Decimal(balance_eth) * Decimal(10**18))
    derived[acct.address] = {"balance": hex(wei)}

existing_alloc = genesis.get("alloc", {})
preserved = {
    addr: entry
    for addr, entry in existing_alloc.items()
    if addr not in derived
}

genesis["alloc"] = {**preserved, **derived}

with open(genesis_file, "w", encoding="utf-8") as fh:
    json.dump(genesis, fh, indent=2)
    fh.write("\n")

for index, (addr, entry) in enumerate(derived.items()):
    wei = int(entry["balance"], 16)
    eth = wei / 10**18
    print(f"    [{index}] {addr} = {eth:g} ETH")
PY
