import XCTest
@testable import MeshKit

final class DailyMartMerchantConsentScopeValidatorTests: XCTestCase {
    func testMerchantConsentScopeValidatorAcceptsMerchantIncludedInConsentGrant() throws {
        let validator = try DailyMartDelegatedSpendingPolicy.merchantConsentScopeValidator()

        let grant = try validator.validate(
            dailyMartRequest(),
            verifiedAt: "2026-05-31T00:00:00Z"
        )

        XCTAssertEqual(grant.consentGrantId, DailyMartDelegatedSpendingPolicy.consentGrantId)
        XCTAssertEqual(grant.merchantScope, DailyMartDelegatedSpendingPolicy.merchantScope)
    }

    func testMerchantConsentScopeValidatorRejectsMerchantOutsideConsentGrant() throws {
        let validator = try DailyMartDelegatedSpendingPolicy.merchantConsentScopeValidator()
        var payload = dailyMartPayload()
        payload["merchantScope"] = "merchant.other-grocery"

        XCTAssertThrowsError(try validator.validate(
            dailyMartRequest(payload: payload),
            verifiedAt: "2026-05-31T00:00:00Z"
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

    private func dailyMartRequest(payload: [String: String]? = nil) -> MeshRequest {
        MeshRequest(
            requestId: "ios-grocery-merchant-consent-scope",
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-sim",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "sample-ios-ed25519"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: DailyMartDelegatedSpendingPolicy.capabilityScope,
                version: "1.0"
            ),
            payload: payload ?? dailyMartPayload(),
            nonce: "ios-grocery-merchant-consent-scope-nonce",
            timestamp: "2026-05-31T00:00:00Z",
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "sample-ios-ed25519",
                value: "test-signature"
            )
        )
    }
}
