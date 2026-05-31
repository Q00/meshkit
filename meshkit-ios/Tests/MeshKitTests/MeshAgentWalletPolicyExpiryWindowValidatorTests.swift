import XCTest
@testable import MeshKit

final class MeshAgentWalletPolicyExpiryWindowValidatorTests: XCTestCase {
    func testDelegatedSpendingPolicyExpiryWindowAllowsActivePolicyWindow() throws {
        let policy = try delegatedSpendingPolicy(
            startsAt: "2026-05-31T00:00:00Z",
            expiresAt: "2026-05-31T00:10:00Z"
        )

        let result = try policy.evaluateExecutionRequest(
            executionRequest(executionId: "exec-policy-window-active"),
            requestedAt: "2026-05-31T00:05:00Z"
        )

        XCTAssertEqual(result.status, .allowed)
        XCTAssertEqual(result.approvedAmount, Decimal(50))
        XCTAssertNil(result.reason)
    }

    func testDelegatedSpendingPolicyExpiryWindowRejectsExpiredPolicyWindow() throws {
        let policy = try delegatedSpendingPolicy(
            startsAt: "2026-05-31T00:00:00Z",
            expiresAt: "2026-05-31T00:10:00Z"
        )

        let result = try policy.evaluateExecutionRequest(
            executionRequest(executionId: "exec-policy-window-expired"),
            requestedAt: "2026-05-31T00:10:01Z"
        )

        XCTAssertEqual(result.status, .denied)
        XCTAssertNil(result.approvedAmount)
        XCTAssertEqual(result.reason, "policy-expired")
    }

    func testDelegatedSpendingPolicyExpiryWindowRejectsFuturePolicyWindow() throws {
        let policy = try delegatedSpendingPolicy(
            startsAt: "2026-05-31T00:10:00Z",
            expiresAt: "2026-05-31T00:20:00Z"
        )

        let result = try policy.evaluateExecutionRequest(
            executionRequest(executionId: "exec-policy-window-future"),
            requestedAt: "2026-05-31T00:09:59Z"
        )

        XCTAssertEqual(result.status, .denied)
        XCTAssertNil(result.approvedAmount)
        XCTAssertEqual(result.reason, "policy-not-yet-active")
    }

    private func delegatedSpendingPolicy(
        startsAt: String,
        expiresAt: String
    ) throws -> MeshAgentWalletDelegatedSpendingPolicy {
        try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64)),
            consentGrantId: "grant-hermes-dailymart-001",
            merchantScope: "merchant.dailymart",
            capabilityScope: "grocery.purchase_essentials",
            singlePaymentMax: Decimal(100),
            sessionTotalLimit: Decimal(500),
            remainingLimit: Decimal(500),
            startsAt: startsAt,
            expiresAt: expiresAt,
            asset: "OKRW",
            recipientAddress: "maroo1dailyMartMerchant"
        )
    }

    private func executionRequest(executionId: String) throws -> MeshAgentWalletExecutionRequest {
        try MeshAgentWalletExecutionRequest(
            executionId: executionId,
            kind: .payment,
            requestAnchorMetadata: MeshSignedRequestAnchorMetadata(request: signedDailyMartRequest(executionId: executionId)),
            scope: MeshAgentWalletSpendingScope(
                merchantId: "merchant.dailymart",
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                consentGrantId: "grant-hermes-dailymart-001"
            ),
            amount: Decimal(50),
            currencyCode: "KRW",
            tokenSymbol: "OKRW",
            recipientAddress: "maroo1dailyMartMerchant",
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64))
        )
    }

    private func signedDailyMartRequest(executionId: String) -> MeshRequest {
        MeshRequest(
            requestId: "ios-grocery-\(executionId)",
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
                "budget_krw": "50",
                "merchantScope": "merchant.dailymart",
                "capabilityScope": "grocery.purchase_essentials",
                "consentGrantId": "grant-hermes-dailymart-001",
                "policyId": "policy-hermes-dailymart-okrw-v1",
                "policyHash": String(repeating: "f", count: 64)
            ],
            nonce: "nonce-\(executionId)",
            timestamp: "2026-05-31T00:00:00Z",
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "sample-ios-ed25519",
                value: "test-signature"
            )
        )
    }
}
