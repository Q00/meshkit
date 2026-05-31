import XCTest
@testable import MeshKit

final class DailyMartConsentGrantVerifierTests: XCTestCase {
    func testDailyMartConsentGrantExpiryWindowClassifiesValidTimestamp() throws {
        let grant = try DailyMartDelegatedSpendingPolicy.consentGrant(
            startsAt: "2026-05-31T00:00:00Z",
            expiresAt: "2026-05-31T00:10:00Z"
        )

        let status = try grant.validityStatus(verifiedAt: "2026-05-31T00:05:00Z")

        XCTAssertEqual(status, .valid)
    }

    func testDailyMartConsentGrantExpiryWindowClassifiesExpiredTimestamp() throws {
        let grant = try DailyMartDelegatedSpendingPolicy.consentGrant(
            startsAt: "2026-05-31T00:00:00Z",
            expiresAt: "2026-05-31T00:10:00Z"
        )

        let status = try grant.validityStatus(verifiedAt: "2026-05-31T00:10:01Z")

        XCTAssertEqual(status, .expired)
    }

    func testDailyMartConsentGrantExpiryWindowClassifiesNotYetValidTimestamp() throws {
        let grant = try DailyMartDelegatedSpendingPolicy.consentGrant(
            startsAt: "2026-05-31T00:10:00Z",
            expiresAt: "2026-05-31T00:20:00Z"
        )

        let status = try grant.validityStatus(verifiedAt: "2026-05-31T00:09:59Z")

        XCTAssertEqual(status, .notYetValid)
    }

    func testDailyMartConsentGrantVerifierAcceptsGrantBoundToRequestContext() throws {
        let verifier = try DailyMartDelegatedSpendingPolicy.consentGrantVerifier()
        let request = dailyMartRequest()

        let grant = try verifier.verify(request, verifiedAt: "2026-05-31T00:00:00Z")

        XCTAssertEqual(grant.consentGrantId, DailyMartDelegatedSpendingPolicy.consentGrantId)
        XCTAssertEqual(grant.status, .active)
        XCTAssertEqual(grant.callerAppId, request.caller.appId)
        XCTAssertEqual(grant.callerBundleId, request.caller.bundleId)
        XCTAssertEqual(grant.requestContextSubject, DailyMartDelegatedSpendingPolicy.requestContextSubject)
        XCTAssertEqual(grant.requestContextSubject, request.payload["requestContextSubject"])
        XCTAssertEqual(grant.walletSessionId, DailyMartDelegatedSpendingPolicy.walletSessionId)
        XCTAssertEqual(grant.principalId, DailyMartDelegatedSpendingPolicy.principalId)
        XCTAssertEqual(grant.walletSessionId, request.payload["walletSessionId"])
        XCTAssertEqual(grant.principalId, request.payload["principalId"])
        XCTAssertEqual(grant.targetBundleId, request.target.targetBundleId)
        XCTAssertEqual(grant.capabilityId, request.target.capabilityId)
    }

    func testDailyMartConsentGrantVerifierResolvesConsentGrantIdToActiveGrant() throws {
        let activeGrant = try DailyMartDelegatedSpendingPolicy.consentGrant(status: .active)
        let verifier = try DailyMartConsentGrantVerifier(grants: [activeGrant])

        let grant = try verifier.verify(
            dailyMartRequest(),
            verifiedAt: "2026-05-31T00:00:00Z"
        )

        XCTAssertEqual(grant.consentGrantId, DailyMartDelegatedSpendingPolicy.consentGrantId)
        XCTAssertEqual(grant.status, .active)
    }

    func testDailyMartConsentGrantVerifierRejectsRevokedGrant() throws {
        let revokedGrant = try DailyMartDelegatedSpendingPolicy.consentGrant(status: .revoked)
        let verifier = try DailyMartConsentGrantVerifier(grants: [revokedGrant])

        XCTAssertThrowsError(try verifier.verify(
            dailyMartRequest(),
            verifiedAt: "2026-05-31T00:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("consentGrantId.revoked"))
        }
    }

    func testConsentGrantBindingValidationAcceptsMatchingSignerWalletSessionAndRequestAnchor() throws {
        let grant = try DailyMartConsentGrant(
            consentGrantId: DailyMartDelegatedSpendingPolicy.consentGrantId,
            callerAppId: "app.hermes-chat",
            callerBundleId: "ai.meshkit.sample.hermeschat",
            requestContextSubject: DailyMartDelegatedSpendingPolicy.requestContextSubject,
            walletSessionId: DailyMartDelegatedSpendingPolicy.walletSessionId,
            principalId: DailyMartDelegatedSpendingPolicy.principalId,
            targetBundleId: "ai.meshkit.sample.dailymart",
            capabilityId: DailyMartDelegatedSpendingPolicy.capabilityScope,
            merchantScope: DailyMartDelegatedSpendingPolicy.merchantScope,
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            signerKeyId: "sample-ios-ed25519",
            walletAddress: "maroo1dailyMartAgentWallet",
            expiresAt: "2026-12-31T23:59:59Z"
        )
        let verifier = try DailyMartConsentGrantVerifier(grants: [grant])
        let request = dailyMartRequest()
        let requestAnchorMetadata = try MeshSignedRequestAnchorMetadata(request: request)

        let accepted = try verifier.verifyBoundRequest(
            request,
            walletAddress: "maroo1dailyMartAgentWallet",
            requestAnchorMetadata: requestAnchorMetadata,
            verifiedAt: "2026-05-31T00:00:00Z"
        )

        XCTAssertEqual(accepted.consentGrantId, DailyMartDelegatedSpendingPolicy.consentGrantId)
        XCTAssertEqual(accepted.signerKeyId, request.signature.keyId)
        XCTAssertEqual(request.caller.publicKeyId, request.signature.keyId)
        XCTAssertEqual(accepted.walletAddress, "maroo1dailyMartAgentWallet")
        XCTAssertEqual(accepted.walletSessionId, request.payload["walletSessionId"])
        XCTAssertEqual(requestAnchorMetadata.requestId, request.requestId)
        XCTAssertEqual(requestAnchorMetadata.nonce, request.nonce)
        XCTAssertEqual(requestAnchorMetadata.signedRequestHash, try MeshRequestAnchorCanonicalization.signedRequestHash(for: request))
    }

    func testDailyMartConsentGrantVerifierRejectsMissingGrantId() throws {
        let verifier = try DailyMartDelegatedSpendingPolicy.consentGrantVerifier()
        var payload = dailyMartPayload()
        payload.removeValue(forKey: "consentGrantId")

        XCTAssertThrowsError(try verifier.verify(
            dailyMartRequest(payload: payload),
            verifiedAt: "2026-05-31T00:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("consentGrantId"))
        }
    }

    func testDailyMartConsentGrantVerifierRejectsUnknownGrantId() throws {
        let verifier = try DailyMartDelegatedSpendingPolicy.consentGrantVerifier()
        var payload = dailyMartPayload()
        payload["consentGrantId"] = "grant-hermes-dailymart-unknown"

        XCTAssertThrowsError(try verifier.verify(
            dailyMartRequest(payload: payload),
            verifiedAt: "2026-05-31T00:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("consentGrantId.unknown"))
        }
    }

    func testDailyMartConsentGrantVerifierRejectsExpiredGrant() throws {
        let verifier = try DailyMartDelegatedSpendingPolicy.consentGrantVerifier(
            expiresAt: "2026-05-30T23:59:59Z"
        )

        XCTAssertThrowsError(try verifier.verify(
            dailyMartRequest(),
            verifiedAt: "2026-05-31T00:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("consentGrantId.expired"))
        }
    }

    func testDailyMartConsentGrantVerifierRejectsNotYetValidGrant() throws {
        let verifier = try DailyMartDelegatedSpendingPolicy.consentGrantVerifier(
            startsAt: "2026-05-31T00:10:00Z",
            expiresAt: "2026-05-31T00:20:00Z"
        )

        XCTAssertThrowsError(try verifier.verify(
            dailyMartRequest(),
            verifiedAt: "2026-05-31T00:09:59Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("consentGrantId.notYetValid"))
        }
    }

    func testDailyMartConsentGrantVerifierRejectsGrantBoundToDifferentContext() throws {
        let verifier = try DailyMartDelegatedSpendingPolicy.consentGrantVerifier()

        XCTAssertThrowsError(try verifier.verify(
            dailyMartRequest(callerAppId: "app.other-agent"),
            verifiedAt: "2026-05-31T00:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("consentGrantId.context"))
        }
    }

    func testDailyMartConsentGrantVerifierRejectsActiveGrantBoundToDifferentRequestContextSubject() throws {
        let grant = try DailyMartConsentGrant(
            consentGrantId: DailyMartDelegatedSpendingPolicy.consentGrantId,
            callerAppId: "app.hermes-chat",
            callerBundleId: "ai.meshkit.sample.hermeschat",
            requestContextSubject: "principal-other-agent-001",
            walletSessionId: DailyMartDelegatedSpendingPolicy.walletSessionId,
            principalId: DailyMartDelegatedSpendingPolicy.principalId,
            targetBundleId: "ai.meshkit.sample.dailymart",
            capabilityId: DailyMartDelegatedSpendingPolicy.capabilityScope,
            merchantScope: DailyMartDelegatedSpendingPolicy.merchantScope,
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            signerKeyId: "sample-ios-ed25519",
            walletAddress: "maroo1dailyMartAgentWallet",
            expiresAt: "2026-12-31T23:59:59Z",
            status: .active
        )
        let verifier = try DailyMartConsentGrantVerifier(grants: [grant])

        XCTAssertThrowsError(try verifier.verify(
            dailyMartRequest(),
            verifiedAt: "2026-05-31T00:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("requestContextSubject"))
        }
    }

    func testDailyMartConsentGrantVerifierRejectsWrongWalletSessionBinding() throws {
        let verifier = try DailyMartDelegatedSpendingPolicy.consentGrantVerifier()
        var payload = dailyMartPayload()
        payload["walletSessionId"] = "wallet-session-other"

        XCTAssertThrowsError(try verifier.verify(
            dailyMartRequest(payload: payload),
            verifiedAt: "2026-05-31T00:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("walletSessionId"))
        }
    }

    func testDailyMartConsentGrantVerifierRejectsWrongPrincipalBinding() throws {
        let verifier = try DailyMartDelegatedSpendingPolicy.consentGrantVerifier()
        var payload = dailyMartPayload()
        payload["principalId"] = "principal-other-agent"

        XCTAssertThrowsError(try verifier.verify(
            dailyMartRequest(payload: payload),
            verifiedAt: "2026-05-31T00:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("principalId"))
        }
    }

    func testDailyMartPolicyVerificationRejectsExpiredConsentGrantBeforePolicyApproval() throws {
        XCTAssertThrowsError(try DailyMartDelegatedSpendingPolicy.verifyRequest(
            dailyMartRequest(),
            verifiedAt: "2026-05-31T00:00:00Z",
            expiresAt: "2026-05-30T23:59:59Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("consent-grant-expired"))
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
            "requestContextSubject": DailyMartDelegatedSpendingPolicy.requestContextSubject,
            "policyId": DailyMartDelegatedSpendingPolicy.policyId,
            "policyHash": DailyMartDelegatedSpendingPolicy.policyHash.value
        ]
    }

    private func dailyMartRequest(
        callerAppId: String = "app.hermes-chat",
        callerBundleId: String = "ai.meshkit.sample.hermeschat",
        targetBundleId: String = "ai.meshkit.sample.dailymart",
        capabilityId: String = DailyMartDelegatedSpendingPolicy.capabilityScope,
        payload: [String: String]? = nil
    ) -> MeshRequest {
        MeshRequest(
            requestId: "ios-grocery-consent-grant",
            caller: MeshIdentity(
                appId: callerAppId,
                installId: "ios-sim",
                bundleId: callerBundleId,
                publicKeyId: "sample-ios-ed25519"
            ),
            target: MeshCapability(
                targetBundleId: targetBundleId,
                capabilityId: capabilityId,
                version: "1.0"
            ),
            payload: payload ?? dailyMartPayload(),
            nonce: "ios-grocery-consent-grant-nonce",
            timestamp: "2026-05-31T00:00:00Z",
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "sample-ios-ed25519",
                value: "test-signature"
            )
        )
    }
}
