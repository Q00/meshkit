# MeshKit

**The mobile era gave us apps. The agent era needs a call graph.**

MeshKit is an App-to-App MCP trust layer for Open Calling Graph. It gives participating apps a way to publish callable capabilities, accept signed requests, require user consent, execute inside the target app boundary, and return signed receipts.

Pitch: https://q00.github.io/meshkit/

## Why

AgentOS should not be a hidden controller that drives arbitrary apps. It should be a trusted router over apps that explicitly opt in.

MeshKit starts with three rules:

1. Apps stay sovereign. The target app owns validation, consent, execution, and receipts.
2. Calls are signed. Requests carry caller identity, target capability, payload hash, nonce, timestamp, and signature metadata.
3. Completion is proven. The caller accepts completion only from a target-signed receipt correlated to the original request.

## Architecture

```text
User / agent intent
  -> caller app
  -> Open Calling Graph capability discovery
  -> signed App-to-App MCP request
  -> target app validation and consent
  -> target-owned handler execution
  -> target-signed receipt
  -> caller receipt verification
```

## Current codebase

```text
meshkit-ios/                  Swift Package and iOS sample apps
meshkit-ios/Sources/MeshKit/  Core request, target, trust, receipt, and OCG models
meshkit-ios/Tests/            Trust-layer unit tests
meshkit-ios/Samples/iOSDemo/  HermesChat, MintNotes, and DailyMart app-to-app demo
ocg/registry/                 Sample OCG manifests
scripts/                      iOS verification and physical-device install scripts
```

## iPad install

Connect the iPad, make sure Xcode has prepared device support, and run:

```bash
DEVELOPMENT_TEAM=<APPLE_TEAM_ID> scripts/install_ios_device.sh
```

The script builds and installs:

- `HermesChat` — caller / agent surface
- `MintNotes` — target for `notes.append_note`
- `DailyMart` — target for `grocery.purchase_essentials`

The DailyMart demo budget is intentionally set to **₩100** for a visibly constrained consent gate.

## Verify

```bash
swift test --package-path meshkit-ios
python3 scripts/verify_ios_scaffold.py
python3 scripts/verify_ios_demo_apps.py
```

For simulator runtime proof:

```bash
scripts/e2e_ios_runtime.sh "platform=iOS Simulator,name=iPhone 16,OS=18.6"
```

## Trust model

MeshKit is designed around a fail-closed boundary:

- unsupported capability: reject
- malformed schema payload: reject
- invalid payload hash: reject
- stale timestamp: reject
- replayed nonce: reject
- missing consent: reject
- exceeded budget: reject
- unsigned or mismatched receipt: reject

## Blockchain direction

The first implementation keeps validation local and deterministic. The blockchain layer should anchor public OCG state and receipts without moving app execution on-chain:

- app and capability registry commitments
- verification-key rotation records
- consent-policy and risk-class attestations
- receipt hashes for auditability
- revocation and dispute evidence

The app remains the execution boundary. The chain becomes the shared trust and audit layer.

## maroo Agent Wallet demo boundary

The iPad demo uses maroo testnet as a replaceable MeshKit provider adapter, not as a core protocol dependency:

- Config schema: `meshkit-maroo-testnet-adapter-config/v1`
- `rpcEndpoint`: `https://rpc-testnet.maroo.io`
- `explorerBaseURL`: `https://explorer-testnet.maroo.io`
- `faucetURL`: `https://faucet.maroo.io`
- `agentWalletKitBaseURL`: `https://agent.maroo.io`
- `docsURL`: `https://docs.maroo.io`

Runtime environment variables used by the maroo demo adapter path:

- `MESHKIT_IOS_MAROO_LIVE_TX_HASH`: required only to present a confirmed live OKRW payment receipt proof.
- `MESHKIT_IOS_MAROO_ANCHOR_TX_HASH`: optional live request-anchor transaction reference.
- `MESHKIT_MAROO_OKRW_CONTRACT_ADDRESS`: optional OKRW contract address for the availability probe.
- `MESHKIT_MAWS_BRIDGE_URL`: optional local HTTP bridge endpoint for DailyMart live M-AWS `transfer.send` execution, for example `http://127.0.0.1:8787/transfer`.
- `MESHKIT_MAWS_AGENT_ID`: required with `MESHKIT_MAWS_BRIDGE_URL`; identifies the M-AWS agent wallet that sends OKRW.
- `WAAS_AUTH_TOKEN` or stored `~/.maroo/credentials.json`: required by the M-AWS MCP server that the bridge calls.
- `MESHKIT_MAWS_AUTHORIZATION`: optional authorization header that DailyMart sends to the bridge.
- `MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_URL`: optional local HTTP bridge endpoint for direct native maroo testnet OKRW transfer execution, for example `http://127.0.0.1:8788/transfer`. When present, DailyMart uses this direct maroo client before the M-AWS bridge.
- `MESHKIT_MAROO_PRIVATE_KEY`: testnet-only EVM private key used by `scripts/maroo_native_okrw_transfer_bridge.mjs`.
- `MESHKIT_MAROO_OKRW_TRANSFER_AUTHORIZATION`: optional authorization header that DailyMart sends to the direct maroo transfer bridge. When set, the bridge requires the exact same header on POST `/transfer`.

MeshKit anchors and proves only provider-neutral commitments: signed MCP request hash, request nonce, policy id, policy hash, anchoring reference, execution status, and transaction/explorer references when a provider returns them. Plaintext cart items, delivery address references, user identity, consent text, and private request payloads must not be placed in maroo transaction metadata or receipt core fields.

If maroo RPC, faucet, explorer, OKRW contract availability, or device signing prevents a live confirmation, the demo must report `BlockedByExternalChain` evidence and must not present a deterministic fallback transaction hash as a confirmed payment. Availability evidence is serialized with a provider-neutral blocker type such as `rpc_unavailable`, `explorer_unavailable`, `faucet_unavailable`, `okrw_contract_unavailable`, or `payment_confirmation_unavailable`, plus the endpoint, operation, observed time, and any signed request hash/nonce/anchoring reference available at the failure boundary.

DailyMart can execute live OKRW transfers through the local M-AWS bridge. The bridge accepts DailyMart's provider-neutral MeshKit execution request, calls M-AWS MCP `transfer.send`, then queries maroo JSON-RPC `eth_getTransactionReceipt` before returning confirmed proof fields. A response with only `txHash` remains `pending`; confirmed DailyMart receipts require `txHash`, `blockHash`, `blockNumber`, `confirmationCount`, and `confirmedAt`.

```bash
WAAS_AUTH_TOKEN=<token> node scripts/maws_transfer_bridge.mjs

MESHKIT_MAWS_BRIDGE_URL=http://127.0.0.1:8787/transfer \
MESHKIT_MAWS_AGENT_ID=<agent-id> \
WAAS_AUTH_TOKEN=<token> \
scripts/install_ios_device.sh
```

If live M-AWS credentials or bridge state are missing, persist explicit blocker evidence:

```bash
python3 scripts/verify_maws_live_readiness.py
```

The script writes `artifacts/maroo-testnet/maws-live-readiness.json` and also probes the real `m-aws serve` stdio MCP surface through `scripts/probe_maws_mcp_stdio.mjs`. A non-ready result is expected to exit non-zero and means the demo must stay pending or failed, not paid or complete. The MCP probe specifically verifies that the server starts with MCP `Content-Length` framing and exposes `transfer.send`; package-startup failures such as missing transitive modules are recorded as `maws_mcp_unavailable`, separately from maroo RPC availability.

The bridge can be contract-tested without credentials by replacing M-AWS and maroo RPC with local fakes:

```bash
node scripts/verify_maws_transfer_bridge_contract.mjs
```

That check proves the HTTP bridge calls MCP `transfer.send`, converts a confirmed maroo receipt into `txHash`, `blockHash`, `blockNumber`, `confirmationCount`, and `confirmedAt`, and preserves `POLICY_REJECTED` without synthesizing a transaction hash. It is not live payment proof. Live proof requires the physical iPad run to capture the same fields from the real bridge response plus an explorer URL under `https://explorer-testnet.maroo.io/tx/`.

To check only the installed M-AWS MCP server surface:

```bash
node scripts/probe_maws_mcp_stdio.mjs
```

The probe writes `artifacts/maroo-testnet/maws-mcp-stdio-probe.json` and passes only when the configured `m-aws serve` command responds to `initialize`/`tools/list` and exposes `transfer.send`.

To capture a live proof artifact from a configured bridge without opening the iPad app:

```bash
MESHKIT_MAWS_BRIDGE_URL=http://127.0.0.1:8787/transfer \
MESHKIT_MAWS_AGENT_ID=<agent-id> \
MESHKIT_MAWS_PROBE_RECIPIENT=0x... \
MESHKIT_MAWS_PROBE_AMOUNT=1 \
node scripts/probe_maws_live_transfer.mjs
```

The probe writes `artifacts/maroo-testnet/maws-live-transfer-proof.json`. It exits successfully only when the bridge returns confirmed maroo proof fields and an explorer URL; otherwise it records `BlockedByExternalChain` evidence so the demo cannot be mistaken for a paid order.

DailyMart can also use a direct maroo testnet OKRW transfer bridge when M-AWS is unavailable. This path signs a native OKRW transfer with a testnet EVM private key, waits for the maroo receipt, and returns the same provider-neutral proof fields. The bridge resolves `ethers` from the repository tool cache and installs it there if missing, without adding a repository dependency:

```bash
MESHKIT_MAROO_PRIVATE_KEY=<testnet-private-key> \
node scripts/maroo_native_okrw_transfer_bridge.mjs

MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_URL=http://127.0.0.1:8788/transfer \
scripts/install_ios_device.sh
```

For a physical iPad, `127.0.0.1` points to the iPad, not the Mac running the bridge. `scripts/install_ios_device.sh` loads `.env.maroo-demo.local` and rewrites loopback bridge URLs to `MESHKIT_IOS_BRIDGE_HOST` for the launched DailyMart app. Set it explicitly when needed:

```bash
MESHKIT_IOS_BRIDGE_HOST=<mac-lan-ip> scripts/install_ios_device.sh
```

The script writes `DailyMart-launch-environment.json` with secret authorization values redacted.

The physical iPad launch environment can be regression-tested without a real device:

```bash
bash scripts/verify_ios_device_maroo_launch_env.sh
```

To capture proof from the direct maroo bridge without opening the iPad app:

```bash
MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_URL=http://127.0.0.1:8788/transfer \
MESHKIT_MAROO_OKRW_PROBE_RECIPIENT=0x... \
MESHKIT_MAROO_OKRW_PROBE_AMOUNT=1 \
node scripts/probe_maroo_native_okrw_transfer.mjs
```

The direct probe writes `artifacts/maroo-testnet/maroo-native-okrw-transfer-proof.json` and succeeds only when the bridge returns confirmed maroo receipt proof fields. The default DailyMart delegated recipient is an EVM address so both M-AWS and direct maroo transfer clients can execute against the same policy-bound recipient.

Direct bridge readiness can be recorded without claiming payment completion:

```bash
python3 scripts/verify_maroo_native_okrw_readiness.py
```

The readiness script writes `artifacts/maroo-testnet/maroo-native-okrw-readiness.json` and exits non-zero until the direct bridge URL and testnet private key path are configured and the bridge health endpoint answers.

The direct bridge contract can be verified without a private key by injecting a fake ethers provider:

```bash
node scripts/verify_maroo_native_okrw_transfer_bridge_contract.mjs
```

That check proves the direct bridge validates EVM recipients, signs through the configured ethers module boundary, maps confirmed, pending, and failed receipts into the same proof contract, and never synthesizes confirmed fields.

To aggregate deterministic checks and live proof availability into a single demo gate:

```bash
python3 scripts/verify_maroo_demo_readiness.py
```

The aggregate writes `artifacts/maroo-testnet/demo-readiness.json`. It includes public maroo endpoint checks, faucet availability/manual-funding readiness, both bridge contract tests, docs/runtime verification, full Swift tests, a DailyMart iPad simulator build, and the DailyMart pending proof UI test. It can report `deterministicReady=true` while still exiting non-zero with `liveConfirmed=false`; that means the demo is ready for dry-run/pending presentation but must not be presented as paid or complete. Set `MESHKIT_IOS_SIMULATOR_DESTINATION` to override the default iPad simulator destination used by this aggregate gate.

For a compact non-secret operator summary:

```bash
node scripts/maroo_demo_operator_status.mjs
```

It writes `artifacts/maroo-testnet/demo-operator-status.json` and `.md` with the signer address, RPC balance, bridge policy status, proof status, and the next command to run. It never prints the private key or authorization token.

The maroo faucet at https://faucet.maroo.io/ is intentionally treated as a wallet-connected manual funding step. `python3 scripts/verify_maroo_faucet_readiness.py` records the faucet page availability and the manual funding instructions in `artifacts/maroo-testnet/faucet-readiness.json`, but it does not automate token requests.

For the fastest hackathon demo path, create a fresh direct maroo testnet wallet and fund it from the faucet:

```bash
node scripts/create_maroo_demo_wallet.mjs
```

This writes an ignored `.env.maroo-demo.local` file containing a testnet-only private key and records the public wallet address in `artifacts/maroo-testnet/demo-wallet.json`. Creating a wallet does not create balance. For a live demo, import that generated testnet-only key into a fresh MetaMask account, connect it to https://faucet.maroo.io/, and request faucet funds for the generated address. Alternatively, create/fund a fresh MetaMask test account first, then copy only that test account private key into `MESHKIT_MAROO_PRIVATE_KEY`. After the wallet is funded, load the env before starting the direct bridge:

```bash
set -a; source .env.maroo-demo.local; set +a
node scripts/maroo_native_okrw_transfer_bridge.mjs
```

For physical iPad access, bind the Mac-side bridge beyond loopback:

```bash
MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_HOST=0.0.0.0 node scripts/maroo_native_okrw_transfer_bridge.mjs
```

Use `MESHKIT_MAROO_OKRW_TRANSFER_AUTHORIZATION` whenever the bridge is reachable off-machine. `node scripts/create_maroo_demo_wallet.mjs` generates this header in `.env.maroo-demo.local` for new demo wallets.

For an existing demo wallet file, add only the bridge authorization without changing the wallet address:

```bash
node scripts/ensure_maroo_bridge_authorization.mjs
```

The bridge can also enforce defense-in-depth spend policy before signing:

- `MESHKIT_MAROO_OKRW_ALLOWED_RECIPIENTS`: comma-separated EVM recipient allowlist.
- `MESHKIT_MAROO_OKRW_TRANSFER_MAX_AMOUNT`: maximum OKRW amount per transfer.

For an existing demo wallet file, add those defaults without changing the wallet address:

```bash
node scripts/ensure_maroo_bridge_policy.mjs
```

In another terminal, with the same env loaded:

```bash
node scripts/probe_maroo_native_okrw_transfer.mjs
python3 scripts/verify_maroo_demo_readiness.py
```

Or run the guarded one-command path after faucet funding:

```bash
node scripts/run_maroo_native_okrw_live_proof.mjs
```

This command loads `.env.maroo-demo.local`, starts the direct bridge if needed, checks the signer balance through maroo RPC, refuses to broadcast when the funded balance is below `MESHKIT_MAROO_OKRW_PROBE_AMOUNT`, then captures the direct proof and reruns aggregate readiness.

To start the command before pressing the faucet button, use the funding wait mode:

```bash
node scripts/run_maroo_native_okrw_live_proof.mjs --wait-for-funding
```

By default it waits up to 300 seconds and polls every 5 seconds. Override those with `MESHKIT_MAROO_WAIT_FOR_FUNDING_SECONDS` and `MESHKIT_MAROO_WAIT_FOR_FUNDING_POLL_SECONDS`.

When `MESHKIT_IOS_BRIDGE_HOST` is present, the guarded runner starts the local direct bridge on `0.0.0.0` unless `MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_HOST` is already set.

The full demo is live only after `artifacts/maroo-testnet/maroo-native-okrw-transfer-proof.json` contains `confirmed=true`, `txHash`, `blockHash`, `blockNumber`, `confirmationCount`, `confirmedAt`, and `explorerUrl`, and `artifacts/maroo-testnet/maroo-native-okrw-proof-verification.json` contains `verified=true` after checking the maroo RPC receipt and explorer URL.

Before funding, verify that the env file private key, faucet address, and bridge sender address all refer to the same test wallet:

```bash
node scripts/verify_maroo_demo_wallet_setup.mjs
```

This writes `artifacts/maroo-testnet/demo-wallet-setup.json` without printing the private key. It passes only when the derived signer address matches `MESHKIT_MAROO_WALLET_ADDRESS` and `MESHKIT_MAROO_FAUCET_WALLET_ADDRESS`, and when the direct bridge URL/probe recipient are configured.

To verify public testnet availability before a live demo:

```bash
python3 scripts/verify_maroo_testnet_status.py

curl -sS https://rpc-testnet.maroo.io \
  -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}'

curl -sS https://rpc-testnet.maroo.io \
  -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":2,"method":"net_version","params":[]}'

MESHKIT_MAROO_OKRW_CONTRACT_ADDRESS=0x... python3 scripts/verify_maroo_testnet_status.py
```

The script writes `artifacts/maroo-testnet/status.json` with the latest public RPC and explorer probe. When `MESHKIT_MAROO_OKRW_CONTRACT_ADDRESS` is set, it also probes OKRW contract bytecode with `eth_getCode` and emits `okrw_contract_unavailable` evidence if no deployed bytecode is returned. Passing this check only proves endpoint availability; a confirmed OKRW payment still requires a funded testnet wallet or Agent Wallet Kit/live adapter path and a real tx hash.

For physical iPad proof, run `scripts/install_ios_device.sh`. If Xcode reports `No Accounts`, `No profiles for ai.meshkit.sample.hermeschat`, or `requires a development team`, sign into Xcode Settings > Accounts and rerun with a valid team, for example:

```bash
DEVELOPMENT_TEAM=<APPLE_TEAM_ID> scripts/install_ios_device.sh
```

Those provisioning failures are device-signing blockers, not confirmed MeshKit runtime failures.
