# `genesis.json` Field Reference

This document describes every field in the execution-layer genesis file used by this
project (`genesis.json`), what it means, and the **default values in this repo**.

The file follows the standard Ethereum genesis format consumed by Reth (and other EL
clients). It defines the state of block `0` — chain rules, header fields, and initial
account balances — before any transactions are executed.

> **Related config:** `vars.env` sets `CHAIN_ID=12345`, which must stay in sync with
> `config.chainId` below. Pre-funded accounts are configured via `MNEMONIC` and
> `GENESIS_ACCOUNT_*` in `vars.env` and rendered by `scripts/render-genesis.sh`.

---

## Rendering from `vars.env`

Do **not** edit `alloc` by hand for routine dev work. Configure accounts in `vars.env`:

```bash
MNEMONIC="test test test test test test test test test test test junk"
GENESIS_ACCOUNT_COUNT=4
GENESIS_ACCOUNT_BALANCE_ETH=1000000
GENESIS_ACCOUNT_BALANCES_ETH="1000000,1000000,1000000,1000000"
```

Then render (requires `pip install eth-account`):

```bash
bash scripts/render-genesis.sh
```

Or let `docker-up.sh` / `docker-setup-genesis.sh` call it automatically.

| Variable | Default | Description |
| --- | --- | --- |
| `MNEMONIC` | Hardhat / Anvil test mnemonic | BIP-39 phrase; addresses at `m/44'/60'/0'/0/N` |
| `GENESIS_ACCOUNT_COUNT` | `4` | How many HD indices to fund |
| `GENESIS_ACCOUNT_BALANCE_ETH` | `1000000` | Fallback balance (ETH) when per-account list is omitted |
| `GENESIS_ACCOUNT_BALANCES_ETH` | four × `1000000` | Comma-separated ETH balance per account index |
| `GENESIS_FILE` | `genesis.json` | Output file (mainnet-equiv: `examples/genesis.mainnet-equivalent.json`) |
| `CHAIN_ID` | `12345` | Written into `config.chainId` during render |

The renderer preserves **non-mnemonic** `alloc` entries already in the genesis file
(e.g. the `0x…00ff` placeholder in mainnet-equivalent genesis).

After changing genesis fields that affect the block hash:

```bash
# Tier 1 — wipe dev volume and restart:
docker compose --profile dev down -v
bash docker-up.sh --profile dev up -d

# Tier 2 — re-bind consensus layer to new EL genesis hash:
FORCE=1 bash docker-setup-genesis.sh
bash docker-up.sh --profile full up -d
```

---

## File structure (overview)

```json
{
  "config": { ... },   // chain rules & fork activation
  "nonce": "...",      // genesis block header
  "timestamp": "...",
  "extraData": "...",
  "gasLimit": "...",
  "difficulty": "...",
  "mixHash": "...",
  "coinbase": "...",
  "alloc": { ... }     // initial account state
}
```

---

## `config` — chain rules & forks

| Field | Default (this repo) | Meaning |
| --- | --- | --- |
| `chainId` | `12345` | EIP-155 chain identifier. Wallets and tools use this to sign transactions and distinguish networks. Must match `CHAIN_ID` in `vars.env`. |
| `homesteadBlock` | `0` | [Homestead](https://eips.ethereum.org/EIPS/eip-2) hard fork active from block 0. |
| `eip150Block` | `0` | [EIP-150](https://eips.ethereum.org/EIPS/eip-150) (Tangerine Whistle) — gas cost changes, active from block 0. |
| `eip155Block` | `0` | [EIP-155](https://eips.ethereum.org/EIPS/eip-155) — replay protection via `chainId` in signatures, active from block 0. |
| `eip158Block` | `0` | [EIP-158](https://eips.ethereum.org/EIPS/eip-158) (Spurious Dragon) — state clearing rules, active from block 0. |
| `byzantiumBlock` | `0` | [Byzantium](https://eips.ethereum.org/EIPS/eip-609) — `REVERT`, `RETURNDATA`, active from block 0. |
| `constantinopleBlock` | `0` | [Constantinople](https://eips.ethereum.org/EIPS/eip-1014) — `CREATE2`, `SHL`/`SHR`, active from block 0. |
| `petersburgBlock` | `0` | [Petersburg](https://eips.ethereum.org/EIPS/eip-1716) — removes one Constantinople change, active from block 0. |
| `istanbulBlock` | `0` | [Istanbul](https://eips.ethereum.org/EIPS/eip-1679) — Blake2, chain ID in `CHAINID` opcode, active from block 0. |
| `berlinBlock` | `0` | [Berlin](https://eips.ethereum.org/EIPS/eip-2565) — gas repricing (EIP-2929 access lists), active from block 0. |
| `londonBlock` | `0` | [London](https://eips.ethereum.org/EIPS/eip-3554) — EIP-1559 base fee, active from block 0. |
| `mergeNetsplitBlock` | `0` | [Paris / The Merge](https://eips.ethereum.org/EIPS/eip-3675) — transition to proof-of-stake, active from block 0. No PoW phase on this devnet. |
| `shanghaiTime` | `0` | [Shanghai](https://eips.ethereum.org/EIPS/eip-4895) — `PUSH0`, beacon withdrawals, active at genesis timestamp (`0`). |
| `cancunTime` | `0` | [Cancun](https://eips.ethereum.org/EIPS/eip-7569) — EIP-4844 blobs, `MCOPY`, `BLOBHASH`, active at genesis timestamp (`0`). |
| `terminalTotalDifficulty` | `0` | Cumulative PoW difficulty at which the Merge is triggered. `0` means there is no PoW mining phase; the chain starts post-merge. |
| `terminalTotalDifficultyPassed` | `true` | Signals that the Merge has already occurred. Required for a chain that begins in PoS mode. |
| `depositContractAddress` | `0x4242424242424242424242424242424242424242` | Address of the beacon-chain deposit contract on the execution layer. This is a well-known placeholder (`0x42…42`) used in dev/test networks. Real mainnet uses `0x00000000219ab540356cBB839Cbe05303d7705Fa`. |

**Design intent:** all forks are active from genesis (`0` block or `0` timestamp), so the
devnet immediately behaves like a current Ethereum mainnet-equivalent EVM (through Cancun),
without simulating historical upgrade heights.

Mainnet-equivalent genesis adds `pragueTime` and `blobSchedule`; see
[`examples/genesis.mainnet-equivalent.json`](../examples/genesis.mainnet-equivalent.json).

---

## Genesis block header fields

These fields describe block `0` itself. Post-merge, several PoW-related fields are zeroed
or unused but must still be present for client compatibility.

| Field | Default (this repo) | Meaning |
| --- | --- | --- |
| `nonce` | `"0x0"` | PoW block nonce (8 bytes). Unused after the Merge; kept as zero. |
| `timestamp` | `"0x0"` | Unix timestamp of the genesis block. `0` is typical for devnets; the CL genesis time is set separately in `docker-setup-genesis.sh`. |
| `extraData` | `"0x"` | Arbitrary extra data in the block header (often validator/client identity on PoS). Empty on this devnet. |
| `gasLimit` | `"0x1c9c380"` | Maximum gas per block. `0x1c9c380` = **30,000,000** gas (same order of magnitude as mainnet). |
| `difficulty` | `"0x0"` | PoW difficulty. `0` because the chain starts post-merge (no mining). |
| `mixHash` | `"0x0000…0000"` (32 zero bytes) | PoW mix hash. Unused post-merge; zero-filled. |
| `coinbase` | `"0x0000…0000"` | Address that receives block rewards in PoW. Zero address on this devnet; PoS fee recipient is configured via `FEE_RECIPIENT` in `vars.env` / Lighthouse flags. |

---

## `alloc` — initial account state

Maps addresses to their state at genesis (before block 1). Each entry can include:

| Sub-field | Required | Default in this repo | Meaning |
| --- | --- | --- | --- |
| `balance` | yes (for funded accounts) | `"0xd3c21bcecceda1000000"` per account | Account balance in **wei**, as a hex string. `0xd3c21bcecceda1000000` = **1,000,000 ETH**. |
| `code` | no | *(omitted)* | Contract bytecode deployed at genesis. Use for pre-deployed bridge / system contracts. |
| `storage` | no | *(omitted)* | Contract storage slots at genesis. Keys and values are hex-encoded 32-byte words. |
| `nonce` | no | *(omitted)* | Account transaction nonce at genesis. Defaults to `0` if omitted. Set to `1` or higher if you need the address to behave as if it already sent transactions. |

### Default pre-funded accounts

These are the first four [Anvil / Hardhat](https://book.getfoundry.sh/reference/anvil/) test
accounts (default `MNEMONIC` in `vars.env`):

| Index | Address | Balance (default) | Private key (test only) |
| --- | --- | --- | --- |
| 0 | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | 1,000,000 ETH | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` |
| 1 | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | 1,000,000 ETH | `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d` |
| 2 | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | 1,000,000 ETH | `0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a` |
| 3 | `0x90F79bf6EB2c4f870365E785982E1f101E93b906` | 1,000,000 ETH | `0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6` |

> Never use these keys on a public network.

### Example: add a pre-deployed contract

Add the entry directly to the genesis JSON template (the renderer preserves addresses
not derived from `MNEMONIC`):

```json
"alloc": {
  "0x00000000000000000000000000000000000000ff": {
    "balance": "0x0",
    "code": "0x608060405234801561001057600080fd5b50...",
    "storage": {
      "0x0000000000000000000000000000000000000000000000000000000000000000": "0x0000000000000000000000000000000000000000000000000000000000000001"
    }
  }
}
```

---

## Common customizations

| Goal | What to change |
| --- | --- |
| **Mainnet-equivalent** | `examples/vars.mainnet-equivalent.env` + `examples/docker-setup-genesis.sh` + `docker-up.sh -f examples/docker-compose-main.yml` |
| Different chain ID | `CHAIN_ID` in `vars.env` (render syncs `config.chainId`) |
| More / different funded accounts | `GENESIS_ACCOUNT_COUNT`, `GENESIS_ACCOUNT_BALANCES_ETH` in `vars.env`, then re-render |
| Pre-deploy bridge / system contracts | `alloc` → `code` (+ optional `storage`) in genesis template |
| Higher block gas limit | `gasLimit` in genesis template (hex gas units, e.g. `0x2faf080` = 50M) |
| Enable a newer fork (e.g. Prague) | Add the corresponding `*Time` or `*Block` field per your Reth/Lighthouse version docs |

---

## How clients use this file

| Script / path | Usage |
| --- | --- |
| `scripts/render-genesis.sh` | Writes `alloc` + `config.chainId` from `vars.env` |
| `docker-up.sh` | Calls `render-genesis.sh`, then `docker compose` |
| `docker-setup-genesis.sh` | Calls `render-genesis.sh`, then `reth init` + `lcli` |
| `docker-compose.yml` | Mounts `./genesis.json` into the Reth container |
| `vars.env` | `GENESIS_FILE`, `CHAIN_ID`, `MNEMONIC`, account balances |

The execution genesis block hash (derived from these fields) is embedded into the
consensus-layer genesis during `docker-setup-genesis.sh`. If you change header or `alloc`
fields, the hash changes — which is why Tier 2 requires regenerating `testnet/`.
