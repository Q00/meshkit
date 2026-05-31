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

MeshKit anchors and proves only provider-neutral commitments: signed MCP request hash, request nonce, policy id, policy hash, anchoring reference, execution status, and transaction/explorer references when a provider returns them. Plaintext cart items, delivery address references, user identity, consent text, and private request payloads must not be placed in maroo transaction metadata or receipt core fields.

If maroo RPC, faucet, explorer, OKRW contract availability, or device signing prevents a live confirmation, the demo must report `BlockedByExternalChain` evidence and must not present a deterministic fallback transaction hash as a confirmed payment. Availability evidence is serialized with a provider-neutral blocker type such as `rpc_unavailable`, `explorer_unavailable`, `faucet_unavailable`, `okrw_contract_unavailable`, or `payment_confirmation_unavailable`, plus the endpoint, operation, observed time, and any signed request hash/nonce/anchoring reference available at the failure boundary.

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
