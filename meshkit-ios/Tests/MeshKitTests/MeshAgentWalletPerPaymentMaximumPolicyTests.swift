import XCTest
@testable import MeshKit

final class MeshAgentWalletPerPaymentMaximumPolicyTests: XCTestCase {
    func testSessionRemainingBalanceEligibilityAllowsAmountsAtOrBelowRemainingBalance() throws {
        let policy = try delegatedSpendingPolicy(
            singlePaymentMax: Decimal(500),
            remainingLimit: Decimal(100)
        )

        XCTAssertTrue(try policy.isSessionRemainingBalanceEligible(paymentAmount: Decimal(99)))
        XCTAssertTrue(try policy.isSessionRemainingBalanceEligible(paymentAmount: Decimal(100)))
        XCTAssertNoThrow(try policy.validateSessionRemainingBalanceEligibility(paymentAmount: Decimal(100)))
    }

    func testSessionRemainingBalanceEligibilityRejectsAmountsAboveRemainingBalance() throws {
        let policy = try delegatedSpendingPolicy(
            singlePaymentMax: Decimal(500),
            remainingLimit: Decimal(100)
        )

        XCTAssertFalse(try policy.isSessionRemainingBalanceEligible(paymentAmount: Decimal(string: "100.01")!))
        XCTAssertThrowsError(try policy.validateSessionRemainingBalanceEligibility(
            paymentAmount: Decimal(string: "100.01")!
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("remainingLimit"))
        }
    }

    func testPerPaymentMaximumAllowsAmountsAtOrBelowDelegatedMax() throws {
        let policy = try delegatedSpendingPolicy(singlePaymentMax: Decimal(100))

        let belowMax = try policy.evaluateExecutionRequest(
            executionRequest(executionId: "exec-per-payment-max-below", amount: Decimal(99)),
            requestedAt: "2026-05-31T00:00:00Z"
        )
        let atMax = try policy.evaluateExecutionRequest(
            executionRequest(executionId: "exec-per-payment-max-equal", amount: Decimal(100)),
            requestedAt: "2026-05-31T00:00:01Z"
        )

        XCTAssertEqual(belowMax.status, .allowed)
        XCTAssertEqual(belowMax.approvedAmount, Decimal(99))
        XCTAssertNil(belowMax.reason)
        XCTAssertEqual(atMax.status, .allowed)
        XCTAssertEqual(atMax.approvedAmount, Decimal(100))
        XCTAssertNil(atMax.reason)
    }

    func testPerPaymentMaximumDeniesAmountsAboveDelegatedMax() throws {
        let policy = try delegatedSpendingPolicy(singlePaymentMax: Decimal(100))

        let result = try policy.evaluateExecutionRequest(
            executionRequest(executionId: "exec-per-payment-max-above", amount: Decimal(string: "100.01")!),
            requestedAt: "2026-05-31T00:00:02Z"
        )

        XCTAssertEqual(result.status, .denied)
        XCTAssertNil(result.approvedAmount)
        XCTAssertEqual(result.reason, "policy-single-payment-max-exceeded")
    }

    private func delegatedSpendingPolicy(
        singlePaymentMax: Decimal,
        remainingLimit: Decimal = Decimal(500)
    ) throws -> MeshAgentWalletDelegatedSpendingPolicy {
        try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64)),
            consentGrantId: "grant-hermes-dailymart-001",
            merchantScope: "merchant.dailymart",
            capabilityScope: "grocery.purchase_essentials",
            singlePaymentMax: singlePaymentMax,
            sessionTotalLimit: Decimal(500),
            remainingLimit: remainingLimit,
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
            requestId: "ios-grocery-per-payment-max-\(amountLabel)",
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
            nonce: "nonce-per-payment-max-\(amountLabel)",
            timestamp: "2026-05-31T00:00:00Z",
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "sample-ios-ed25519",
                value: "test-signature"
            )
        )
    }
}
