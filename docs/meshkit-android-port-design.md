# MeshKit Android Port — Design (Phase 1: Signed Intent Mesh, Phase 2: AppFunctions Contribution)

Status: draft for implementation kickoff (2026-08-24)

## Goal

Port the MeshKit app-to-app MCP trust layer to Android with full wire
compatibility, using the transport Android actually gives cooperating apps
today, and publish MeshKit target capabilities into the Android 16
AppFunctions registry so platform assistants can discover them.

- **Phase 1** — MeshKit-Android SDK: the signed MCP envelope carried over an
  explicit Intent round-trip (`startActivityForResult`), OCG discovery, TEE
  (Android Keystore) Ed25519 signing, target-owned receipts, and a
  `ROLE_ASSISTANT` agent surface for the Hermes agent app.
- **Phase 2** — AppFunctions contribution: target apps additionally register
  their MeshKit capabilities as `androidx.appfunctions` app functions so the
  platform assistant (Gemini) can call them. MeshKit stays the trust layer
  above the OS registry, not a competing transport.

## Non-Goals

- Executing other apps' AppFunctions ourselves (`EXECUTE_APP_FUNCTIONS` is
  internal/privileged; requires an OEM priv-app deal — out of scope here).
- Accessibility-based autonomous automation (prohibited by Play policy for
  non-accessibility tools).
- AOSP fork or privileged system service (separate track; this SDK is its
  userland reference).
- Chain anchoring / Agent Wallet Kit parity (Phase 3; the envelope and receipt
  formats already carry the hooks).

## Wire Compatibility Contract

The Android SDK speaks the exact byte formats the Swift SDK signs and
verifies. These identifiers are frozen:

| Contract | Version string |
|---|---|
| Request signing input | `meshkit-request-signing/v1` (12 newline-joined fields, see `MeshRequest.signingInputData()`) |
| Nonce-bound payload hash | `meshkit-payload-hash/v1` (canonical `key=value&...` with percent-escaping to alphanumerics, sorted keys) |
| Target receipt signing input | `meshkit-target-receipt-signing/v1` |
| Envelope encoding | JSON with sorted keys, base64; carried as `mesh_request` / `mesh_receipt` |
| Signature algorithm | `Ed25519`, raw 32-byte public keys, hex/base64 per existing trust metadata |

Cross-platform equivalence is enforced by **golden vectors generated from the
Swift SDK** (`meshkit-android/vectors/wire-compat.v1.json`, produced by
`scripts/wire_vectors_gen`, orchestrated by
`scripts/verify_android_wire_compat.sh`). The Kotlin test suite must
reproduce every canonical string, hash, and signing input byte-for-byte and
verify every Swift Ed25519 signature; the script's cross-verify step then has
the Swift SDK verify Kotlin-signed envelopes. Signature bytes are never
compared directly — CryptoKit emits randomized Ed25519 signatures (JCA is
RFC 8032 deterministic), so equivalence is proven by mutual verification over
identical signing inputs. Any change to the vectors is a wire-format change
and needs both SDKs updated in the same commit.

**Ed25519 on Android**: `java.security.Signature.getInstance("Ed25519")` is
available on JDK ≥15 for JVM tests. On device, Android Keystore supports
Curve 25519 from API 33 (Android 13): generate with
`KeyPairGenerator("EC", "AndroidKeyStore")` +
`ECGenParameterSpec("ed25519")`, `PURPOSE_SIGN`. Keys are TEE-backed and
non-exportable; StrongBox support for Ed25519 is device-dependent, so
`setIsStrongBoxBacked(true)` is attempted and falls back to TEE. Key
attestation certificates are recorded alongside OCG trust metadata
(`request_signer` / `receipt_signer`) so registry consumers can verify
hardware residency. minSdk is therefore **33**.

## Module Layout

```text
meshkit-android/
  settings.gradle.kts
  build.gradle.kts
  vectors/wire-compat.v1.json          # generated from Swift, checked in
  meshkit-core/                        # pure Kotlin/JVM, no Android deps
    src/main/kotlin/ai/meshkit/core/
      MeshIdentity.kt                  # appId, installId, bundleId, publicKeyId
      MeshCapability.kt                # targetBundleId, capabilityId, version
      MeshSignature.kt                 # algorithm, keyId, value
      MeshPayloadHash.kt               # + MeshRequestPayloadHasher (canonical form, nonce-bound)
      MeshRequest.kt                   # signingInputData(), base64 envelope encode/decode
      MeshReceipt.kt                   # target-owned receipt + signingInputData()
      MeshTrust.kt                     # MeshTargetPolicy, MeshSenderTrust, MeshInvocationPolicy, MeshAuditEvent
      MeshValidationException.kt       # mirrors MeshKitValidationError cases
      MeshSignedRequestCrypto.kt       # sign/verify facade; Signer/Verifier interfaces
      Ed25519Jvm.kt                    # java.security-based signer/verifier (JVM + device)
      OpenCapabilityGraph.kt           # OCG model incl. android bindings; ACP descriptor projection
    src/test/kotlin/                   # golden-vector tests + policy/validation unit tests
  meshkit-transport-intent/            # Android library (minSdk 33)
    src/main/kotlin/ai/meshkit/transport/
      MeshIntentContract.kt            # action/extras constants (below)
      MeshCaller.kt                    # ActivityResultContract<MeshRequest, MeshReceiptResult>
      MeshTargetActivityDelegate.kt    # decode -> observe caller -> verify -> consent -> execute -> setResult
      CallerIdentityObserver.kt        # getCallingPackage() + PackageManager signing-cert SHA-256
  meshkit-appfunctions/                # Android library (Phase 2, androidx.appfunctions alpha)
    src/main/kotlin/ai/meshkit/appfunctions/
      MeshAppFunctionBridge.kt         # OCG capability -> @AppFunction adapter, trust-class gating
  samples/
    hermeschat/                        # agent app: ROLE_ASSISTANT + MeshCaller
    mintnotes/                         # target: notes.append_note
    dailymart/                         # target: grocery.purchase_essentials (budget-gated consent)
```

`meshkit-core` has no Android dependency so the wire contract is testable on
any JVM (CI does not need an emulator for the trust layer).

## Phase 1 — Signed Intent Transport

### Invocation contract

The OCG manifests already declare the Android binding
(`ocg/registry/dailymart.ocg.json`):

```json
"android": {
  "action": "ai.meshkit.action.INVOKE_CAPABILITY",
  "target_activity": "ai.meshkit.sample.dailymart.PurchaseInvokeActivity"
}
```

Caller side (`MeshCaller`):

1. Build and sign a `MeshRequest` (same 12-field signing input as iOS).
2. Explicit intent: `setClassName(targetPackage, targetActivity)`,
   `setAction("ai.meshkit.action.INVOKE_CAPABILITY")`, extra
   `mesh_request` = the base64 sorted-keys JSON envelope (identical bytes to
   the iOS `mesh_request` query parameter).
3. Launch via `startActivityForResult` (wrapped as an
   `ActivityResultContract`), await the result.
4. Decode `mesh_receipt` from the result intent; run the same receipt
   verification as `HermesChat` on iOS (target-signed, correlated by
   `requestId` + `requestPayloadHash`, target-owned keys only).

Result codes: `RESULT_OK` + `mesh_receipt` (receipt may itself carry status
`completed` / `failed` / `policy_denied`); `RESULT_CANCELED` without a receipt
means user dismissal before consent — never treated as completion.

Target side (`MeshTargetActivityDelegate`), fail-closed and in this order
(mirrors `MeshSignedMCPRequestVerifier`):

1. Decode envelope; reject malformed base64/JSON.
2. **Observed caller identity**: `getCallingPackage()` (non-null only for
   `startActivityForResult` callers — reject otherwise) must match
   `caller.bundleId`, and the caller package's signing certificate SHA-256
   (via `PackageManager.getPackageInfo(..., GET_SIGNING_CERTIFICATES)`) must
   match `package_signature_sha256` in OCG trust metadata. This is strictly
   stronger than the iOS "observed caller bundle" claim — Android gives the
   target a kernel-verified caller identity, upgrading
   `observedCallerBundleMismatch` from claim-check to proof-check.
3. Verify target policy, trusted caller app id, signature algorithm/key id
   against OCG trust metadata, payload hash (nonce-bound), timestamp
   freshness, nonce replay reservation.
4. Verify the Ed25519 signature over `signingInputData()`.
5. `MeshInvocationPolicy.validateBeforeExecution` — consent + budget gates
   (`spend:money` requires approved budget; DailyMart demo keeps the ₩100
   cap), production kill switch.
6. Execute the target-owned handler, mint the target-signed `MeshReceipt`
   with a Keystore-resident receipt key, `setResult(RESULT_OK, ...)`,
   `finish()`.

Every repeat invocation gets a fresh requestId/nonce/signature/receiptId —
same rule as the iOS saved-grant flow.

### Discovery

Same OCG registry (`ocg/registry/signed/*.signed.ocg.json`) and ACP surface
(`GET /api/acp/apps`). `OpenCapabilityGraph.acpRegistryDescriptors()` gains
`mcpTransport: "app-to-app-intent"` and `platform: "android-demo"` for
entries carrying an `android` binding. On-device, callers declare targets in
the manifest with `<queries>` (specific `package` entries — no
`QUERY_ALL_PACKAGES`), which replaces the iOS `LSApplicationQueriesSchemes`
cap; registry-driven server-side discovery remains the primary path.

### Agent surface (HermesChat-Android)

- Requests `ROLE_ASSISTANT` via `RoleManager.createRequestRoleIntent` — the
  Play-legal agent slot (the Perplexity/ChatGPT path). The role provides the
  assist gesture entry point and, with a `VoiceInteractionService`,
  foreground screen context; it is **not** used for input injection and does
  not unlock AppFunctions execution.
- All actual invocation goes through the signed intent mesh above; the
  assistant role is presentation and entry point only, so the sample runs
  fine without the role granted.

## Phase 2 — AppFunctions Contribution

Target apps additionally publish capabilities into the OS registry with
`androidx.appfunctions` (`@AppFunction` in an `AppFunctionService`; schema
generated by KSP, indexed via AppSearch). Google's framing is "a local
implementation of MCP"; the caller is the privileged platform assistant.

`MeshAppFunctionBridge` rules:

- One generated app function per OCG capability, parameters/result mapped
  from `input_schema` / `result_schema`.
- The app-function execution path routes into the **same target-owned
  handler and consent gates** as the intent path, but under a distinct
  caller trust class `platform_assistant`: there is no MeshKit-signed
  request, so the bridge synthesizes an audit-only envelope (no
  `MeshSignature`) and the receipt records
  `callerTrustClass: "platform_assistant"`.
- **`spend:money` capabilities are not exposed via AppFunctions.** Without a
  signed request and budget mandate there is no trust object to anchor a
  payment to; DailyMart exposes at most a draft-cart function
  (`grocery.prepare_essentials_cart`, risk `read_only`) whose confirmation
  still requires the signed intent path. Risk classes `read_only` and
  `write:user_content` (with per-invocation consent UI in the target) are
  eligible.
- The bridge still mints a target-signed receipt for every executed app
  function, so the audit layer stays uniform across transports.

This keeps the strategic position: Gemini can call MeshKit targets, and the
delta MeshKit adds over the bare OS registry — signed requests, budget
mandates, target-owned receipts — stays visible in the artifacts.

## Verification

- `meshkit-core` JVM tests: golden-vector equivalence (canonical payload
  data, nonce-bound hashes, signing inputs, Ed25519 verify against
  Swift-produced signatures), plus ports of the trust-layer unit tests
  (policy gates, replay, tampered payloads, wrong signer key).
- `scripts/generate_wire_vectors.swift` — regenerates
  `vectors/wire-compat.v1.json` from the Swift SDK; CI check fails if the
  checked-in vectors drift from Swift output.
- Instrumented tests (emulator/redroid, arm64): caller-identity observation,
  full HermesChat → DailyMart round trip with consent + receipt
  verification, repeat-grant freshness.
- `scripts/verify_android_scaffold.py` mirrors the iOS verify scripts.

## Milestones

1. **M1 (this kickoff)**: design doc, golden vectors generated from Swift,
   `meshkit-core` implemented with vector tests passing on JVM.
2. **M2**: `meshkit-transport-intent` + three sample apps; e2e on
   emulator/redroid; DailyMart ₩100 consent gate on Android.
3. **M3**: `meshkit-appfunctions` bridge behind a build flag (androidx
   appfunctions is alpha; pin the version, isolate the dependency), draft-cart
   function for DailyMart, Gemini/trusted-tester validation when available.
4. **M4**: key attestation recorded into OCG trust metadata; registry/ACP
   descriptors annotated with android transport; docs + runnable doc checks.
