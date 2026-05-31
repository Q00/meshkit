import XCTest
@testable import MeshKit

final class MeshAgentWalletAuthorizationCheckTests: XCTestCase {
    func testAuthorizationCheckApprovesProposedPaymentWithinDelegatedPolicy() throws {
        let wallet = try marooWallet()
        let policy = try delegatedSpendingPolicy()
        let request = try executionRequest(
            executionId: "exec-auth-check-payment",
            kind: .payment,
            amount: Decimal(80)
        )

        let result = try wallet.checkExecutionAuthorization(
            request,
            policy: policy,
            checkedAt: "2026-05-31T12:00:00Z"
        )

        XCTAssertEqual(result.status, .approved)
        XCTAssertEqual(result.policyEvaluation.status, .allowed)
        XCTAssertEqual(result.approvedAmount, Decimal(80))
        XCTAssertEqual(result.availableLimitBeforeAuthorization, Decimal(100))
        XCTAssertNil(result.reason)

        let decision = try result.authorizationDecision(authorizationId: "auth-exec-auth-check-payment")
        XCTAssertEqual(decision.status, .approved)
        XCTAssertEqual(decision.executionRequest.kind, .payment)
        XCTAssertEqual(decision.approvedAmount, Decimal(80))
    }

    func testAuthorizationCheckDeniesProposedTransferAbovePerPaymentMaximum() throws {
        let wallet = try marooWallet()
        let policy = try delegatedSpendingPolicy(singlePaymentMax: Decimal(100))
        let request = try executionRequest(
            executionId: "exec-auth-check-transfer-over-max",
            kind: .transfer,
            amount: Decimal(101)
        )

        let result = try wallet.checkExecutionAuthorization(
            request,
            policy: policy,
            checkedAt: "2026-05-31T12:01:00Z"
        )

        XCTAssertEqual(result.status, .denied)
        XCTAssertEqual(result.policyEvaluation.status, .denied)
        XCTAssertNil(result.approvedAmount)
        XCTAssertEqual(result.reason, "policy-single-payment-max-exceeded")
        XCTAssertEqual(result.executionRequest.kind, .transfer)
    }

    func testAuthorizationCheckDeniesWhenPendingReservationsExhaustAvailableLimit() throws {
        let wallet = try marooWallet()
        let policy = try delegatedSpendingPolicy(sessionTotalLimit: Decimal(100), remainingLimit: Decimal(100))
        let existingRequest = try executionRequest(
            executionId: "exec-auth-check-pending-reservation",
            kind: .payment,
            amount: Decimal(80)
        )
        let accounting = try MeshAgentWalletDelegatedSpendAccounting(policy: policy)
            .reservingPendingExecution(
                existingRequest,
                recordedAt: "2026-05-31T12:02:00Z"
            )
        let proposedRequest = try executionRequest(
            executionId: "exec-auth-check-transfer-available-limit",
            kind: .transfer,
            amount: Decimal(30)
        )

        let result = try wallet.checkExecutionAuthorization(
            proposedRequest,
            policy: policy,
            accounting: accounting,
            checkedAt: "2026-05-31T12:03:00Z"
        )

        XCTAssertEqual(result.status, .denied)
        XCTAssertEqual(result.policyEvaluation.status, .denied)
        XCTAssertEqual(result.availableLimitBeforeAuthorization, Decimal(20))
        XCTAssertEqual(result.reason, "policy-available-limit-exceeded")
    }

    private func marooWallet() throws -> any MeshAgentWallet {
        try MeshMarooAgentWalletAdapter(
            chainProviderIdentity: MeshMarooTestnetChainProvider().identity,
            walletId: "wallet-hermes-dailymart-okrw-v1",
            agentId: "agent.hermes-chat.daily-mart",
            walletAddress: "maroo1dailyMartAgentWallet",
            capabilities: [
                .reportWalletAddress,
                .exposeSigningBoundary,
                .checkExecutionAuthorization
            ]
        )
    }

    private func delegatedSpendingPolicy(
        singlePaymentMax: Decimal = Decimal(100),
        sessionTotalLimit: Decimal = Decimal(100),
        remainingLimit: Decimal = Decimal(100)
    ) throws -> MeshAgentWalletDelegatedSpendingPolicy {
        try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64)),
            consentGrantId: "grant-hermes-dailymart-001",
            merchantScope: "merchant.dailymart",
            capabilityScope: "grocery.purchase_essentials",
            singlePaymentMax: singlePaymentMax,
            sessionTotalLimit: sessionTotalLimit,
            remainingLimit: remainingLimit,
            expiresAt: "2026-06-30T00:00:00Z",
            asset: "OKRW",
            recipientAddress: "maroo1dailyMartMerchant"
        )
    }

    private func executionRequest(
        executionId: String,
        kind: MeshAgentWalletExecutionKind,
        amount: Decimal
    ) throws -> MeshAgentWalletExecutionRequest {
        try MeshAgentWalletExecutionRequest(
            executionId: executionId,
            kind: kind,
            requestAnchorMetadata: MeshSignedRequestAnchorMetadata(request: signedDailyMartRequest(amount: amount)),
            scope: MeshAgentWalletSpendingScope(
                merchantId: "merchant.dailymart",
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                consentGrantId: "grant-hermes-dailymart-001"
            ),
            amount: amount,
            currencyCode: "KRW",
            tokenSymbol: "OKRW",
            recipientAddress: "maroo1dailyMartMerchant",
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64))
        )
    }

    private func signedDailyMartRequest(amount: Decimal) -> MeshRequest {
        let amountLabel = "\(amount)".replacingOccurrences(of: ".", with: "-")
        return MeshRequest(
            requestId: "ios-grocery-auth-check-\(amountLabel)",
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-device",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "sample-ios-ed25519"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                version: "1.0"
            ),
            payload: [
                "items": "laundry_detergent:1",
                "address_ref": "home.saved",
                "budget_krw": "\(amount)",
                "merchantScope": "merchant.dailymart",
                "capabilityScope": "grocery.purchase_essentials",
                "consentGrantId": "grant-hermes-dailymart-001",
                "policyId": "policy-hermes-dailymart-okrw-v1",
                "policyHash": String(repeating: "f", count: 64)
            ],
            nonce: "nonce-auth-check-\(amountLabel)",
            timestamp: "2026-05-31T12:00:00Z",
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "sample-ios-ed25519",
                value: "test-signature"
            )
        )
    }
}
