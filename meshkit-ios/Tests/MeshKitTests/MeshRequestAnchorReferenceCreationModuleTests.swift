import CryptoKit
import XCTest
@testable import MeshKit

final class MeshRequestAnchorReferenceCreationModuleTests: XCTestCase {
    private let signer = MeshRequestSigner(algorithm: "Ed25519", keyId: "hermes-anchor-create-key") { data in
        Data(SHA256.hash(data: data))
    }

    func testCreatesProviderNeutralAnchoredMCPRequestReferenceFromNormalizedMetadata() throws {
        let identity = try chainProviderIdentity()
        let metadata = try normalizedMetadataWithUppercaseHash()
        let configuration = try MeshChainProviderConfiguration(
            identity: identity,
            capabilities: [.createRequestAnchorReference]
        )
        let module = MeshRequestAnchorReferenceCreationModule(configuration: configuration)
        let input = try MeshRequestAnchorReferenceCreationInput(
            metadata: metadata,
            providerIdentity: identity
        )

        let output = try module.createReference(input)

        XCTAssertEqual(input.requestHash.algorithm, "sha256")
        XCTAssertEqual(input.requestHash.value, metadata.signedRequestHash.value.lowercased())
        XCTAssertEqual(output.requestHash, input.requestHash)
        XCTAssertEqual(output.requestNonce, metadata.nonce)
        XCTAssertEqual(output.providerMetadata, identity.metadata)
        XCTAssertEqual(output.anchoringReference.identity.metadata, identity.metadata)
        XCTAssertEqual(
            output.anchoringReference.anchorId,
            "request-anchor-sha256-\(metadata.signedRequestHash.value.lowercased())"
        )
        XCTAssertNil(output.anchoringReference.transactionHash)
        XCTAssertNil(output.anchoringReference.explorerURL)
        XCTAssertTrue(input.canonicalString.contains("provider=demo-chain"))
        XCTAssertTrue(input.canonicalString.contains("requestNonce=nonce-anchor-create-normalized-001"))
        XCTAssertTrue(input.canonicalString.contains("signedRequestHashValue=\(metadata.signedRequestHash.value.lowercased())"))
    }

    func testCreateReferenceFromRequestMatchesCanonicalSignedRequestHash() throws {
        let identity = try chainProviderIdentity()
        let request = try signedDailyMartRequest()
        let module = MeshRequestAnchorReferenceCreationModule(
            configuration: try MeshChainProviderConfiguration(
                identity: identity,
                capabilities: [.createRequestAnchorReference]
            )
        )

        let output = try module.createReference(request: request)
        let requestHash = try MeshRequestAnchorCanonicalization.signedRequestHash(for: request)

        XCTAssertEqual(output.requestHash, requestHash)
        XCTAssertEqual(output.requestNonce, request.nonce)
        XCTAssertEqual(
            output.anchoringReference,
            try MeshRequestAnchorCanonicalization.anchoringReference(
                forSignedRequestHash: requestHash,
                providerIdentity: identity
            )
        )
    }

    func testCreatesDeterministicReferenceLinkingRequestNoncePolicyProviderAndStatus() throws {
        let identity = try chainProviderIdentity()
        let request = try signedDailyMartRequest()
        let policy = try DailyMartDelegatedSpendingPolicy.expectedPolicy()
        let metadata = try MeshSignedRequestAnchorMetadata(request: request)
        let payload = try MeshRequestAnchorPayload(
            metadata: metadata,
            policyId: policy.policyId,
            policyHash: policy.policyHash
        )
        let module = MeshRequestAnchorReferenceCreationModule(
            configuration: try MeshChainProviderConfiguration(
                identity: identity,
                capabilities: [.createRequestAnchorReference]
            )
        )

        let first = try module.createReference(payload: payload, status: .pending)
        let second = try module.createReference(request: request, policy: policy, status: .pending)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.requestHash, try MeshRequestAnchorCanonicalization.signedRequestHash(for: request))
        XCTAssertEqual(first.requestNonce, request.nonce)
        XCTAssertEqual(first.policyId, policy.policyId)
        XCTAssertEqual(first.policyHash, policy.policyHash)
        XCTAssertEqual(first.providerMetadata, identity.metadata)
        XCTAssertEqual(first.anchoringReference.identity.metadata, identity.metadata)
        XCTAssertEqual(first.status, .pending)
        XCTAssertTrue(first.canonicalString.contains("requestNonce=nonce-anchor-create-001"))
        XCTAssertTrue(first.canonicalString.contains("policyId=\(policy.policyId)"))
        XCTAssertTrue(first.canonicalString.contains("policyHashValue=\(policy.policyHash.value)"))
        XCTAssertTrue(first.canonicalString.contains("status=pending"))
        XCTAssertNoThrow(try first.validate())
    }

    func testReferenceCreationRequiresAdvertisedCapability() throws {
        let identity = try chainProviderIdentity()
        let metadata = try MeshSignedRequestAnchorMetadata(request: signedDailyMartRequest())
        let module = MeshRequestAnchorReferenceCreationModule(
            configuration: try MeshChainProviderConfiguration(
                identity: identity,
                capabilities: [.anchorSignedRequest]
            )
        )

        XCTAssertThrowsError(try module.createReference(metadata: metadata)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }
    }

    func testDemoRequestAnchorProviderAdvertisesReferenceCreationCapability() throws {
        let provider = try MeshDemoRequestAnchorProvider(identity: chainProviderIdentity())
        let module = try MeshRequestAnchorReferenceCreationModule(provider: provider)
        let output = try module.createReference(metadata: MeshSignedRequestAnchorMetadata(request: signedDailyMartRequest()))

        XCTAssertTrue(provider.capabilities.contains(.createRequestAnchorReference))
        XCTAssertEqual(output.anchoringReference.identity.metadata, provider.identity.metadata)
    }

    private func normalizedMetadataWithUppercaseHash() throws -> MeshSignedRequestAnchorMetadata {
        try MeshSignedRequestAnchorMetadata(
            requestId: "ios-grocery-anchor-create-normalized-001",
            nonce: "nonce-anchor-create-normalized-001",
            timestamp: "2026-05-31T12:10:00Z",
            callerAppId: "app.hermes-chat",
            callerBundleId: "ai.meshkit.sample.hermeschat",
            targetBundleId: "ai.meshkit.sample.dailymart",
            capabilityId: "grocery.purchase_essentials",
            payloadHash: MeshPayloadHash(
                algorithm: "SHA256",
                value: String(repeating: "A", count: 64)
            ),
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "hermes-anchor-create-key",
                value: "signature-anchor-create-normalized-001"
            ),
            signedRequestHash: MeshPayloadHash(
                algorithm: "SHA256",
                value: String(repeating: "B", count: 64)
            )
        )
    }

    private func signedDailyMartRequest() throws -> MeshRequest {
        try MeshSignedRequestBuilder(
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ipad-device",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "hermes-anchor-create-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                version: "1.0"
            ),
            signer: signer
        ).makeRequest(
            requestId: "ios-grocery-anchor-create-001",
            payload: [
                "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6",
                "address_ref": "home.saved",
                "budget_krw": "100",
                "policyId": DailyMartDelegatedSpendingPolicy.policyId,
                "policyHash": DailyMartDelegatedSpendingPolicy.policyHash.value
            ],
            nonce: "nonce-anchor-create-001",
            timestamp: "2026-05-31T12:10:00Z"
        )
    }

    private func chainProviderIdentity() throws -> MeshChainProviderIdentity {
        try MeshChainProviderIdentity(
            providerName: "Demo-Chain",
            networkIdentity: "Demo-Testnet",
            chainId: "Demo-Testnet-1",
            rpcEndpoint: try XCTUnwrap(URL(string: "https://RPC.demo-chain.example.invalid/")),
            explorerBaseURL: try XCTUnwrap(URL(string: "https://Explorer.demo-chain.example.invalid/"))
        )
    }
}
