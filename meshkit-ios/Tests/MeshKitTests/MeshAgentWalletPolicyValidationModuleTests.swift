import XCTest
@testable import MeshKit

final class MeshAgentWalletPolicyValidationModuleTests: XCTestCase {
    func testPolicyValidationModuleAllowsPolicyCompliantWalletRequest() throws {
        let wallet = try MeshMarooAgentWalletAdapter(
            chainProviderIdentity: MeshMarooTestnetChainProvider().identity,
            walletId: "wallet-hermes-dailymart-okrw-v1",
            agentId: "agent.hermes-chat.daily-mart",
            walletAddress: "maroo1dailyMartAgentWallet",
            capabilities: [.validatePolicy]
        )
        let policy = try delegatedSpendingPolicy()
        let request = try executionRequest(
            executionId: "exec-policy-validation-allowed",
            amount: Decimal(4_900)
        )
        let module = MeshAgentWalletPolicyValidationModule(wallet: wallet)

        let evaluation = try module.validateAllowedExecutionRequest(
            request,
            policy: policy,
            requestedAt: "2026-05-31T12:00:00Z"
        )

        XCTAssertEqual(evaluation.policyId, policy.policyId)
        XCTAssertEqual(evaluation.executionId, request.executionId)
        XCTAssertEqual(evaluation.status, .allowed)
        XCTAssertEqual(evaluation.approvedAmount, Decimal(4_900))
        XCTAssertNil(evaluation.reason)
    }

    func testPolicyValidationModuleReturnsPolicyDeniedResultForPolicyViolatingWalletRequest() throws {
        let wallet = try MeshMarooAgentWalletAdapter(
            chainProviderIdentity: MeshMarooTestnetChainProvider().identity,
            walletId: "wallet-hermes-dailymart-okrw-v1",
            agentId: "agent.hermes-chat.daily-mart",
            walletAddress: "maroo1dailyMartAgentWallet",
            capabilities: [.validatePolicy]
        )
        let policy = try delegatedSpendingPolicy()
        let request = try executionRequest(
            executionId: "exec-policy-validation-denied-over-max",
            amount: Decimal(5_001)
        )
        let module = MeshAgentWalletPolicyValidationModule(wallet: wallet)

        let result = try module.validateExecutionRequest(
            request,
            policy: policy,
            validatedAt: "2026-05-31T12:05:00Z"
        )

        XCTAssertEqual(result.status, .policyDenied)
        XCTAssertEqual(result.policyEvaluation.status, .denied)
        XCTAssertEqual(result.policyEvaluation.reason, "policy-single-payment-max-exceeded")
        XCTAssertEqual(result.reason, "policy-single-payment-max-exceeded")
        XCTAssertNil(result.approvedAmount)
        XCTAssertEqual(result.availableLimitBeforeValidation, Decimal(10_000))
        XCTAssertEqual(result.walletIdentity.walletAddress, "maroo1dailyMartAgentWallet")
    }

    private func delegatedSpendingPolicy() throws -> MeshAgentWalletDelegatedSpendingPolicy {
        try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64)),
            consentGrantId: "grant-hermes-dailymart-001",
            merchantScope: "merchant.dailymart",
            capabilityScope: "grocery.purchase_essentials",
            singlePaymentMax: Decimal(5_000),
            sessionTotalLimit: Decimal(10_000),
            remainingLimit: Decimal(10_000),
            startsAt: "2026-05-01T00:00:00Z",
            expiresAt: "2026-06-30T00:00:00Z",
            asset: "OKRW",
            recipientAddress: "0x000000000000000000000000000000000000d417"
        )
    }

    private func executionRequest(
        executionId: String,
        amount: Decimal
    ) throws -> MeshAgentWalletExecutionRequest {
        try MeshAgentWalletExecutionRequest(
            executionId: executionId,
            kind: .payment,
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
            recipientAddress: "0x000000000000000000000000000000000000d417",
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64))
        )
    }

    private func signedDailyMartRequest(amount: Decimal) -> MeshRequest {
        let amountLabel = "\(amount)".replacingOccurrences(of: ".", with: "-")
        return MeshRequest(
            requestId: "ios-grocery-policy-validation-\(amountLabel)",
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
            nonce: "nonce-policy-validation-\(amountLabel)",
            timestamp: "2026-05-31T12:00:00Z",
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "sample-ios-ed25519",
                value: "test-signature"
            )
        )
    }
}
