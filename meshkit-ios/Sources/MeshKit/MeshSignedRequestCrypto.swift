import Foundation

/// Provider-neutral signing facade for App-to-App MCP requests.
///
/// Chain anchors and payment proofs may reference the request hash later, but
/// this module signs and verifies the nonce-bound MeshRequest trust object
/// itself.
public enum MeshSignedRequestCrypto {
    public static func makeSignature(
        for request: MeshRequest,
        signer: MeshRequestSigner
    ) throws -> MeshSignature {
        try signer.sign(request).signature
    }

    public static func sign(
        _ request: MeshRequest,
        signer: MeshRequestSigner
    ) throws -> MeshRequest {
        try signer.sign(request)
    }

    public static func verifySignature(
        for request: MeshRequest,
        trust: MeshSenderTrust
    ) throws {
        try MeshTarget.verifyRequiredSignature(request, trust: trust)
    }
}
