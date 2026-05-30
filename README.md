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
