# MeshKit Android

Android port of the MeshKit app-to-app MCP trust layer. Design:
`docs/meshkit-android-port-design.md`. Wire-compatible with the Swift SDK —
same signing inputs (`meshkit-request-signing/v1`,
`meshkit-target-receipt-signing/v1`), same nonce-bound canonical payload hash
(`meshkit-payload-hash/v1`), same base64 sorted-keys JSON envelopes, Ed25519
with raw public keys.

## Modules

- `meshkit-core` — pure Kotlin/JVM trust layer: envelopes, canonicalization,
  target-side fail-closed validation, consent/budget policy, target-owned
  receipts, OCG/ACP models, and the Phase 2 AppFunctions exposure gate
  (`MeshAppFunctionGate` — `spend:money` is never published to the platform
  assistant). No Android dependency; tests run on any JDK 17+.
- `meshkit-transport-intent` — Android library (minSdk 33): the signed MCP
  envelope over an explicit-intent `startActivityForResult` round-trip
  (`MeshCaller` / `MeshTargetActivityDelegate`), with kernel-verified caller
  identity (`getCallingPackage()` + signing-cert SHA-256 against the OCG
  `package_signature_sha256` pin). Included only when an Android SDK is
  available (`ANDROID_HOME` or `local.properties`).

## Verify

```bash
# Kotlin trust-layer tests (JVM only, no Android SDK needed)
cd meshkit-android && gradle :meshkit-core:test

# Mutual Swift <-> Kotlin wire-compat proof
scripts/verify_android_wire_compat.sh
```

The wire-compat script (1) regenerates the golden vectors from the Swift SDK
(`scripts/wire_vectors_gen`) and fails on drift of any deterministic field,
(2) runs the Kotlin tests, which reproduce every canonical form byte-for-byte
and verify the Swift signatures, and (3) has the Swift SDK verify
Kotlin-signed request and receipt envelopes. Signature bytes are not compared
directly: CryptoKit emits randomized Ed25519 signatures, so the
cross-implementation proof is mutual verification over identical signing
inputs.
