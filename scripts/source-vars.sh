# Shared vars for verification scripts. Source from repo scripts/.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ROOT_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"

if [[ -n "${VARS_ENV:-}" ]]; then
  if [[ "$VARS_ENV" != /* ]]; then
    VARS_ENV="$ROOT_DIR/$VARS_ENV"
  fi
  if [[ -f "$VARS_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$VARS_ENV"
  fi
elif [[ -f "$ROOT_DIR/vars.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/vars.env"
fi

RETH_HTTP_PORT="${RETH_HTTP_PORT:-8545}"
BN_HTTP_PORT="${BN_HTTP_PORT:-5052}"
CHAIN_ID="${CHAIN_ID:-12345}"
RPC_URL="${RPC_URL:-http://127.0.0.1:${RETH_HTTP_PORT}}"
BEACON_URL="${BEACON_URL:-http://127.0.0.1:${BN_HTTP_PORT}}"
PREFUNDED_ACCOUNT="${PREFUNDED_ACCOUNT:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}"
MNEMONIC="${MNEMONIC:-test test test test test test test test test test test junk}"
GENESIS_ACCOUNT_COUNT="${GENESIS_ACCOUNT_COUNT:-4}"
GENESIS_ACCOUNT_BALANCE_ETH="${GENESIS_ACCOUNT_BALANCE_ETH:-1000000}"
