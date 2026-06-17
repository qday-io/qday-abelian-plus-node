#!/usr/bin/env bash
# Source vars.env (or VARS_ENV) and export Docker Compose interpolation variables.
set -a

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$(basename "${BASH_SOURCE[0]}")" == "compose-env.sh" ]]; then
  ROOT_DIR="${ROOT_DIR:-$(cd "$_script_dir/.." && pwd)}"
else
  ROOT_DIR="${ROOT_DIR:-$(pwd)}"
fi

if [[ -n "${VARS_ENV:-}" ]]; then
  if [[ "$VARS_ENV" != /* ]]; then
    VARS_ENV="$ROOT_DIR/$VARS_ENV"
  fi
  # shellcheck disable=SC1090
  source "$VARS_ENV"
elif [[ -f "$ROOT_DIR/vars.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/vars.env"
fi

export ROOT_DIR
export RETH_IMAGE="${RETH_IMAGE:-ghcr.io/paradigmxyz/reth:v2.3.0}"
export LIGHTHOUSE_IMAGE="${LIGHTHOUSE_IMAGE:-sigp/lighthouse:v8.1.3}"
export FEE_RECIPIENT="${FEE_RECIPIENT:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}"
export RETH_HTTP_PORT="${RETH_HTTP_PORT:-8545}"
export BN_HTTP_PORT="${BN_HTTP_PORT:-5052}"

set +a
