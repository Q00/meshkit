import XCTest
@testable import MeshKit

final class DailyMartDelegatedSpendingPolicyVerifierTests: XCTestCase {
    func testDailyMartDelegatedPolicyVerifierApprovesMatchingPolicyIdAndHash() throws {
        let verifier = try DailyMartDelegatedSpendingPolicy.verifier()

        let result = try verifier.verify(
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash,
            verifiedAt: "2026-05-31T00:00:00Z"
        )

        XCTAssertEqual(result.status, .approved)
        XCTAssertEqual(result.policyId, DailyMartDelegatedSpendingPolicy.policyId)
        XCTAssertEqual(result.policyHash, DailyMartDelegatedSpendingPolicy.policyHash)
        XCTAssertNil(result.reason)
    }

    func testDailyMartPolicyVerificationApprovesRequestReferencingMatchingDelegatedPolicy() throws {
        let request = dailyMartRequest(payload: dailyMartPayload(merchantScope: DailyMartDelegatedSpendingPolicy.merchantScope))

        let result = try DailyMartDelegatedSpendingPolicy.verifyRequest(
            request,
            verifiedAt: "2026-05-31T00:00:00Z"
        )

        XCTAssertEqual(result.status, .approved)
        XCTAssertEqual(result.policyId, DailyMartDelegatedSpendingPolicy.policyId)
        XCTAssertEqual(result.policyHash, DailyMartDelegatedSpendingPolicy.policyHash)
        XCTAssertNil(result.reason)
    }

    func testDailyMartDelegatedPolicyVerifierDeniesMismatchedPolicyId() throws {
        let verifier = try DailyMartDelegatedSpendingPolicy.verifier()

        let result = try verifier.verify(
            policyId: "policy-hermes-dailymart-okrw-v2",
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash,
            verifiedAt: "2026-05-31T00:00:01Z"
        )

        XCTAssertEqual(result.status, .denied)
        XCTAssertEqual(result.reason, "policy-id-mismatch")
        XCTAssertEqual(result.policyHash, DailyMartDelegatedSpendingPolicy.policyHash)
    }

    func testDailyMartPolicyVerificationDeniesRequestWithWrongPolicyId() throws {
        var payload = dailyMartPayload(merchantScope: DailyMartDelegatedSpendingPolicy.merchantScope)
        payload["policyId"] = "policy-hermes-dailymart-okrw-wrong"
        let request = dailyMartRequest(payload: payload)

        let result = try DailyMartDelegatedSpendingPolicy.verifyRequest(
            request,
            verifiedAt: "2026-05-31T00:00:01Z"
        )

        XCTAssertEqual(result.status, .denied)
        XCTAssertEqual(result.reason, "policy-id-mismatch")
        XCTAssertEqual(result.policyId, "policy-hermes-dailymart-okrw-wrong")
        XCTAssertEqual(result.policyHash, DailyMartDelegatedSpendingPolicy.policyHash)
    }

    func testDailyMartDelegatedPolicyVerifierDeniesMismatchedPolicyHash() throws {
        let verifier = try DailyMartDelegatedSpendingPolicy.verifier()

        let result = try verifier.verify(
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: MeshPayloadHash(value: String(repeating: "a", count: 64)),
            verifiedAt: "2026-05-31T00:00:02Z"
        )

        XCTAssertEqual(result.status, .denied)
        XCTAssertEqual(result.reason, "policy-hash-mismatch")
        XCTAssertEqual(result.policyId, DailyMartDelegatedSpendingPolicy.policyId)
    }

    func testDailyMartPolicyVerificationRejectsKnownPolicyIdWithUnexpectedRequestPolicyHash() throws {
        let request = dailyMartRequest(
            payload: [
                "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6",
                "address_ref": "home.saved",
                "budget_krw": "100",
                "merchantScope": DailyMartDelegatedSpendingPolicy.merchantScope,
                "capabilityScope": DailyMartDelegatedSpendingPolicy.capabilityScope,
                "consentGrantId": DailyMartDelegatedSpendingPolicy.consentGrantId,
                "walletSessionId": DailyMartDelegatedSpendingPolicy.walletSessionId,
                "principalId": DailyMartDelegatedSpendingPolicy.principalId,
                "policyId": DailyMartDelegatedSpendingPolicy.policyId,
                "policyHash": String(repeating: "a", count: 64)
            ]
        )

        let result = try DailyMartDelegatedSpendingPolicy.verifyRequest(
            request,
            verifiedAt: "2026-05-31T00:00:04Z"
        )

        XCTAssertEqual(result.status, .denied)
        XCTAssertEqual(result.reason, "policy-hash-mismatch")
        XCTAssertEqual(result.policyId, DailyMartDelegatedSpendingPolicy.policyId)
        XCTAssertEqual(result.policyHash, MeshPayloadHash(value: String(repeating: "a", count: 64)))
    }

    func testDailyMartPolicyVerificationRejectsRequestWithNoResolvableDelegatedPolicy() throws {
        var payload = dailyMartPayload(merchantScope: DailyMartDelegatedSpendingPolicy.merchantScope)
        payload.removeValue(forKey: "policyId")
        let request = dailyMartRequest(payload: payload)

        XCTAssertThrowsError(try DailyMartDelegatedSpendingPolicy.verifyRequest(
            request,
            verifiedAt: "2026-05-31T00:00:06Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("missing-policy"))
        }
    }

    func testDailyMartMerchantScopeValidatorAllowsAuthorizedMerchantScope() throws {
        let validator = try DailyMartMerchantScopeValidator()
        let request = dailyMartRequest(
            payload: dailyMartPayload(merchantScope: DailyMartDelegatedSpendingPolicy.merchantScope)
        )

        XCTAssertNoThrow(try validator.validate(request))
    }

    func testDailyMartMerchantScopeValidatorRejectsMissingMerchantScope() throws {
        let validator = try DailyMartMerchantScopeValidator()
        var payload = dailyMartPayload(merchantScope: DailyMartDelegatedSpendingPolicy.merchantScope)
        payload.removeValue(forKey: "merchantScope")
        let request = dailyMartRequest(payload: payload)

        XCTAssertThrowsError(try validator.validate(request)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("merchantScope"))
        }
    }

    func testDailyMartMerchantScopeValidatorRejectsMismatchedMerchantScope() throws {
        let validator = try DailyMartMerchantScopeValidator()
        let request = dailyMartRequest(payload: dailyMartPayload(merchantScope: "merchant.other-grocery"))

        XCTAssertThrowsError(try validator.validate(request)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("merchantScope"))
        }
    }

    func testDailyMartPolicyVerificationRejectsMissingMerchantScopeBeforePolicyApproval() throws {
        var payload = dailyMartPayload(merchantScope: DailyMartDelegatedSpendingPolicy.merchantScope)
        payload.removeValue(forKey: "merchantScope")
        let request = dailyMartRequest(payload: payload)

        XCTAssertThrowsError(try DailyMartDelegatedSpendingPolicy.verifyRequest(
            request,
            verifiedAt: "2026-05-31T00:00:05Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("merchant-scope-denied"))
        }
    }

    func testDailyMartDelegatedPolicyVerifierRejectsMalformedPolicyHash() throws {
        let verifier = try DailyMartDelegatedSpendingPolicy.verifier()

        XCTAssertThrowsError(try verifier.verify(
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: MeshPayloadHash(value: "not-a-sha256"),
            verifiedAt: "2026-05-31T00:00:03Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("policyHash.value"))
        }
    }

    private func dailyMartPayload(merchantScope: String) -> [String: String] {
        [
            "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6",
            "address_ref": "home.saved",
            "budget_krw": "100",
            "merchantScope": merchantScope,
            "capabilityScope": DailyMartDelegatedSpendingPolicy.capabilityScope,
            "consentGrantId": DailyMartDelegatedSpendingPolicy.consentGrantId,
            "walletSessionId": DailyMartDelegatedSpendingPolicy.walletSessionId,
            "principalId": DailyMartDelegatedSpendingPolicy.principalId,
            "policyId": DailyMartDelegatedSpendingPolicy.policyId,
            "policyHash": DailyMartDelegatedSpendingPolicy.policyHash.value
        ]
    }

    private func dailyMartRequest(payload: [String: String]) -> MeshRequest {
        MeshRequest(
            requestId: "ios-grocery-policy-hash-mismatch",
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-sim",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "sample-ios-ed25519"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                version: "1.0"
            ),
            payload: payload,
            nonce: "ios-grocery-policy-hash-mismatch-nonce",
            timestamp: "2026-05-31T00:00:04Z",
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "sample-ios-ed25519",
                value: "test-signature"
            )
        )
    }
}
