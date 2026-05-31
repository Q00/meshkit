import XCTest
@testable import MeshKit

final class DailyMartScopeConsentGateTests: XCTestCase {
    func testDailyMartScopeConsentGateAllowsComposedMerchantCapabilityAndConsentGrant() throws {
        let gate = try DailyMartDelegatedSpendingPolicy.scopeConsentGate()

        let result = try gate.evaluate(
            dailyMartRequest(),
            verifiedAt: "2026-05-31T00:00:00Z"
        )

        XCTAssertEqual(result.status, .approved)
        XCTAssertEqual(result.merchantScope, DailyMartDelegatedSpendingPolicy.merchantScope)
        XCTAssertEqual(result.capabilityScope, DailyMartDelegatedSpendingPolicy.capabilityScope)
        XCTAssertEqual(result.consentGrantId, DailyMartDelegatedSpendingPolicy.consentGrantId)
        XCTAssertNil(result.reason)
    }

    func testDailyMartScopeConsentGateDeniesMerchantScopeBeforeExecution() throws {
        let gate = try DailyMartDelegatedSpendingPolicy.scopeConsentGate()
        var payload = dailyMartPayload()
        payload["merchantScope"] = "merchant.other-grocery"

        let result = try gate.evaluate(
            dailyMartRequest(payload: payload),
            verifiedAt: "2026-05-31T00:00:01Z"
        )

        XCTAssertEqual(result.status, .denied)
        XCTAssertEqual(result.reason, "merchant-scope-denied")
    }

    func testDailyMartScopeConsentGateDeniesCapabilityScopeBeforeExecution() throws {
        let gate = try DailyMartDelegatedSpendingPolicy.scopeConsentGate()

        let result = try gate.evaluate(
            dailyMartRequest(capabilityId: "grocery.refund_order"),
            verifiedAt: "2026-05-31T00:00:02Z"
        )

        XCTAssertEqual(result.status, .denied)
        XCTAssertEqual(result.reason, "capability-scope-denied")
    }

    func testDailyMartScopeConsentGateDeniesUnknownConsentGrantBeforeExecution() throws {
        let gate = try DailyMartDelegatedSpendingPolicy.scopeConsentGate()
        var payload = dailyMartPayload()
        payload["consentGrantId"] = "grant-hermes-dailymart-unknown"

        let result = try gate.evaluate(
            dailyMartRequest(payload: payload),
            verifiedAt: "2026-05-31T00:00:03Z"
        )

        XCTAssertEqual(result.status, .denied)
        XCTAssertEqual(result.reason, "consent-grant-denied")
    }

    func testDailyMartScopeConsentGateRequireApprovedStopsPolicyDeniedOutcome() throws {
        let gate = try DailyMartDelegatedSpendingPolicy.scopeConsentGate()
        var payload = dailyMartPayload()
        payload["merchantScope"] = "merchant.other-grocery"

        XCTAssertThrowsError(try gate.requireApproved(
            dailyMartRequest(payload: payload),
            verifiedAt: "2026-05-31T00:00:04Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("merchant-scope-denied"))
        }
    }

    private func dailyMartPayload() -> [String: String] {
        [
            "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6",
            "address_ref": "home.saved",
            "budget_krw": "100",
            "merchantScope": DailyMartDelegatedSpendingPolicy.merchantScope,
            "capabilityScope": DailyMartDelegatedSpendingPolicy.capabilityScope,
            "consentGrantId": DailyMartDelegatedSpendingPolicy.consentGrantId,
            "walletSessionId": DailyMartDelegatedSpendingPolicy.walletSessionId,
            "principalId": DailyMartDelegatedSpendingPolicy.principalId,
            "policyId": DailyMartDelegatedSpendingPolicy.policyId,
            "policyHash": DailyMartDelegatedSpendingPolicy.policyHash.value
        ]
    }

    private func dailyMartRequest(
        capabilityId: String = DailyMartDelegatedSpendingPolicy.capabilityScope,
        payload: [String: String]? = nil
    ) -> MeshRequest {
        MeshRequest(
            requestId: "ios-grocery-scope-consent-gate",
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-sim",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "sample-ios-ed25519"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: capabilityId,
                version: "1.0"
            ),
            payload: payload ?? dailyMartPayload(),
            nonce: "ios-grocery-scope-consent-gate-nonce",
            timestamp: "2026-05-31T00:00:00Z",
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "sample-ios-ed25519",
                value: "test-signature"
            )
        )
    }
}
