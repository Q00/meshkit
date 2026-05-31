import CryptoKit
import XCTest
@testable import MeshKit

final class MeshRequestAnchoringReferenceTests: XCTestCase {
    private let signer = MeshRequestSigner(algorithm: "Ed25519", keyId: "hermes-anchor-reference-key") { data in
        Data(SHA256.hash(data: data))
    }

    func testSubmitAnchorAcceptsProviderNeutralSDKInputForValidPayload() async throws {
        let request = try signedDailyMartRequest()
        let providerIdentity = try chainProviderIdentity()
        let provider = try MeshDemoRequestAnchorProvider(identity: providerIdentity, status: .submitted)
        let payload = try MeshRequestAnchorPayload(
            metadata: MeshSignedRequestAnchorMetadata(request: request),
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash
        )
        let input = try MeshRequestAnchorSubmitInput(
            payload: payload,
            providerIdentity: providerIdentity,
            submittedAt: "2026-05-31T12:00:05Z"
        )

        let output = try await MeshRequestAnchorSubmissionModule(provider: provider).submitAnchor(input)

        XCTAssertEqual(input.signedMCPRequestHash, try MeshRequestAnchorCanonicalization.signedRequestHash(for: request))
        XCTAssertEqual(input.requestNonce, request.nonce)
        XCTAssertEqual(input.policyId, DailyMartDelegatedSpendingPolicy.policyId)
        XCTAssertEqual(input.policyHash, DailyMartDelegatedSpendingPolicy.policyHash)
        XCTAssertEqual(output.requestHash, input.signedMCPRequestHash)
        XCTAssertEqual(output.requestNonce, input.requestNonce)
        XCTAssertEqual(output.policyId, input.policyId)
        XCTAssertEqual(output.policyHash, input.policyHash)
        XCTAssertEqual(output.status, .submitted)
        XCTAssertEqual(output.anchoringReference.identity.metadata, providerIdentity.metadata)
    }

    func testRequestAnchorReferenceOutputContainsRequestPolicyProviderAndStatus() async throws {
        let request = try signedDailyMartRequest()
        let providerIdentity = try chainProviderIdentity()
        let provider = try MeshDemoRequestAnchorProvider(identity: providerIdentity, status: .confirmed)
        let policy = try DailyMartDelegatedSpendingPolicy.expectedPolicy()

        let anchor = try await MeshRequestAnchorSubmissionModule(provider: provider).submit(
            request: request,
            policy: policy,
            submittedAt: "2026-05-31T12:00:06Z"
        )
        let output = try MeshRequestAnchorReferenceOutput(anchor: anchor)

        XCTAssertEqual(output.version, MeshRequestAnchorReferenceOutput.version)
        XCTAssertEqual(output.requestHash, try MeshRequestAnchorCanonicalization.signedRequestHash(for: request))
        XCTAssertEqual(output.requestNonce, request.nonce)
        XCTAssertEqual(output.policyId, DailyMartDelegatedSpendingPolicy.policyId)
        XCTAssertEqual(output.policyHash, DailyMartDelegatedSpendingPolicy.policyHash)
        XCTAssertEqual(output.providerReference, anchor.identifier)
        XCTAssertEqual(output.providerReference.identity.metadata, providerIdentity.metadata)
        XCTAssertEqual(output.status, .confirmed)
        XCTAssertNoThrow(try output.validate())
        XCTAssertNoThrow(try MeshRequestAnchorReferenceOutput.validate(output: output, anchor: anchor))
    }

    func testRequestAnchorReferenceOutputValidationRejectsPolicyMismatch() async throws {
        let request = try signedDailyMartRequest()
        let providerIdentity = try chainProviderIdentity()
        let provider = try MeshDemoRequestAnchorProvider(identity: providerIdentity, status: .confirmed)
        let anchor = try await MeshRequestAnchorSubmissionModule(provider: provider).submit(
            request: request,
            policy: DailyMartDelegatedSpendingPolicy.expectedPolicy(),
            submittedAt: "2026-05-31T12:00:06Z"
        )
        let output = try MeshRequestAnchorReferenceOutput(
            requestHash: anchor.metadata.signedRequestHash,
            requestNonce: anchor.metadata.nonce,
            policyId: "policy-hermes-dailymart-okrw-other",
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash,
            providerReference: anchor.identifier,
            status: anchor.status
        )

        XCTAssertThrowsError(try MeshRequestAnchorReferenceOutput.validate(output: output, anchor: anchor)) { error in
            XCTAssertEqual(
                error as? MeshKitValidationError,
                .signatureMismatch("request anchor reference output policy linkage mismatch")
            )
        }
    }

    func testAnchoringReferenceIsPresentForSignedRequestHash() throws {
        let request = try signedDailyMartRequest()
        let requestHash = try MeshRequestAnchorCanonicalization.signedRequestHash(for: request)
        let providerIdentity = try chainProviderIdentity()

        let reference = try MeshRequestAnchorCanonicalization.anchoringReference(
            forSignedRequestHash: requestHash,
            providerIdentity: providerIdentity
        )

        XCTAssertEqual(reference.identity.metadata, providerIdentity.metadata)
        XCTAssertEqual(
            reference.anchorId,
            "request-anchor-sha256-\(requestHash.value)"
        )
        XCTAssertNil(reference.transactionHash)
        XCTAssertNil(reference.explorerURL)
    }

    func testAnchoringReferenceIsDeterministicForSameSignedRequestHash() throws {
        let request = try signedDailyMartRequest()
        let providerIdentity = try chainProviderIdentity()
        let requestHash = try MeshRequestAnchorCanonicalization.signedRequestHash(for: request)
        let equivalentRequestHash = MeshPayloadHash(
            algorithm: requestHash.algorithm.uppercased(),
            value: requestHash.value.uppercased()
        )

        let firstReference = try MeshRequestAnchorCanonicalization.anchoringReference(
            forSignedRequestHash: requestHash,
            providerIdentity: providerIdentity
        )
        let secondReference = try MeshRequestAnchorCanonicalization.anchoringReference(
            forSignedRequestHash: equivalentRequestHash,
            providerIdentity: providerIdentity
        )
        let requestDerivedReference = try MeshRequestAnchorCanonicalization.anchoringReference(
            for: request,
            providerIdentity: providerIdentity
        )

        XCTAssertEqual(firstReference, secondReference)
        XCTAssertEqual(firstReference, requestDerivedReference)
        XCTAssertEqual(
            try MeshRequestAnchorCanonicalization.anchoringReferenceId(forSignedRequestHash: requestHash),
            firstReference.anchorId
        )
    }

    func testRequestAnchorCanonicalSerializationIsStableAndRoundTripsAllFields() throws {
        let metadata = try MeshSignedRequestAnchorMetadata(
            requestId: "ios-grocery-anchor-serialization-001",
            nonce: "nonce-anchor-serialization-001",
            timestamp: "2026-05-31T12:10:00Z",
            callerAppId: "app.hermes-chat",
            callerBundleId: "ai.meshkit.sample.hermeschat",
            targetBundleId: "ai.meshkit.sample.dailymart",
            capabilityId: "grocery.purchase_essentials",
            payloadHash: MeshPayloadHash(value: String(repeating: "1", count: 64)),
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "hermes-anchor-reference-key",
                value: "signature-anchor-serialization"
            ),
            signedRequestHash: MeshPayloadHash(value: String(repeating: "2", count: 64))
        )
        let payload = try MeshRequestAnchorPayload(
            metadata: metadata,
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: MeshPayloadHash(value: String(repeating: "3", count: 64))
        )
        let identifier = try MeshRequestAnchorIdentifier(
            identity: chainProviderIdentity(),
            anchorId: "request-anchor-sha256-\(String(repeating: "2", count: 64))",
            transactionHash: "0xanchorSerialization001"
        )
        let anchor = try MeshRequestAnchor(
            metadata: metadata,
            payload: payload,
            identifier: identifier,
            status: .confirmed,
            submittedAt: "2026-05-31T12:10:01Z",
            observedAt: "2026-05-31T12:10:05Z",
            message: "confirmed on demo testnet"
        )

        let canonical = try MeshRequestAnchorSerialization.canonicalString(for: anchor)
        let expectedCanonical = #"{"identifier":{"anchorId":"request-anchor-sha256-2222222222222222222222222222222222222222222222222222222222222222","explorerURL":"https:\/\/explorer.demo-chain.example.invalid\/tx\/0xanchorSerialization001","identity":{"chainId":"demo-testnet-1","explorerBaseUrl":"https:\/\/explorer.demo-chain.example.invalid","network":"demo-testnet","provider":"demo-chain","rpcEndpoint":"https:\/\/rpc.demo-chain.example.invalid"},"transactionHash":"0xanchorSerialization001"},"message":"confirmed on demo testnet","metadata":{"callerAppId":"app.hermes-chat","callerBundleId":"ai.meshkit.sample.hermeschat","capabilityId":"grocery.purchase_essentials","nonce":"nonce-anchor-serialization-001","payloadHash":{"algorithm":"sha256","value":"1111111111111111111111111111111111111111111111111111111111111111"},"requestId":"ios-grocery-anchor-serialization-001","signature":{"algorithm":"Ed25519","keyId":"hermes-anchor-reference-key","value":"signature-anchor-serialization"},"signedRequestHash":{"algorithm":"sha256","value":"2222222222222222222222222222222222222222222222222222222222222222"},"targetBundleId":"ai.meshkit.sample.dailymart","timestamp":"2026-05-31T12:10:00Z"},"observedAt":"2026-05-31T12:10:05Z","payload":{"metadata":{"callerAppId":"app.hermes-chat","callerBundleId":"ai.meshkit.sample.hermeschat","capabilityId":"grocery.purchase_essentials","nonce":"nonce-anchor-serialization-001","payloadHash":{"algorithm":"sha256","value":"1111111111111111111111111111111111111111111111111111111111111111"},"requestId":"ios-grocery-anchor-serialization-001","signature":{"algorithm":"Ed25519","keyId":"hermes-anchor-reference-key","value":"signature-anchor-serialization"},"signedRequestHash":{"algorithm":"sha256","value":"2222222222222222222222222222222222222222222222222222222222222222"},"targetBundleId":"ai.meshkit.sample.dailymart","timestamp":"2026-05-31T12:10:00Z"},"policyHash":{"algorithm":"sha256","value":"3333333333333333333333333333333333333333333333333333333333333333"},"policyId":"policy-hermes-dailymart-okrw-v1","requestNonce":"nonce-anchor-serialization-001","version":"meshkit-request-anchor\/v1"},"status":"confirmed","submittedAt":"2026-05-31T12:10:01Z"}"#

        XCTAssertEqual(canonical, expectedCanonical)
        XCTAssertEqual(try MeshRequestAnchorSerialization.canonicalString(for: anchor), canonical)

        let decoded = try MeshRequestAnchorSerialization.decode(canonical)
        XCTAssertEqual(decoded, anchor)
        XCTAssertEqual(decoded.metadata, metadata)
        XCTAssertEqual(decoded.payload, payload)
        XCTAssertEqual(decoded.identifier, identifier)
        XCTAssertEqual(decoded.status, .confirmed)
        XCTAssertEqual(decoded.submittedAt, "2026-05-31T12:10:01Z")
        XCTAssertEqual(decoded.observedAt, "2026-05-31T12:10:05Z")
        XCTAssertEqual(decoded.message, "confirmed on demo testnet")
        XCTAssertEqual(try MeshRequestAnchorSerialization.canonicalString(for: decoded), expectedCanonical)
    }

    private func signedDailyMartRequest() throws -> MeshRequest {
        try MeshSignedRequestBuilder(
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ipad-device",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "hermes-anchor-reference-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                version: "1.0"
            ),
            signer: signer
        ).makeRequest(
            requestId: "ios-grocery-anchor-reference-001",
            payload: [
                "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6",
                "address_ref": "home.saved",
                "budget_krw": "100",
                "policyId": DailyMartDelegatedSpendingPolicy.policyId,
                "policyHash": DailyMartDelegatedSpendingPolicy.policyHash.value
            ],
            nonce: "nonce-anchor-reference-001",
            timestamp: "2026-05-31T12:00:00Z"
        )
    }

    private func chainProviderIdentity() throws -> MeshChainProviderIdentity {
        try MeshChainProviderIdentity(
            providerName: "demo-chain",
            networkIdentity: "demo-testnet",
            chainId: "demo-testnet-1",
            rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc.demo-chain.example.invalid")),
            explorerBaseURL: try XCTUnwrap(URL(string: "https://explorer.demo-chain.example.invalid"))
        )
    }
}
