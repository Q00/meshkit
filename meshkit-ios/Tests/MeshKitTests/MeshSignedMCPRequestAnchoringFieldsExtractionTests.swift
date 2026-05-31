import CryptoKit
import XCTest
@testable import MeshKit

final class MeshSignedMCPRequestAnchoringFieldsExtractionTests: XCTestCase {
    private let signer = MeshRequestSigner(algorithm: "Ed25519", keyId: "hermes-anchor-fields-key") { data in
        Data(SHA256.hash(data: data))
    }

    func testExtractsSignedMCPRequestAnchoringFieldsFromSDKAndProviderRequestContexts() throws {
        let request = try signedDailyMartRequest()
        let providerIdentity = try chainProviderIdentity()
        let metadata = try MeshSignedRequestAnchorMetadata(request: request)
        let payload = try MeshRequestAnchorPayload(
            metadata: metadata,
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash
        )
        let submission = try MeshRequestAnchorSubmission(
            payload: payload,
            providerIdentity: providerIdentity,
            submittedAt: "2026-05-31T12:21:05Z"
        )
        let submitInput = try MeshRequestAnchorSubmitInput(
            payload: payload,
            providerIdentity: providerIdentity,
            submittedAt: "2026-05-31T12:21:06Z"
        )
        let providerInput = try MeshRequestAnchorProviderInput(
            payload: payload,
            providerIdentity: providerIdentity,
            submittedAt: "2026-05-31T12:21:07Z"
        )

        let expected = try MeshSignedMCPRequestAnchoringFields(payload: payload)

        XCTAssertEqual(try payload.signedMCPRequestAnchoringFields(), expected)
        XCTAssertEqual(try submission.signedMCPRequestAnchoringFields(), expected)
        XCTAssertEqual(try submitInput.signedMCPRequestAnchoringFields(), expected)
        XCTAssertEqual(try providerInput.signedMCPRequestAnchoringFields(), expected)
        XCTAssertEqual(expected.signedMCPRequestHash, metadata.signedRequestHash)
        XCTAssertEqual(expected.requestNonce, request.nonce)
        XCTAssertEqual(expected.policyId, DailyMartDelegatedSpendingPolicy.policyId)
        XCTAssertEqual(expected.policyHash, DailyMartDelegatedSpendingPolicy.policyHash)
    }

    func testExtractsSignedMCPRequestAnchoringFieldsFromExecutionAndPaymentContexts() throws {
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-anchor-fields-payment-001",
            nonce: "nonce-anchor-fields-payment-001"
        )
        let paymentContext = try makePaymentContext(request: request)
        let expected = try MeshSignedMCPRequestAnchoringFields(payload: paymentContext.payload)

        XCTAssertEqual(try paymentContext.executionRequest.signedMCPRequestAnchoringFields(), expected)
        XCTAssertEqual(try paymentContext.paymentRequest.signedMCPRequestAnchoringFields(), expected)
        XCTAssertEqual(expected.signedMCPRequestHash, try MeshRequestAnchorCanonicalization.signedRequestHash(for: request))
        XCTAssertEqual(expected.requestNonce, "nonce-anchor-fields-payment-001")
    }

    func testPaymentContextExtractionRejectsMismatchedAnchorPayloadPolicyBinding() throws {
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-anchor-fields-mismatch-001",
            nonce: "nonce-anchor-fields-mismatch-001"
        )
        let paymentContext = try makePaymentContext(request: request)
        let tamperedPayload = try MeshRequestAnchorPayload(
            metadata: paymentContext.payload.metadata,
            policyId: "policy-hermes-dailymart-okrw-v1-tampered",
            policyHash: MeshPayloadHash(value: String(repeating: "9", count: 64))
        )
        let tamperedAnchor = try MeshRequestAnchor(
            metadata: paymentContext.anchor.metadata,
            payload: tamperedPayload,
            identifier: paymentContext.anchor.identifier,
            status: paymentContext.anchor.status,
            submittedAt: paymentContext.anchor.submittedAt,
            observedAt: paymentContext.anchor.observedAt
        )
        let tamperedPaymentRequest = try MeshPaymentExecutionRequest(
            paymentId: paymentContext.paymentRequest.paymentId,
            authorizationDecision: paymentContext.paymentRequest.authorizationDecision,
            requestAnchor: tamperedAnchor,
            requestedAt: paymentContext.paymentRequest.requestedAt
        )

        XCTAssertThrowsError(try MeshSignedMCPRequestAnchoringFields(paymentRequest: tamperedPaymentRequest)) { error in
            XCTAssertEqual(
                error as? MeshKitValidationError,
                .signatureMismatch("signed MCP request anchoring fields payload linkage mismatch")
            )
        }
    }

    private func makePaymentContext(request: MeshRequest) throws -> PaymentContext {
        let providerIdentity = try chainProviderIdentity()
        let metadata = try MeshSignedRequestAnchorMetadata(request: request)
        let payload = try MeshRequestAnchorPayload(
            metadata: metadata,
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash
        )
        let anchor = try MeshRequestAnchor(
            metadata: metadata,
            payload: payload,
            identifier: MeshRequestAnchorCanonicalization.anchoringReference(
                for: metadata,
                providerIdentity: providerIdentity
            ),
            status: .submitted,
            submittedAt: "2026-05-31T12:22:05Z",
            observedAt: "2026-05-31T12:22:06Z"
        )
        let executionRequest = try MeshAgentWalletExecutionRequest(
            executionId: "execution-\(request.requestId)",
            kind: .payment,
            requestAnchorMetadata: metadata,
            scope: MeshAgentWalletSpendingScope(
                merchantId: "dailymart",
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                consentGrantId: DailyMartDelegatedSpendingPolicy.consentGrantId
            ),
            amount: Decimal(100),
            tokenSymbol: "OKRW",
            recipientAddress: "maroo1dailymartmerchant",
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash
        )
        let authorizationDecision = try MeshAgentWalletAuthorizationDecision(
            authorizationId: "authorization-\(request.requestId)",
            walletIdentity: walletIdentity(providerIdentity: providerIdentity),
            executionRequest: executionRequest,
            status: .approved,
            approvedAmount: Decimal(100),
            decidedAt: "2026-05-31T12:22:07Z"
        )
        let paymentRequest = try MeshPaymentExecutionRequest(
            paymentId: "payment-\(request.requestId)",
            authorizationDecision: authorizationDecision,
            requestAnchor: anchor,
            requestedAt: "2026-05-31T12:22:08Z"
        )

        return PaymentContext(
            payload: payload,
            anchor: anchor,
            executionRequest: executionRequest,
            paymentRequest: paymentRequest
        )
    }

    private func signedDailyMartRequest(
        requestId: String = "ios-grocery-anchor-fields-001",
        nonce: String = "nonce-anchor-fields-001"
    ) throws -> MeshRequest {
        try MeshSignedRequestBuilder(
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ipad-device",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "hermes-anchor-fields-key"
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
            timestamp: "2026-05-31T12:21:00Z"
        )
    }

    private func walletIdentity(providerIdentity: MeshChainProviderIdentity) throws -> MeshAgentWalletIdentity {
        try MeshAgentWalletIdentity(
            walletId: "wallet-hermes-anchor-fields",
            agentId: "agent-hermes-chat",
            walletAddress: "maroo1hermesdelegatewallet",
            providerMetadata: MeshAgentWalletProviderMetadata(chainProviderIdentity: providerIdentity),
            signingBoundary: .localSignature
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

private struct PaymentContext {
    let payload: MeshRequestAnchorPayload
    let anchor: MeshRequestAnchor
    let executionRequest: MeshAgentWalletExecutionRequest
    let paymentRequest: MeshPaymentExecutionRequest
}
