# HermesChat iOS sample

HermesChat iOS is the caller-side demo for MeshKit Swift. It looks like a chat assistant discovering MintNotes through the Open Calling Graph, building a signed `MeshRequest`, opening a `mintnotes://mesh/invoke?...` URL, and receiving a `meshkit-hermes://callback?...` result into Hermes Hub.

Expected demo flow:

```text
HermesChat iOS
  → OCG discovery: notes.append_note
  → MeshRequest envelope with payload hash, nonce, timestamp, and signature metadata
  → mintnotes://mesh/invoke?mesh_request=...
  → MintNotes consent screen
  → target-owned append note logic
  → meshkit-hermes://callback
  → Hermes Hub audit
```

## Caller responsibilities

HermesChat must not hardcode arbitrary app control. The caller-side app should:

1. Find a capability from OCG metadata.
2. Match the payload against the declared input schema.
3. Build a `MeshRequest` with caller identity, target capability, payload, payload hash, nonce, timestamp, and signature metadata.
4. Use the target's URL scheme from the capability metadata.
5. Treat success, denial, malformed callback, and validation failure as first-class outcomes.
6. Record callback/audit facts in Hermes Hub.

Swift anchor:

```swift
let capability = OpenCapabilityGraph.mintNotesSample.findCapability("notes.append_note")
let caller = MeshIdentity(
    appId: "app.hermes-chat",
    installId: "ios-sim",
    bundleId: "ai.meshkit.sample.hermeschat",
    publicKeyId: "demo-key"
)
let target = MeshCapability(
    targetBundleId: "ai.meshkit.sample.mintnotes",
    capabilityId: capability?.id ?? "notes.append_note",
    version: "1.0"
)
let request = MeshRequest(
    requestId: "ios-demo-001",
    caller: caller,
    target: target,
    payload: ["note_ref": "ios:mint:demo", "text": "Ship MeshKit iOS demo with OCG discovery."],
    nonce: UUID().uuidString,
    timestamp: ISO8601DateFormatter().string(from: Date()),
    signature: MeshSignature(algorithm: "Ed25519", keyId: "demo-key", value: "demo-signature")
)
```

## iOS-specific note

The current sample uses URL scheme handoff for MVP parity. Future iOS production paths can move the same envelope and validation model behind App Intents, Universal Links, or a relay, but the product boundary stays the same: target app opt-in, target validation, target consent, target-owned execution.
