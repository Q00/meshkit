import XCTest
@testable import MeshKit

final class DailyMartCapabilityScopeValidatorTests: XCTestCase {
    func testDailyMartCapabilityScopeValidatorAllowsConsentedCapability() throws {
        let validator = try DailyMartCapabilityScopeValidator()

        XCTAssertNoThrow(try validator.validate(dailyMartRequest()))
    }

    func testDailyMartCapabilityScopeValidatorAllowsRequestedCapabilitiesInsideConsentGrant() throws {
        let validator = try DailyMartCapabilityScopeValidator(
            consentGrantId: "grant-hermes-dailymart-expanded",
            consentedCapabilities: [
                DailyMartDelegatedSpendingPolicy.capabilityScope,
                "grocery.check_inventory"
            ]
        )

        XCTAssertNoThrow(try validator.validate(
            requestedCapabilities: [
                DailyMartDelegatedSpendingPolicy.capabilityScope,
                "grocery.check_inventory"
            ],
            consentGrantId: "grant-hermes-dailymart-expanded"
        ))
    }

    func testDailyMartCapabilityScopeValidatorRejectsRequestedCapabilityOutsideConsentGrant() throws {
        let validator = try DailyMartCapabilityScopeValidator(
            consentGrantId: "grant-hermes-dailymart-expanded",
            consentedCapabilities: [
                DailyMartDelegatedSpendingPolicy.capabilityScope,
                "grocery.check_inventory"
            ]
        )

        XCTAssertThrowsError(try validator.validate(
            requestedCapabilities: [
                DailyMartDelegatedSpendingPolicy.capabilityScope,
                "grocery.issue_refund"
            ],
            consentGrantId: "grant-hermes-dailymart-expanded"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("capabilityScope"))
        }
    }

    func testDailyMartCapabilityScopeValidatorCanUseConsentGrantAsScopeSource() throws {
        let validator = try DailyMartCapabilityScopeValidator(
            consentGrant: DailyMartDelegatedSpendingPolicy.consentGrant()
        )

        XCTAssertNoThrow(try validator.validate(
            requestedCapabilities: [DailyMartDelegatedSpendingPolicy.capabilityScope],
            consentGrantId: DailyMartDelegatedSpendingPolicy.consentGrantId
        ))
    }

    func testDailyMartCapabilityScopeValidatorRejectsMissingCapabilityScope() throws {
        let validator = try DailyMartCapabilityScopeValidator()
        var payload = dailyMartPayload()
        payload.removeValue(forKey: "capabilityScope")

        XCTAssertThrowsError(try validator.validate(dailyMartRequest(payload: payload))) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("capabilityScope"))
        }
    }

    func testDailyMartCapabilityScopeValidatorRejectsOutOfScopePayloadCapability() throws {
        let validator = try DailyMartCapabilityScopeValidator()
        var payload = dailyMartPayload()
        payload["capabilityScope"] = "grocery.refund_order"

        XCTAssertThrowsError(try validator.validate(dailyMartRequest(payload: payload))) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("capabilityScope"))
        }
    }

    func testDailyMartCapabilityScopeValidatorRejectsOutOfScopeTargetCapability() throws {
        let validator = try DailyMartCapabilityScopeValidator()

        XCTAssertThrowsError(try validator.validate(dailyMartRequest(capabilityId: "grocery.refund_order"))) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("capabilityScope"))
        }
    }

    func testDailyMartCapabilityScopeValidatorRejectsMissingConsentGrant() throws {
        let validator = try DailyMartCapabilityScopeValidator()
        var payload = dailyMartPayload()
        payload.removeValue(forKey: "consentGrantId")

        XCTAssertThrowsError(try validator.validate(dailyMartRequest(payload: payload))) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("consentGrantId"))
        }
    }

    func testDailyMartPolicyVerificationRejectsMissingCapabilityScopeBeforePolicyApproval() throws {
        var payload = dailyMartPayload()
        payload.removeValue(forKey: "capabilityScope")

        XCTAssertThrowsError(try DailyMartDelegatedSpendingPolicy.verifyRequest(
            dailyMartRequest(payload: payload),
            verifiedAt: "2026-05-31T00:00:06Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("capability-scope-denied"))
        }
    }

    func testDailyMartPolicyVerificationRejectsOutOfScopeCapabilityBeforePolicyApproval() throws {
        XCTAssertThrowsError(try DailyMartDelegatedSpendingPolicy.verifyRequest(
            dailyMartRequest(capabilityId: "grocery.refund_order"),
            verifiedAt: "2026-05-31T00:00:07Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("capability-scope-denied"))
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
            requestId: "ios-grocery-capability-scope",
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
            nonce: "ios-grocery-capability-scope-nonce",
            timestamp: "2026-05-31T00:00:06Z",
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "sample-ios-ed25519",
                value: "test-signature"
            )
        )
    }
}
