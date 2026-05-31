import CryptoKit
import XCTest
@testable import MeshKit

final class MeshRequestAnchorReferenceSigningModuleTests: XCTestCase {
    private let signingKey = Curve25519.Signing.PrivateKey()

    func testSignsProviderNeutralAnchoredMCPRequestReferenceWithoutWalletProviderDependency() throws {
        let identity = try chainProviderIdentity(providerName: "Demo-Chain")
        let referenceOutput = try referenceOutput(identity: identity)
        let signer = MeshRequestSigner.ed25519(keyId: "hermes-reference-anchor-key", privateKey: signingKey)
        let module = MeshRequestAnchorReferenceSigningModule(
            configuration: try MeshChainProviderConfiguration(
                identity: identity,
                capabilities: [.createRequestAnchorReference, .signRequestAnchorReference]
            ),
            signer: signer
        )

        let signedReference = try module.signReference(referenceOutput)
        let signatureData = try XCTUnwrap(Data(base64Encoded: signedReference.signature.value))

        XCTAssertEqual(signedReference.signature.algorithm, "Ed25519")
        XCTAssertEqual(signedReference.signature.keyId, "hermes-reference-anchor-key")
        XCTAssertEqual(signedReference.anchoringReference, referenceOutput.anchoringReference)
        XCTAssertEqual(signedReference.requestHash, referenceOutput.requestHash)
        XCTAssertEqual(signedReference.requestNonce, referenceOutput.requestNonce)
        XCTAssertEqual(signedReference.providerMetadata, identity.metadata)
        XCTAssertTrue(signedReference.canonicalString.contains("provider=demo-chain"))
        XCTAssertTrue(signedReference.canonicalString.contains("anchorId=request-anchor-sha256-"))
        XCTAssertTrue(signedReference.canonicalString.contains("requestNonce=nonce-anchor-reference-signing-001"))
        XCTAssertTrue(signingKey.publicKey.isValidSignature(signatureData, for: signedReference.input.data))
    }

    func testReferenceSigningRequiresAdvertisedProviderNeutralCapability() throws {
        let identity = try chainProviderIdentity(providerName: "Demo-Chain")
        let signer = MeshRequestSigner.ed25519(keyId: "hermes-reference-anchor-key", privateKey: signingKey)
        let module = MeshRequestAnchorReferenceSigningModule(
            configuration: try MeshChainProviderConfiguration(
                identity: identity,
                capabilities: [.createRequestAnchorReference]
            ),
            signer: signer
        )

        XCTAssertThrowsError(try module.signReference(referenceOutput(identity: identity))) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }
    }

    func testReferenceSigningRejectsProviderMetadataMismatchBeforeSigning() throws {
        let identity = try chainProviderIdentity(providerName: "Demo-Chain")
        let otherIdentity = try chainProviderIdentity(providerName: "Other-Chain")
        let signer = MeshRequestSigner.ed25519(keyId: "hermes-reference-anchor-key", privateKey: signingKey)
        let module = MeshRequestAnchorReferenceSigningModule(
            configuration: try MeshChainProviderConfiguration(
                identity: otherIdentity,
                capabilities: [.signRequestAnchorReference]
            ),
            signer: signer
        )

        XCTAssertThrowsError(try module.signReference(referenceOutput(identity: identity))) { error in
            XCTAssertEqual(
                error as? MeshKitValidationError,
                .signatureMismatch("request anchor reference signing provider metadata mismatch")
            )
        }
    }

    func testSignedReferenceEnvelopeRejectsEmptySignatureValue() throws {
        let identity = try chainProviderIdentity(providerName: "Demo-Chain")
        let input = try MeshRequestAnchorReferenceSigningInput(referenceOutput: referenceOutput(identity: identity))

        XCTAssertThrowsError(try MeshSignedRequestAnchorReference(
            input: input,
            signature: MeshSignature(algorithm: "Ed25519", keyId: "anchor-key", value: "")
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProviderIdentity("signature.value"))
        }
    }

    private func referenceOutput(identity: MeshChainProviderIdentity) throws -> MeshRequestAnchorReferenceCreationOutput {
        let metadata = try MeshSignedRequestAnchorMetadata(
            requestId: "ios-grocery-anchor-reference-signing-001",
            nonce: "nonce-anchor-reference-signing-001",
            timestamp: "2026-05-31T12:20:00Z",
            callerAppId: "app.hermes-chat",
            callerBundleId: "ai.meshkit.sample.hermeschat",
            targetBundleId: "ai.meshkit.sample.dailymart",
            capabilityId: "grocery.purchase_essentials",
            payloadHash: MeshPayloadHash(value: String(repeating: "a", count: 64)),
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "hermes-reference-anchor-key",
                value: "signature-anchor-reference-signing-001"
            ),
            signedRequestHash: MeshPayloadHash(value: String(repeating: "b", count: 64))
        )
        return try MeshRequestAnchorReferenceCreationModule(
            configuration: MeshChainProviderConfiguration(
                identity: identity,
                capabilities: [.createRequestAnchorReference]
            )
        ).createReference(metadata: metadata)
    }

    private func chainProviderIdentity(providerName: String) throws -> MeshChainProviderIdentity {
        try MeshChainProviderIdentity(
            providerName: providerName,
            networkIdentity: "Demo-Testnet",
            chainId: "Demo-Testnet-1",
            rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc.\(providerName.lowercased()).example.invalid")),
            explorerBaseURL: try XCTUnwrap(URL(string: "https://explorer.\(providerName.lowercased()).example.invalid"))
        )
    }
}
