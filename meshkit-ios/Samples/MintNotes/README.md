# MintNotes iOS sample

MintNotes iOS is the target-side demo for MeshKit Swift. It owns the `notes.append_note` capability, receives a `mintnotes://mesh/invoke?...` request, validates the caller, shows consent, appends text through its own internal app logic, and returns a callback result to HermesChat.

Capability:

```text
id: notes.append_note
risk: write:user_content
consent: per_invocation
input: note_ref, text
result: status, note_ref, audit_id
```

## Target responsibilities

MintNotes is the authority for execution. HermesChat can request `notes.append_note`, but MintNotes decides whether to run it.

The production target path should be:

```text
1. Decode mesh_request from URL
2. Validate MeshTargetPolicy
3. Bind caller app id, caller bundle claim, and observed caller bundle
4. Verify payload hash, timestamp freshness, nonce replay, and request signature metadata
5. Validate registry trust and risk/consent policy
6. Ask user for per-invocation consent
7. Call internal note append logic
8. Return structured callback and audit event
```

Swift anchor:

```swift
let audit = try MeshTarget.validatePublicMesh(
    request: request,
    policy: MeshTargetPolicy(
        allowedCallerAppId: "app.hermes-chat",
        targetBundleId: "ai.meshkit.sample.mintnotes",
        capabilityId: "notes.append_note"
    ),
    trust: MeshSenderTrust(
        callerAppId: "app.hermes-chat",
        callerBundleId: "ai.meshkit.sample.hermeschat",
        teamId: "DEVTEAMID",
        requestSigningAlgorithm: "Ed25519",
        requestSigningKeyId: "demo-key",
        publicKey: "BASE64_PUBLIC_KEY"
    ),
    invocationPolicy: MeshInvocationPolicy(
        risk: "write:user_content",
        consent: "per_invocation",
        userApproved: true,
        registrySignatureVerified: true
    ),
    observedCallerBundleId: "ai.meshkit.sample.hermeschat",
    replayCache: replayCache
)

// App-owned business logic boundary.
notesStore.append(noteRef: request.payload["note_ref"]!, text: request.payload["text"]!)
```

## Demo vs production

The visual sample uses demo signature values so the simulator flow can be shown without real key material. Production targets must fail closed on identity mismatch, observed bundle mismatch, stale timestamps, replayed nonces, bad payload hashes, invalid signatures, missing registry trust, consent denial, or budget violations.

Do not paste private keys, app signing material, wallet credentials, or production secrets into manifests, sample apps, docs, or chats. MeshKit trust metadata should contain public values only: app ID, bundle ID, Team ID, signing key ID, algorithm, public key, and verification state.
