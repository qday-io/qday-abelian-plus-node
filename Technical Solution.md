# Expend Abelian 

> **Note:** This document describes the original local-binary setup. The current repo uses
> **Docker-only** deployment — see [`README.md`](README.md) and [`docs/DOCKER.md`](docs/DOCKER.md).

> include DA,DAC (or zkrollup), committer ( push root to abelian)，L1 Devnet Deployment (Reth + Lighthouse)
> 

## Overview

This project sets up a **minimal Ethereum L1 devnet** using:

- Reth (Execution Layer)
- Lighthouse (Consensus Layer)
- Single Validator

This setup is suitable for:

- Rollup / CDK development
- Smart contract deployment
- Bridge testing
- Local L1 simulation

---

## Architecture

```
[ Reth (EL) ]  <--Engine API-->  [ Lighthouse BN (CL) ]  <---> [ Validator ]
        |
      RPC (8545)
```

---

## Features

- Single-node block production
- Full EVM compatibility
- JSON-RPC support (eth_call, sendTransaction)
- Lightweight and fast sync
- Suitable as L1 for Rollups / Sovereign chains

---

## Project Structure

```
l1-devnet/
├── jwt.hex
├── reth/
├── testnet/
├── scripts/
│   ├── install.sh
│   ├── start-reth.sh
│   ├── start-beacon.sh
│   ├── start-validator.sh
│   ├── start-all.sh
│   └── check.sh
└── README.md
```

---

## Installation

### 1. Install Dependencies

```bash
bash scripts/install.sh
```

### install.sh

```bash
#!/bin/bash
set -e

# install rust
curl https://sh.rustup.rs -sSf | sh -s -- -y
source $HOME/.cargo/env

# build reth
git clone https://github.com/paradigmxyz/reth.git
cd reth
cargo build --release
cd ..

# install lighthouse
curl https://raw.githubusercontent.com/sigp/lighthouse/master/scripts/install.sh -sSf | bash

echo "Install complete"
```

---

## Configuration

### 1. Generate JWT

```bash
openssl rand -hex 32 > jwt.hex
```

---

### 2. Initialize Lighthouse Testnet

```bash
lighthouse testnet bootstrap \
  --testnet-dir ./testnet \
  --min-genesis-time $(date +%s) \
  --genesis-delay 10 \
  --validator-count 1 \
  --force
```

---

## Start Services

### 1. Start Reth

```bash
bash scripts/start-reth.sh
```

```bash
#!/bin/bash

./reth/target/release/reth node \
  --chain dev \
  --http \
  --http.addr 0.0.0.0 \
  --http.port 8545 \
  --http.api eth,net,web3 \
  --authrpc.addr 127.0.0.1 \
  --authrpc.port 8551 \
  --authrpc.jwtsecret ./jwt.hex
```

---

### 2. Start Beacon Node

```bash
bash scripts/start-beacon.sh
```

```bash
#!/bin/bash

lighthouse beacon_node \
  --testnet-dir ./testnet \
  --execution-endpoint http://127.0.0.1:8551 \
  --execution-jwt ./jwt.hex \
  --http
```

---

### 3. Start Validator

```bash
bash scripts/start-validator.sh
```

```bash
#!/bin/bash

lighthouse validator_client \
  --testnet-dir ./testnet \
  --beacon-node http://127.0.0.1:5052
```

---

### 4. Start All

```bash
bash scripts/start-all.sh
```

```bash
#!/bin/bash
set -e

echo "Starting Reth..."
bash scripts/start-reth.sh &

sleep 5

echo "Starting Beacon Node..."
bash scripts/start-beacon.sh &

sleep 5

echo "Starting Validator..."
bash scripts/start-validator.sh &

echo "All services started"
wait
```

---

## Verification

### Check Block Production

```bash
bash scripts/check.sh
```

```bash
#!/bin/bash

curl -s http://localhost:8545 \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

Expected:

- Block number increases over time

---

## RPC Endpoint

```
http://localhost:8545
```

---

## Usage

You can connect using:

- Foundry
- Hardhat
- ethers.js / web3.js

---

## Notes

- This is a **single-node L1**, not production-safe
- No decentralization or security guarantees
- Suitable for development and testing only

---

## Recommended Enhancements

### 1. Docker Compose

Create services:

- reth
- lighthouse beacon
- lighthouse validator

---

### 2. Custom Genesis

Replace:

```
--chain dev
```

With:

- custom chainId
- prefunded accounts
- predeployed contracts

---

### 3. Performance Optimization

- Reduce RPC APIs
- Disable txpool (if using sequencer)
- Limit logging

---

### 4. Integration

This L1 can be used for:

- CDK (Polygon)
- OP Stack
- Sovereign chains
- Bridge testing

---

## Summary

This setup provides:

- Minimal Ethereum-compatible L1
- Fully functional EL + CL stack
- Lightweight and fast deployment
- Ideal base layer for Rollup development

---