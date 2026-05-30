#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[1]
required = {
    "meshkit-ios/Package.swift": ["MeshKit", "library"],
    "meshkit-ios/Sources/MeshKit/MeshRequest.swift": ["public struct MeshRequest", "payloadHash", "decodedFromURLScheme", "nonce", "signature"],
    "meshkit-ios/Sources/MeshKit/MeshTarget.swift": ["validateSecure", "validatePublicMesh", "verifyPayloadHash", "MeshReplayCache"],
    "meshkit-ios/Sources/MeshKit/MeshTrust.swift": ["MeshSenderTrust", "MeshInvocationPolicy", "MeshAuditEvent", "teamId"],
    "meshkit-ios/Sources/MeshKit/OpenCapabilityGraph.swift": ["OpenCapabilityGraph", "notes.append_note", "write:user_content", "inputSchema"],
    "meshkit-ios/Samples/HermesChat/README.md": ["HermesChat iOS", "MintNotes", "payload hash", "callback"],
    "meshkit-ios/Samples/MintNotes/README.md": ["MintNotes iOS", "validatePublicMesh", "consent", "append_note", "Production targets must fail closed"],
    "meshkit-ios/Samples/iOSDemo/HermesChat/HermesChatApp.swift": ["MeshURLRouter.invokeURL", "MeshSignedRequestBuilder", "SampleMeshSigningKey", "ISO8601DateFormatter", "UUID"],
    "meshkit-ios/Samples/iOSDemo/MintNotes/MintNotesApp.swift": ["MeshProductionTarget", "observedCallerBundleId", "appendStoredNote"],
}
for rel, needles in required.items():
    path = root / rel
    assert path.exists(), f"missing {rel}"
    text = path.read_text()
    for needle in needles:
        assert needle in text, f"{rel} missing {needle}"
print("iOS scaffold verification passed")
