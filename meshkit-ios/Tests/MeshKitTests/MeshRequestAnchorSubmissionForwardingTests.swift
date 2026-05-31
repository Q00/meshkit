import CryptoKit
import XCTest
@testable import MeshKit

final class MeshRequestAnchorSubmissionForwardingTests: XCTestCase {
    private let signer = MeshRequestSigner(algorithm: "Ed25519", keyId: "hermes-anchor-forwarding-key") { data in
        Data(SHA256.hash(data: data))
    }

    func testSubmitAnchorForwardsValidatedPayloadToConfiguredAdapterExactlyOnce() async throws {
        let providerIdentity = try chainProviderIdentity()
        let adapter = try CapturingRequestAnchorAdapter(identity: providerIdentity)
        let request = try signedDailyMartRequest()
        let payload = try MeshRequestAnchorPayload(
            metadata: MeshSignedRequestAnchorMetadata(request: request),
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash
        )
        let input = try MeshRequestAnchorSubmitInput(
            payload: payload,
            providerIdentity: providerIdentity,
            submittedAt: "2026-05-31T12:03:05Z"
        )

        let output = try await MeshRequestAnchorSubmissionModule(provider: adapter).submitAnchor(input)
        let invocations = await adapter.snapshotInvocations()

        XCTAssertEqual(invocations.count, 1)
        XCTAssertEqual(invocations.first?.payload, payload)
        XCTAssertEqual(invocations.first?.submittedAt, input.submittedAt)
        XCTAssertEqual(output.anchoringReference.anchorId, "mock-anchor-ios-grocery-anchor-forwarding-001")
        XCTAssertEqual(output.requestHash, payload.metadata.signedRequestHash)
        XCTAssertEqual(output.requestNonce, payload.metadata.nonce)
        XCTAssertEqual(output.policyId, payload.policyId)
        XCTAssertEqual(output.policyHash, payload.policyHash)
    }

    func testSubmitAnchorPreservesSignedMCPRequestHashNonceAndPolicyBindingWhenForwardingToMockAdapter() async throws {
        let providerIdentity = try chainProviderIdentity()
        let adapter = try CapturingRequestAnchorAdapter(identity: providerIdentity)
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-anchor-forwarding-002",
            nonce: "nonce-anchor-forwarding-preserved-002"
        )
        let expectedPolicyId = "policy-hermes-dailymart-okrw-v1-forwarding-preserved"
        let expectedPolicyHash = MeshPayloadHash(value: String(repeating: "8", count: 64))
        let expectedMetadata = try MeshSignedRequestAnchorMetadata(request: request)
        let payload = try MeshRequestAnchorPayload(
            metadata: expectedMetadata,
            policyId: expectedPolicyId,
            policyHash: expectedPolicyHash
        )
        let input = try MeshRequestAnchorSubmitInput(
            payload: payload,
            providerIdentity: providerIdentity,
            submittedAt: "2026-05-31T12:04:05Z"
        )

        _ = try await MeshRequestAnchorSubmissionModule(provider: adapter).submitAnchor(input)
        let invocations = await adapter.snapshotInvocations()
        let invocation = try XCTUnwrap(invocations.first)

        XCTAssertEqual(input.signedMCPRequestHash, expectedMetadata.signedRequestHash)
        XCTAssertEqual(input.requestNonce, expectedMetadata.nonce)
        XCTAssertEqual(invocation.forwardedSignedMCPRequestHash, expectedMetadata.signedRequestHash)
        XCTAssertEqual(invocation.forwardedRequestNonce, expectedMetadata.nonce)
        XCTAssertEqual(invocation.forwardedPolicyId, expectedPolicyId)
        XCTAssertEqual(invocation.forwardedPolicyHash, expectedPolicyHash)
        XCTAssertEqual(invocation.forwardedSignedMCPRequestHash, input.signedMCPRequestHash)
        XCTAssertEqual(invocation.forwardedRequestNonce, input.requestNonce)
        XCTAssertEqual(invocation.forwardedPolicyId, input.policyId)
        XCTAssertEqual(invocation.forwardedPolicyHash, input.policyHash)
    }

    func testSubmitAnchorContractAcceptsRequiredSignedRequestNonceAndPolicyFields() async throws {
        let providerIdentity = try chainProviderIdentity()
        let adapter = try CapturingRequestAnchorAdapter(identity: providerIdentity)
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-anchor-forwarding-003",
            nonce: "nonce-anchor-forwarding-required-contract-003"
        )
        let payload = try MeshRequestAnchorPayload(
            metadata: MeshSignedRequestAnchorMetadata(request: request),
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash
        )

        let output = try await MeshRequestAnchorSubmissionModule(provider: adapter).submitAnchor(
            payload: payload,
            signedMCPRequestHash: payload.metadata.signedRequestHash,
            requestNonce: payload.metadata.nonce,
            policyId: payload.policyId,
            policyHash: payload.policyHash,
            submittedAt: "2026-05-31T12:05:05Z"
        )
        let invocations = await adapter.snapshotInvocations()
        let invocation = try XCTUnwrap(invocations.first)

        XCTAssertEqual(invocation.forwardedSignedMCPRequestHash, payload.metadata.signedRequestHash)
        XCTAssertEqual(invocation.forwardedRequestNonce, payload.metadata.nonce)
        XCTAssertEqual(invocation.forwardedPolicyId, DailyMartDelegatedSpendingPolicy.policyId)
        XCTAssertEqual(invocation.forwardedPolicyHash, DailyMartDelegatedSpendingPolicy.policyHash)
        XCTAssertEqual(output.requestHash, payload.metadata.signedRequestHash)
        XCTAssertEqual(output.requestNonce, payload.metadata.nonce)
        XCTAssertEqual(output.policyId, payload.policyId)
        XCTAssertEqual(output.policyHash, payload.policyHash)
    }

    func testSubmitAnchorContractRejectsMismatchedRequiredSignedRequestFieldsBeforeProviderSubmission() async throws {
        let providerIdentity = try chainProviderIdentity()
        let adapter = try CapturingRequestAnchorAdapter(identity: providerIdentity)
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-anchor-forwarding-004",
            nonce: "nonce-anchor-forwarding-required-contract-004"
        )
        let payload = try MeshRequestAnchorPayload(
            metadata: MeshSignedRequestAnchorMetadata(request: request),
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash
        )

        do {
            _ = try await MeshRequestAnchorSubmissionModule(provider: adapter).submitAnchor(
                payload: payload,
                signedMCPRequestHash: MeshPayloadHash(value: String(repeating: "9", count: 64)),
                requestNonce: payload.metadata.nonce,
                policyId: payload.policyId,
                policyHash: payload.policyHash,
                submittedAt: "2026-05-31T12:06:05Z"
            )
            XCTFail("submitAnchor accepted a mismatched signed MCP request hash")
        } catch {
            XCTAssertEqual(
                error as? MeshKitValidationError,
                .signatureMismatch("request anchor submit input request linkage mismatch")
            )
        }

        let invocations = await adapter.snapshotInvocations()
        XCTAssertTrue(invocations.isEmpty)
    }

    func testSubmitAnchorSubmissionBridgeConstructsPayloadInputAndForwardsProviderError() async throws {
        let providerIdentity = try chainProviderIdentity()
        let adapter = try FailingRequestAnchorAdapter(identity: providerIdentity)
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-anchor-forwarding-005",
            nonce: "nonce-anchor-forwarding-required-contract-005"
        )
        let policy = try DailyMartDelegatedSpendingPolicy.expectedPolicy()
        let submission = try MeshRequestAnchorSubmission(
            request: request,
            policy: policy,
            providerIdentity: providerIdentity,
            submittedAt: "2026-05-31T12:07:05Z"
        )

        do {
            _ = try await MeshRequestAnchorSubmissionModule(provider: adapter).submitAnchor(
                submission,
                boundTo: request,
                policy: policy
            )
            XCTFail("submitAnchor did not propagate the provider submission error")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProviderIdentity("provider-submitAnchor"))
        }

        let invocations = await adapter.snapshotInvocations()
        XCTAssertEqual(invocations.count, 1)
        XCTAssertEqual(invocations.first?.payload, submission.payload)
        XCTAssertEqual(invocations.first?.submittedAt, submission.submittedAt)
    }

    private func signedDailyMartRequest(
        requestId: String = "ios-grocery-anchor-forwarding-001",
        nonce: String = "nonce-anchor-forwarding-001"
    ) throws -> MeshRequest {
        try MeshSignedRequestBuilder(
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ipad-device",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "hermes-anchor-forwarding-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                version: "1.0"
            ),
            signer: signer
        ).makeRequest(
            requestId: requestId,
            payload: [
                "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6",
                "address_ref": "home.saved",
                "budget_krw": "100",
                "policyId": DailyMartDelegatedSpendingPolicy.policyId,
                "policyHash": DailyMartDelegatedSpendingPolicy.policyHash.value
            ],
            nonce: nonce,
            timestamp: "2026-05-31T12:03:00Z"
        )
    }

    private func chainProviderIdentity() throws -> MeshChainProviderIdentity {
        try MeshChainProviderIdentity(
            providerName: "mock-chain",
            networkIdentity: "mock-testnet",
            chainId: "mock-testnet-1",
            rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc.mock-chain.example.invalid")),
            explorerBaseURL: try XCTUnwrap(URL(string: "https://explorer.mock-chain.example.invalid"))
        )
    }
}

private actor FailingRequestAnchorAdapter: MeshRequestAnchorProvider {
    struct Invocation: Equatable {
        let payload: MeshRequestAnchorPayload
        let submittedAt: String
    }

    let identity: MeshChainProviderIdentity
    let capabilities: [MeshChainProviderCapability] = [.anchorSignedRequest]
    private var invocations: [Invocation] = []

    init(identity: MeshChainProviderIdentity) throws {
        self.identity = identity
        try MeshChainProviderConfiguration(identity: identity, capabilities: capabilities).validate()
    }

    func anchorSignedRequest(
        payload: MeshRequestAnchorPayload,
        submittedAt: String
    ) async throws -> MeshRequestAnchor {
        try payload.validate()
        invocations.append(Invocation(payload: payload, submittedAt: submittedAt))
        throw MeshKitValidationError.invalidChainProviderIdentity("provider-submitAnchor")
    }

    func anchorSignedRequest(
        metadata: MeshSignedRequestAnchorMetadata,
        submittedAt: String
    ) async throws -> MeshRequestAnchor {
        XCTFail("submitAnchor must forward the constructed payload input before provider failure")
        throw MeshKitValidationError.invalidChainProviderIdentity("metadata-submitAnchor")
    }

    func requestAnchorStatus(
        identifier: MeshRequestAnchorIdentifier,
        checkedAt: String
    ) async throws -> MeshRequestAnchor {
        throw MeshKitValidationError.requestAnchorReferenceNotFound(identifier.anchorId)
    }

    func snapshotInvocations() -> [Invocation] {
        invocations
    }
}

private actor CapturingRequestAnchorAdapter: MeshRequestAnchorProvider {
    struct Invocation: Equatable {
        let payload: MeshRequestAnchorPayload
        let submittedAt: String

        var forwardedSignedMCPRequestHash: MeshPayloadHash {
            payload.metadata.signedRequestHash
        }

        var forwardedRequestNonce: String {
            payload.metadata.nonce
        }

        var forwardedPolicyId: String {
            payload.policyId
        }

        var forwardedPolicyHash: MeshPayloadHash {
            payload.policyHash
        }
    }

    let identity: MeshChainProviderIdentity
    let capabilities: [MeshChainProviderCapability]
    private var invocations: [Invocation] = []

    init(
        identity: MeshChainProviderIdentity,
        capabilities: [MeshChainProviderCapability] = [.anchorSignedRequest]
    ) throws {
        self.identity = identity
        self.capabilities = Array(Set(capabilities)).sorted()
        try MeshChainProviderConfiguration(identity: identity, capabilities: self.capabilities).validate()
    }

    func anchorSignedRequest(
        payload: MeshRequestAnchorPayload,
        submittedAt: String
    ) async throws -> MeshRequestAnchor {
        try payload.validate()
        invocations.append(Invocation(payload: payload, submittedAt: submittedAt))
        return try MeshRequestAnchor(
            metadata: payload.metadata,
            payload: payload,
            identifier: MeshRequestAnchorIdentifier(
                identity: identity,
                anchorId: "mock-anchor-\(payload.metadata.requestId)",
                transactionHash: "0x" + String(repeating: "3", count: 64)
            ),
            status: .submitted,
            submittedAt: submittedAt,
            observedAt: submittedAt
        )
    }

    func anchorSignedRequest(
        metadata: MeshSignedRequestAnchorMetadata,
        submittedAt: String
    ) async throws -> MeshRequestAnchor {
        XCTFail("submitAnchor must forward the validated payload object, not metadata-only anchoring")
        return try MeshRequestAnchor(
            metadata: metadata,
            identifier: MeshRequestAnchorIdentifier(
                identity: identity,
                anchorId: "unexpected-metadata-anchor-\(metadata.requestId)"
            ),
            status: .failed,
            submittedAt: submittedAt
        )
    }

    func requestAnchorStatus(
        identifier: MeshRequestAnchorIdentifier,
        checkedAt: String
    ) async throws -> MeshRequestAnchor {
        throw MeshKitValidationError.requestAnchorReferenceNotFound(identifier.anchorId)
    }

    func snapshotInvocations() -> [Invocation] {
        invocations
    }
}
