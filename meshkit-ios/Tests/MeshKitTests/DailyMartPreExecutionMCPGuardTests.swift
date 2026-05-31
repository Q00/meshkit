import CryptoKit
import XCTest
@testable import MeshKit

final class DailyMartPreExecutionMCPGuardTests: XCTestCase {
    private let signingKey = Curve25519.Signing.PrivateKey()
    private let referenceDate = ISO8601DateFormatter().date(from: "2026-05-31T12:00:00Z")!

    func testPreExecutionGuardAcceptsValidFreshSignedRequest() throws {
        let guardModule = try makeGuard()
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-valid",
            nonce: "nonce-dailymart-pre-exec-valid",
            timestamp: "2026-05-31T12:00:00Z"
        )

        let accepted = try guardModule.acceptForPreExecution(request, now: referenceDate)

        XCTAssertEqual(accepted.requestId, "ios-grocery-pre-exec-valid")
        XCTAssertEqual(accepted.nonce, "nonce-dailymart-pre-exec-valid")
    }

    func testPreExecutionGuardAcceptsSignedRequestForWalletPolicyExecution() throws {
        let guardModule = try makeGuard(walletPolicyGuard: DailyMartPreExecutionWalletPolicyGuard())
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-wallet-valid",
            nonce: "nonce-dailymart-pre-exec-wallet-valid",
            timestamp: "2026-05-31T12:00:00Z"
        )

        let accepted = try guardModule.acceptForWalletExecution(
            request,
            executionKind: .payment,
            executionId: "exec-ios-grocery-pre-exec-wallet-valid",
            now: referenceDate,
            verifiedAt: "2026-05-31T12:00:00Z"
        )

        XCTAssertEqual(accepted.requestId, "ios-grocery-pre-exec-wallet-valid")
        XCTAssertEqual(accepted.scopeConsent.status, .approved)
        XCTAssertEqual(accepted.policyVerification.status, .approved)
        XCTAssertEqual(accepted.policyEvaluation.status, .allowed)
        XCTAssertEqual(accepted.executionRequest.amount, Decimal(100))
        XCTAssertEqual(accepted.executionRequest.tokenSymbol, DailyMartDelegatedSpendingPolicy.asset)
        XCTAssertEqual(accepted.executionRequest.recipientAddress, DailyMartDelegatedSpendingPolicy.recipientAddress)
        XCTAssertEqual(accepted.availableLimitBeforeExecution, Decimal(100))
    }

    func testConsentGuardApprovesDelegatedAgentConsentForExactDailyMartAction() throws {
        let consentGuard = try DailyMartPreExecutionConsentGuard()
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-delegated-consent",
            nonce: "nonce-dailymart-pre-exec-delegated-consent",
            timestamp: "2026-05-31T12:00:00Z"
        )

        let result = try consentGuard.requireApproved(
            request,
            verifiedAt: "2026-05-31T12:00:00Z"
        )

        XCTAssertEqual(result.status, .approved)
        XCTAssertEqual(result.source, .delegatedAgent)
        XCTAssertEqual(result.consentGrantId, DailyMartDelegatedSpendingPolicy.consentGrantId)
        XCTAssertEqual(result.capabilityId, DailyMartDelegatedSpendingPolicy.capabilityScope)
    }

    func testPreExecutionGuardAcceptsSignedRequestBoundToConsentGrantWalletSessionAndPrincipal() throws {
        let guardModule = try makeGuard()
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-bound-consent",
            nonce: "nonce-dailymart-pre-exec-bound-consent",
            timestamp: "2026-05-31T12:00:00Z"
        )

        let accepted = try guardModule.acceptForPreExecution(request, now: referenceDate)

        XCTAssertEqual(accepted.payload["consentGrantId"], DailyMartDelegatedSpendingPolicy.consentGrantId)
        XCTAssertEqual(accepted.payload["walletSessionId"], DailyMartDelegatedSpendingPolicy.walletSessionId)
        XCTAssertEqual(accepted.payload["principalId"], DailyMartDelegatedSpendingPolicy.principalId)
    }

    func testPreExecutionGuardRejectsSignedRequestWithWrongWalletSessionBinding() throws {
        let guardModule = try makeGuard()
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-wrong-wallet-session",
            nonce: "nonce-dailymart-pre-exec-wrong-wallet-session",
            timestamp: "2026-05-31T12:00:00Z",
            payloadOverrides: ["walletSessionId": "wallet-session-other"]
        )

        XCTAssertThrowsError(try guardModule.acceptForPreExecution(request, now: referenceDate)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .consentRequired("consent-grant-context"))
        }
    }

    func testPreExecutionGuardRejectsSignedRequestWithWrongPrincipalBinding() throws {
        let guardModule = try makeGuard()
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-wrong-principal",
            nonce: "nonce-dailymart-pre-exec-wrong-principal",
            timestamp: "2026-05-31T12:00:00Z",
            payloadOverrides: ["principalId": "principal-other-agent"]
        )

        XCTAssertThrowsError(try guardModule.acceptForPreExecution(request, now: referenceDate)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .consentRequired("consent-grant-context"))
        }
    }

    func testConsentGuardApprovesForegroundUserConsentForExactDailyMartAction() throws {
        let consentGuard = try DailyMartPreExecutionConsentGuard()
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-user-consent",
            nonce: "nonce-dailymart-pre-exec-user-consent",
            timestamp: "2026-05-31T12:00:00Z",
            payloadOverrides: [
                "consentGrantId": nil,
                "userConsentId": "user-consent-dailymart-grocery-001",
                "userConsentStatus": "approved",
                "userConsentTargetBundleId": "ai.meshkit.sample.dailymart",
                "userConsentCapabilityId": DailyMartDelegatedSpendingPolicy.capabilityScope
            ]
        )

        let result = try consentGuard.requireApproved(
            request,
            verifiedAt: "2026-05-31T12:00:00Z"
        )

        XCTAssertEqual(result.status, .approved)
        XCTAssertEqual(result.source, .user)
        XCTAssertEqual(result.userConsentId, "user-consent-dailymart-grocery-001")
        XCTAssertNil(result.consentGrantId)
    }

    func testPreExecutionGuardRejectsRequestWithoutUserOrDelegatedConsentBeforeNonceReservation() throws {
        let guardModule = try makeGuard()
        let missingConsent = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-missing-consent",
            nonce: "nonce-dailymart-pre-exec-consent-retry",
            timestamp: "2026-05-31T12:00:00Z",
            payloadOverrides: ["consentGrantId": nil]
        )
        let validRetry = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-consent-retry",
            nonce: "nonce-dailymart-pre-exec-consent-retry",
            timestamp: "2026-05-31T12:00:01Z"
        )

        XCTAssertThrowsError(try guardModule.acceptForPreExecution(missingConsent, now: referenceDate)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .consentRequired("consent-grant-denied"))
        }
        XCTAssertNoThrow(try guardModule.acceptForPreExecution(validRetry, now: referenceDate))
    }

    func testPreExecutionGuardRejectsConsentForDifferentTargetAction() throws {
        let guardModule = try makeGuard()
        let wrongAction = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-wrong-user-consent-action",
            nonce: "nonce-dailymart-pre-exec-wrong-user-consent-action",
            timestamp: "2026-05-31T12:00:00Z",
            payloadOverrides: [
                "consentGrantId": nil,
                "userConsentId": "user-consent-dailymart-refund-001",
                "userConsentStatus": "approved",
                "userConsentTargetBundleId": "ai.meshkit.sample.dailymart",
                "userConsentCapabilityId": "grocery.refund_order"
            ]
        )

        XCTAssertThrowsError(try guardModule.acceptForPreExecution(wrongAction, now: referenceDate)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .consentRequired("consent-required"))
        }
    }

    func testWalletPolicyGuardRejectsRequestAboveDelegatedSpendingLimitBeforeExecution() throws {
        let guardModule = try DailyMartPreExecutionWalletPolicyGuard()
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-over-single-limit",
            nonce: "nonce-dailymart-pre-exec-over-single-limit",
            timestamp: "2026-05-31T12:00:00Z",
            payloadOverrides: ["budget_krw": "101"]
        )

        XCTAssertThrowsError(try guardModule.evaluate(
            request,
            executionKind: .payment,
            executionId: "exec-ios-grocery-pre-exec-over-single-limit",
            verifiedAt: "2026-05-31T12:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("policy-single-payment-max-exceeded"))
        }
    }

    func testWalletPolicyGuardRejectsRequestWhenRemainingLimitIsReservedBeforeExecution() throws {
        let firstRequest = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-reserved-first",
            nonce: "nonce-dailymart-pre-exec-reserved-first",
            timestamp: "2026-05-31T12:00:00Z",
            payloadOverrides: ["budget_krw": "80"]
        )
        let emptyGuard = try DailyMartPreExecutionWalletPolicyGuard()
        let reservedExecution = try emptyGuard.makeExecutionRequest(
            from: firstRequest,
            executionKind: .payment,
            executionId: "exec-ios-grocery-pre-exec-reserved-first"
        )
        let accounting = try MeshAgentWalletDelegatedSpendAccounting(
            policy: DailyMartDelegatedSpendingPolicy.expectedPolicy()
        ).reservingPendingExecution(
            reservedExecution,
            recordedAt: "2026-05-31T12:00:00Z"
        )
        let guardModule = try DailyMartPreExecutionWalletPolicyGuard(accounting: accounting)
        let secondRequest = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-reserved-second",
            nonce: "nonce-dailymart-pre-exec-reserved-second",
            timestamp: "2026-05-31T12:00:01Z",
            payloadOverrides: ["budget_krw": "30"]
        )

        XCTAssertThrowsError(try guardModule.evaluate(
            secondRequest,
            executionKind: .payment,
            executionId: "exec-ios-grocery-pre-exec-reserved-second",
            verifiedAt: "2026-05-31T12:00:01Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("availableLimit"))
        }
    }

    func testWalletPolicyGuardRejectsUnauthorizedOKRWAssetScopeBeforeExecution() throws {
        let guardModule = try DailyMartPreExecutionWalletPolicyGuard()
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-usdc",
            nonce: "nonce-dailymart-pre-exec-usdc",
            timestamp: "2026-05-31T12:00:00Z",
            payloadOverrides: ["payment_asset": "USDC"]
        )

        XCTAssertThrowsError(try guardModule.evaluate(
            request,
            executionKind: .payment,
            executionId: "exec-ios-grocery-pre-exec-usdc",
            verifiedAt: "2026-05-31T12:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("policy-asset-mismatch"))
        }
    }

    func testWalletPolicyGuardRejectsMismatchedRequestPolicyHashBeforeExecution() throws {
        let guardModule = try DailyMartPreExecutionWalletPolicyGuard()
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-policy-hash-mismatch",
            nonce: "nonce-dailymart-pre-exec-policy-hash-mismatch",
            timestamp: "2026-05-31T12:00:00Z",
            payloadOverrides: ["policyHash": String(repeating: "a", count: 64)]
        )

        XCTAssertThrowsError(try guardModule.evaluate(
            request,
            executionKind: .payment,
            executionId: "exec-ios-grocery-pre-exec-policy-hash-mismatch",
            verifiedAt: "2026-05-31T12:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("policy-hash-mismatch"))
        }
    }

    func testWalletPolicyGuardRejectsUnauthorizedRecipientScopeBeforeExecution() throws {
        let guardModule = try DailyMartPreExecutionWalletPolicyGuard()
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-wrong-recipient",
            nonce: "nonce-dailymart-pre-exec-wrong-recipient",
            timestamp: "2026-05-31T12:00:00Z",
            payloadOverrides: ["recipientAddress": "maroo1unapprovedMerchant"]
        )

        XCTAssertThrowsError(try guardModule.evaluate(
            request,
            executionKind: .transfer,
            executionId: "exec-ios-grocery-pre-exec-wrong-recipient",
            verifiedAt: "2026-05-31T12:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("policy-recipient-address-mismatch"))
        }
    }

    func testWalletPolicyGuardRejectsUnauthorizedCapabilityScopeBeforeExecution() throws {
        let guardModule = try DailyMartPreExecutionWalletPolicyGuard()
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-refund-scope",
            nonce: "nonce-dailymart-pre-exec-refund-scope",
            timestamp: "2026-05-31T12:00:00Z",
            capabilityId: "grocery.refund_order",
            payloadOverrides: ["capabilityScope": "grocery.refund_order"]
        )

        XCTAssertThrowsError(try guardModule.evaluate(
            request,
            executionKind: .payment,
            executionId: "exec-ios-grocery-pre-exec-refund-scope",
            verifiedAt: "2026-05-31T12:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("capability-scope-denied"))
        }
    }

    func testPreExecutionGuardRejectsInvalidSignatureBeforeExecution() throws {
        let guardModule = try makeGuard()
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-bad-signature",
            nonce: "nonce-dailymart-pre-exec-bad-signature",
            timestamp: "2026-05-31T12:00:00Z",
            signatureValue: Data(repeating: 1, count: 64).base64EncodedString()
        )

        XCTAssertThrowsError(try guardModule.acceptForPreExecution(request, now: referenceDate)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("invalid request signature"))
        }
    }

    func testPreExecutionGuardRejectsTamperedPayloadBeforeExecution() throws {
        let guardModule = try makeGuard()
        let original = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-tampered",
            nonce: "nonce-dailymart-pre-exec-tampered",
            timestamp: "2026-05-31T12:00:00Z"
        )
        var tamperedPayload = original.payload
        tamperedPayload["budget_krw"] = "500"
        let tampered = MeshRequest(
            requestId: original.requestId,
            caller: original.caller,
            target: original.target,
            payload: tamperedPayload,
            payloadHash: original.payloadHash,
            nonce: original.nonce,
            timestamp: original.timestamp,
            signature: original.signature
        )

        XCTAssertThrowsError(try guardModule.acceptForPreExecution(tampered, now: referenceDate)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .payloadHashMismatch)
        }
    }

    func testPreExecutionGuardRejectsStaleRequestBeforeExecution() throws {
        let guardModule = try makeGuard()
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-stale",
            nonce: "nonce-dailymart-pre-exec-stale",
            timestamp: "2026-05-31T11:54:59Z"
        )

        XCTAssertThrowsError(try guardModule.acceptForPreExecution(request, now: referenceDate)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .staleTimestamp)
        }
    }

    func testPreExecutionGuardRejectsReplayedRequestBeforeExecution() throws {
        let guardModule = try makeGuard()
        let original = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-replay-001",
            nonce: "nonce-dailymart-pre-exec-replay",
            timestamp: "2026-05-31T12:00:00Z"
        )
        let replay = try signedDailyMartRequest(
            requestId: "ios-grocery-pre-exec-replay-002",
            nonce: "nonce-dailymart-pre-exec-replay",
            timestamp: "2026-05-31T12:00:01Z"
        )

        XCTAssertNoThrow(try guardModule.acceptForPreExecution(original, now: referenceDate))
        XCTAssertThrowsError(try guardModule.acceptForPreExecution(replay, now: referenceDate)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .replayDetected("nonce-dailymart-pre-exec-replay"))
        }
    }

    private func makeGuard(
        walletPolicyGuard: DailyMartPreExecutionWalletPolicyGuard? = nil
    ) throws -> DailyMartPreExecutionMCPGuard {
        try DailyMartPreExecutionMCPGuard(
            expectedHermesAgentSigner: MeshSenderTrust(
                callerAppId: "app.hermes-chat",
                callerBundleId: "ai.meshkit.sample.hermeschat",
                teamId: "DEVTEAMID",
                requestSigningAlgorithm: "Ed25519",
                requestSigningKeyId: "demo-key",
                publicKey: signingKey.publicKey.rawRepresentation.base64EncodedString()
            ),
            freshnessStore: DailyMartRequestNonceFreshnessStore(
                expirationValidator: DailyMartRequestNonceExpirationValidator(maxAgeSeconds: 300)
            ),
            walletPolicyGuard: walletPolicyGuard
        )
    }

    private func signedDailyMartRequest(
        requestId: String,
        nonce: String,
        timestamp: String,
        capabilityId: String = DailyMartDelegatedSpendingPolicy.capabilityScope,
        payloadOverrides: [String: String?] = [:],
        signatureValue: String? = nil
    ) throws -> MeshRequest {
        var payload = [
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
        for (key, value) in payloadOverrides {
            payload[key] = value
        }
        let unsigned = MeshRequest(
            requestId: requestId,
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-device",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "demo-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: capabilityId,
                version: "1.0"
            ),
            payload: payload,
            nonce: nonce,
            timestamp: timestamp,
            signature: MeshSignature(algorithm: "Ed25519", keyId: "demo-key", value: "")
        )
        let signature = try signingKey.signature(for: unsigned.signingInputData()).base64EncodedString()
        return MeshRequest(
            requestId: unsigned.requestId,
            caller: unsigned.caller,
            target: unsigned.target,
            payload: unsigned.payload,
            payloadHash: unsigned.payloadHash,
            nonce: unsigned.nonce,
            timestamp: unsigned.timestamp,
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "demo-key",
                value: signatureValue ?? signature
            )
        )
    }
}
