# AgentOS Trust Layer

MeshKit is the seed of an AgentOS trust layer: an app call graph where each participating app can verify, consent, execute, and prove what happened.

## Layers

1. **Open Calling Graph**
   - App capability manifests.
   - Risk class and consent policy.
   - Verification keys and callback metadata.

2. **App-to-App MCP envelope**
   - Canonical request signing.
   - Payload hash, nonce, timestamp, caller identity, target capability, and signature.
   - Deterministic validation before target business logic.

3. **Target app execution boundary**
   - The target app owns user consent.
   - The target app validates budget and replay policy.
   - The target app executes its own handler.

4. **Receipt and audit layer**
   - Target-signed receipt.
   - Caller-side receipt verification.
   - Optional blockchain anchoring for registry state, revocation, and receipt hashes.

## iPad proof path

The iPad proof starts with a small but complete flow:

```text
HermesChat
  -> OCG discovery
  -> DailyMart foreground consent with ₩100 limit
  -> HermesChat foreground background-MCP progress
  -> DailyMart target-signed receipt
  -> HermesChat verified completion
```

## Production boundary

Physical-device proof is a preview milestone. Production requires persistent registry operations, key rotation, revocation, status reporting, and a public audit/control-plane path.
