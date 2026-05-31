import XCTest
@testable import MeshKit

final class DailyMartDelegatedPolicyScopeValidatorTests: XCTestCase {
    func testDailyMartPolicyScopeValidatorAllowsMerchantAndCapabilityInDelegatedPolicy() throws {
        let validator = try DailyMartDelegatedPolicyScopeValidator(
            policy: DailyMartDelegatedSpendingPolicy.expectedPolicy()
        )

        let result = try validator.requireApproved(
            dailyMartRequest(),
            verifiedAt: "2026-05-31T12:00:00Z"
        )

        XCTAssertEqual(result.status, .approved)
        XCTAssertEqual(result.merchantScope, DailyMartDelegatedSpendingPolicy.merchantScope)
        XCTAssertEqual(
            result.requestedCapabilities,
            [
                DailyMartDelegatedSpendingPolicy.capabilityScope,
                DailyMartDelegatedSpendingPolicy.capabilityScope
            ]
        )
        XCTAssertNil(result.reason)
    }

    func testDailyMartPolicyScopeValidatorRejectsWrongMerchantIdentity() throws {
        let validator = try DailyMartDelegatedPolicyScopeValidator(
            policy: DailyMartDelegatedSpendingPolicy.expectedPolicy()
        )
        var payload = dailyMartPayload()
        payload["merchantScope"] = "merchant.other-grocery"

        let result = try validator.evaluate(
            dailyMartRequest(payload: payload),
            verifiedAt: "2026-05-31T12:00:01Z"
        )

        XCTAssertEqual(result.status, .denied)
        XCTAssertEqual(result.reason, "policy-merchant-scope-mismatch")
    }

    func testDailyMartPolicyScopeValidatorRejectsUnsupportedCapability() throws {
        let validator = try DailyMartDelegatedPolicyScopeValidator(
            policy: DailyMartDelegatedSpendingPolicy.expectedPolicy()
        )

        let result = try validator.evaluate(
            dailyMartRequest(capabilityId: "grocery.issue_refund"),
            verifiedAt: "2026-05-31T12:00:02Z"
        )

        XCTAssertEqual(result.status, .denied)
        XCTAssertEqual(result.reason, "policy-capability-scope-mismatch")
    }

    func testDailyMartPolicyScopeValidatorRejectsOverbroadCapabilityRequest() throws {
        let validator = try DailyMartDelegatedPolicyScopeValidator(
            policy: DailyMartDelegatedSpendingPolicy.expectedPolicy()
        )
        var payload = dailyMartPayload()
        payload["paymentCapabilityScope"] = "\(DailyMartDelegatedSpendingPolicy.capabilityScope),grocery.issue_refund"

        let result = try validator.evaluate(
            dailyMartRequest(payload: payload),
            verifiedAt: "2026-05-31T12:00:03Z"
        )

        XCTAssertEqual(result.status, .denied)
        XCTAssertEqual(result.reason, "policy-capability-scope-mismatch")
        XCTAssertEqual(result.requestedCapabilities.last, "grocery.issue_refund")
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
            requestId: "ios-grocery-policy-scope-validator",
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-device",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "sample-ios-ed25519"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: capabilityId,
                version: "1.0"
            ),
            payload: payload ?? dailyMartPayload(),
            nonce: "ios-grocery-policy-scope-validator-nonce",
            timestamp: "2026-05-31T12:00:00Z",
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "sample-ios-ed25519",
                value: "test-signature"
            )
        )
    }
}
