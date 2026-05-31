import CryptoKit
import XCTest
@testable import MeshKit

final class DailyMartGuardOrchestrationTests: XCTestCase {
    private let signingKey = Curve25519.Signing.PrivateKey()
    private let receiptSigningKey = Curve25519.Signing.PrivateKey()
    private let referenceDate = ISO8601DateFormatter().date(from: "2026-05-31T12:00:00Z")!

    func testOrchestratorInvokesAnchoringThenOKRWExecutionOnlyAfterAllGuardsPass() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentExecutor = try RecordingPaymentExecutor(
            identity: anchorProvider.identity,
            recorder: recorder,
            status: .confirmed
        )
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-allowed",
            nonce: "nonce-dailymart-orchestrated-allowed",
            timestamp: "2026-05-31T12:00:00Z"
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .paidComplete)
        XCTAssertTrue(result.didAnchorRequest)
        XCTAssertTrue(result.didExecutePayment)
        XCTAssertEqual(result.requestAnchor?.metadata.requestId, request.requestId)
        XCTAssertEqual(result.paymentResult?.status, .confirmed)
        XCTAssertEqual(result.paymentResult?.tokenSymbol, "OKRW")
        XCTAssertEqual(result.paymentResult?.requestHash, try MeshRequestAnchorCanonicalization.signedRequestHash(for: request))
        let events = await recorder.events()
        XCTAssertEqual(events, ["anchor", "execute"])
    }

    func testValidationDeniedRequestReturnsValidationStateWithoutAnchoringOrExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentExecutor = try RecordingPaymentExecutor(identity: anchorProvider.identity, recorder: recorder)
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-validation-denied",
            nonce: "nonce-dailymart-orchestrated-validation-denied",
            timestamp: "2026-05-31T12:00:00Z",
            signatureValue: Data(repeating: 7, count: 64).base64EncodedString()
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .validationDenied)
        XCTAssertEqual(result.denialReason, "invalid request signature")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testExpiredNonceIsRejectedBeforeAnchoringOrOKRWExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentExecutor = try RecordingPaymentExecutor(identity: anchorProvider.identity, recorder: recorder)
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-expired-nonce",
            nonce: "nonce-dailymart-orchestrated-expired",
            timestamp: "2026-05-31T11:54:59Z"
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .validationDenied)
        XCTAssertEqual(result.denialReason, "stale-timestamp")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        XCTAssertNil(result.guardResult)
        XCTAssertNil(result.requestAnchor)
        XCTAssertNil(result.paymentResult)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testMalformedNonceIsRejectedBeforeAnchoringOrOKRWExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentExecutor = try RecordingPaymentExecutor(identity: anchorProvider.identity, recorder: recorder)
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-malformed-nonce",
            nonce: "nonce/dailymart/orchestrated/malformed",
            timestamp: "2026-05-31T12:00:00Z"
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .validationDenied)
        XCTAssertEqual(result.denialReason, "invalid-nonce")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        XCTAssertNil(result.guardResult)
        XCTAssertNil(result.requestAnchor)
        XCTAssertNil(result.paymentResult)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testDuplicateNonceReplayIsRejectedBeforeAnchoringOrOKRWExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentExecutor = try RecordingPaymentExecutor(
            identity: anchorProvider.identity,
            recorder: recorder,
            status: .confirmed
        )
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-duplicate-nonce-original",
            nonce: "nonce-dailymart-orchestrated-duplicate-replay",
            timestamp: "2026-05-31T12:00:00Z"
        )
        let replay = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-duplicate-nonce-replay",
            nonce: "nonce-dailymart-orchestrated-duplicate-replay",
            timestamp: "2026-05-31T12:00:01Z"
        )

        let firstResult = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )
        let replayResult = try await orchestrator.execute(
            request: replay,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:05Z",
            authorizationDecidedAt: "2026-05-31T12:00:06Z",
            paymentRequestedAt: "2026-05-31T12:00:07Z",
            paymentSubmittedAt: "2026-05-31T12:00:08Z"
        )

        XCTAssertEqual(firstResult.presentationState, .paidComplete)
        XCTAssertTrue(firstResult.didAnchorRequest)
        XCTAssertTrue(firstResult.didExecutePayment)
        XCTAssertEqual(replayResult.presentationState, .validationDenied)
        XCTAssertEqual(replayResult.denialReason, "replay-detected")
        XCTAssertFalse(replayResult.didAnchorRequest)
        XCTAssertFalse(replayResult.didExecutePayment)
        XCTAssertNil(replayResult.guardResult)
        XCTAssertNil(replayResult.requestAnchor)
        XCTAssertNil(replayResult.paymentResult)
        let events = await recorder.events()
        XCTAssertEqual(events, ["anchor", "execute"])
    }

    func testPolicyDeniedRequestReturnsPolicyStateWithoutAnchoringOrExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentSpy = PaymentExecutionSpy()
        let paymentExecutor = try FailingPaymentExecutionSpy(
            identity: anchorProvider.identity,
            spy: paymentSpy
        )
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-policy-denied",
            nonce: "nonce-dailymart-orchestrated-policy-denied",
            timestamp: "2026-05-31T12:00:00Z",
            payloadOverrides: ["budget_krw": "101"]
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .policyDenied)
        XCTAssertEqual(result.denialReason, "policy-single-payment-max-exceeded")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        let executePaymentCallCount = await paymentSpy.executePaymentCallCount()
        XCTAssertEqual(executePaymentCallCount, 0)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testMissingDelegatedSpendingPolicyReturnsPolicyDeniedWithoutAnchoringOrExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentSpy = PaymentExecutionSpy()
        let paymentExecutor = try FailingPaymentExecutionSpy(
            identity: anchorProvider.identity,
            spy: paymentSpy
        )
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-missing-policy",
            nonce: "nonce-dailymart-orchestrated-missing-policy",
            timestamp: "2026-05-31T12:00:00Z",
            payloadOverrides: ["policyId": nil]
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .policyDenied)
        XCTAssertEqual(result.denialReason, "missing-policy")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        XCTAssertNil(result.guardResult)
        XCTAssertNil(result.requestAnchor)
        XCTAssertNil(result.paymentResult)
        let executePaymentCallCount = await paymentSpy.executePaymentCallCount()
        XCTAssertEqual(executePaymentCallCount, 0)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testMissingConsentGrantIdIsRejectedBeforeAnchoringOrOKRWExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentSpy = PaymentExecutionSpy()
        let paymentExecutor = try FailingPaymentExecutionSpy(
            identity: anchorProvider.identity,
            spy: paymentSpy
        )
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-missing-consent-grant",
            nonce: "nonce-dailymart-orchestrated-missing-consent-grant",
            timestamp: "2026-05-31T12:00:00Z",
            payloadOverrides: ["consentGrantId": nil]
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .policyDenied)
        XCTAssertEqual(result.denialReason, "consent-grant-denied")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        XCTAssertNil(result.guardResult)
        XCTAssertNil(result.requestAnchor)
        XCTAssertNil(result.paymentResult)
        let executePaymentCallCount = await paymentSpy.executePaymentCallCount()
        XCTAssertEqual(executePaymentCallCount, 0)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testWrongPolicyIdReturnsPolicyDeniedWithoutAnchoringOrPaymentExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentSpy = PaymentExecutionSpy()
        let paymentExecutor = try FailingPaymentExecutionSpy(
            identity: anchorProvider.identity,
            spy: paymentSpy
        )
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-wrong-policy-id",
            nonce: "nonce-dailymart-orchestrated-wrong-policy-id",
            timestamp: "2026-05-31T12:00:00Z",
            payloadOverrides: ["policyId": "policy-hermes-dailymart-okrw-wrong"]
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .policyDenied)
        XCTAssertEqual(result.denialReason, "policy-id-mismatch")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        XCTAssertNil(result.guardResult)
        XCTAssertNil(result.requestAnchor)
        XCTAssertNil(result.paymentResult)
        let executePaymentCallCount = await paymentSpy.executePaymentCallCount()
        XCTAssertEqual(executePaymentCallCount, 0)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testMismatchedPolicyHashReturnsPolicyDeniedWithoutAnchoringOrPaymentExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentSpy = PaymentExecutionSpy()
        let paymentExecutor = try FailingPaymentExecutionSpy(
            identity: anchorProvider.identity,
            spy: paymentSpy
        )
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-policy-hash-mismatch",
            nonce: "nonce-dailymart-orchestrated-policy-hash-mismatch",
            timestamp: "2026-05-31T12:00:00Z",
            payloadOverrides: ["policyHash": String(repeating: "a", count: 64)]
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .policyDenied)
        XCTAssertEqual(result.denialReason, "policy-hash-mismatch")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        XCTAssertNil(result.guardResult)
        XCTAssertNil(result.requestAnchor)
        XCTAssertNil(result.paymentResult)
        let executePaymentCallCount = await paymentSpy.executePaymentCallCount()
        XCTAssertEqual(executePaymentCallCount, 0)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testActivePolicyAndConsentGrantWindowsAllowPaymentExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentExecutor = try RecordingPaymentExecutor(
            identity: anchorProvider.identity,
            recorder: recorder,
            status: .confirmed
        )
        let walletPolicyGuard = try DailyMartPreExecutionWalletPolicyGuard(
            policy: delegatedSpendingPolicy(
                startsAt: "2026-05-31T11:59:00Z",
                expiresAt: "2026-05-31T12:05:00Z"
            ),
            scopeConsentGate: DailyMartDelegatedSpendingPolicy.scopeConsentGate(
                expiresAt: "2026-05-31T12:05:00Z"
            )
        )
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor,
            walletPolicyGuard: walletPolicyGuard
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-window-active",
            nonce: "nonce-dailymart-orchestrated-window-active",
            timestamp: "2026-05-31T12:00:00Z"
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .paidComplete)
        XCTAssertTrue(result.didAnchorRequest)
        XCTAssertTrue(result.didExecutePayment)
        XCTAssertEqual(result.guardResult?.policyEvaluation.status, .allowed)
        let events = await recorder.events()
        XCTAssertEqual(events, ["anchor", "execute"])
    }

    func testExpiredPolicyWindowDeniesBeforeAnchorOrPaymentExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentSpy = PaymentExecutionSpy()
        let paymentExecutor = try FailingPaymentExecutionSpy(
            identity: anchorProvider.identity,
            spy: paymentSpy
        )
        let walletPolicyGuard = try DailyMartPreExecutionWalletPolicyGuard(
            policy: delegatedSpendingPolicy(
                startsAt: "2026-05-31T11:00:00Z",
                expiresAt: "2026-05-31T11:59:59Z"
            ),
            scopeConsentGate: DailyMartDelegatedSpendingPolicy.scopeConsentGate(
                expiresAt: "2026-05-31T12:05:00Z"
            )
        )
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor,
            walletPolicyGuard: walletPolicyGuard
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-policy-window-expired",
            nonce: "nonce-dailymart-orchestrated-policy-window-expired",
            timestamp: "2026-05-31T12:00:00Z"
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .policyDenied)
        XCTAssertEqual(result.denialReason, "policy-expired")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        let executePaymentCallCount = await paymentSpy.executePaymentCallCount()
        XCTAssertEqual(executePaymentCallCount, 0)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testPolicyWindowExpiredAtPaymentRequestTimeDeniesBeforeAnchorOrPaymentExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentSpy = PaymentExecutionSpy()
        let paymentExecutor = try FailingPaymentExecutionSpy(
            identity: anchorProvider.identity,
            spy: paymentSpy
        )
        let walletPolicyGuard = try DailyMartPreExecutionWalletPolicyGuard(
            policy: delegatedSpendingPolicy(
                startsAt: "2026-05-31T11:59:00Z",
                expiresAt: "2026-05-31T12:00:02Z"
            ),
            scopeConsentGate: DailyMartDelegatedSpendingPolicy.scopeConsentGate(
                expiresAt: "2026-05-31T12:05:00Z"
            )
        )
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor,
            walletPolicyGuard: walletPolicyGuard
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-policy-window-expired-at-payment",
            nonce: "nonce-dailymart-orchestrated-policy-window-expired-at-payment",
            timestamp: "2026-05-31T12:00:00Z"
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .policyDenied)
        XCTAssertEqual(result.denialReason, "policy-expired")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        XCTAssertNil(result.guardResult)
        XCTAssertNil(result.requestAnchor)
        XCTAssertNil(result.paymentResult)
        let executePaymentCallCount = await paymentSpy.executePaymentCallCount()
        XCTAssertEqual(executePaymentCallCount, 0)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testFuturePolicyWindowDeniesTransferBeforeAnchorOrExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentSpy = PaymentExecutionSpy()
        let paymentExecutor = try FailingPaymentExecutionSpy(
            identity: anchorProvider.identity,
            spy: paymentSpy
        )
        let walletPolicyGuard = try DailyMartPreExecutionWalletPolicyGuard(
            policy: delegatedSpendingPolicy(
                startsAt: "2026-05-31T12:00:03Z",
                expiresAt: "2026-05-31T12:05:00Z"
            ),
            scopeConsentGate: DailyMartDelegatedSpendingPolicy.scopeConsentGate(
                expiresAt: "2026-05-31T12:05:00Z"
            )
        )
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor,
            walletPolicyGuard: walletPolicyGuard
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-policy-window-future",
            nonce: "nonce-dailymart-orchestrated-policy-window-future",
            timestamp: "2026-05-31T12:00:00Z"
        )

        let result = try await orchestrator.execute(
            request: request,
            executionKind: .transfer,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .policyDenied)
        XCTAssertEqual(result.denialReason, "policy-not-yet-active")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        let executePaymentCallCount = await paymentSpy.executePaymentCallCount()
        XCTAssertEqual(executePaymentCallCount, 0)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testExpiredConsentGrantWindowDeniesBeforeAnchorOrPaymentExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentExecutor = try RecordingPaymentExecutor(identity: anchorProvider.identity, recorder: recorder)
        let walletPolicyGuard = try DailyMartPreExecutionWalletPolicyGuard(
            policy: delegatedSpendingPolicy(
                startsAt: "2026-05-31T11:00:00Z",
                expiresAt: "2026-05-31T12:05:00Z"
            ),
            scopeConsentGate: DailyMartDelegatedSpendingPolicy.scopeConsentGate(
                expiresAt: "2026-05-31T11:59:59Z"
            )
        )
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor,
            walletPolicyGuard: walletPolicyGuard
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-consent-window-expired",
            nonce: "nonce-dailymart-orchestrated-consent-window-expired",
            timestamp: "2026-05-31T12:00:00Z"
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .policyDenied)
        XCTAssertEqual(result.denialReason, "consent-grant-expired")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testConsentGrantMismatchIsRejectedBeforeAnchorOrPaymentExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentExecutor = try RecordingPaymentExecutor(identity: anchorProvider.identity, recorder: recorder)
        let walletPolicyGuard = try DailyMartPreExecutionWalletPolicyGuard(
            policy: delegatedSpendingPolicy(
                consentGrantId: "grant-hermes-dailymart-other",
                startsAt: "2026-05-31T11:59:00Z",
                expiresAt: "2026-05-31T12:05:00Z"
            ),
            scopeConsentGate: DailyMartDelegatedSpendingPolicy.scopeConsentGate(
                expiresAt: "2026-05-31T12:05:00Z"
            )
        )
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor,
            walletPolicyGuard: walletPolicyGuard
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-consent-grant-mismatch",
            nonce: "nonce-dailymart-orchestrated-consent-grant-mismatch",
            timestamp: "2026-05-31T12:00:00Z"
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .policyDenied)
        XCTAssertEqual(result.denialReason, "policy-consent-grant-mismatch")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        XCTAssertNil(result.guardResult)
        XCTAssertNil(result.requestAnchor)
        XCTAssertNil(result.paymentResult)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testWalletSessionMismatchIsRejectedBeforePaymentExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentSpy = PaymentExecutionSpy()
        let paymentExecutor = try FailingPaymentExecutionSpy(
            identity: anchorProvider.identity,
            spy: paymentSpy
        )
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-wallet-session-mismatch",
            nonce: "nonce-dailymart-orchestrated-wallet-session-mismatch",
            timestamp: "2026-05-31T12:00:00Z",
            payloadOverrides: ["walletSessionId": "wallet-session-unbound"]
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .policyDenied)
        XCTAssertEqual(result.denialReason, "consent-grant-context")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        XCTAssertNil(result.guardResult)
        XCTAssertNil(result.requestAnchor)
        XCTAssertNil(result.paymentResult)
        let executePaymentCallCount = await paymentSpy.executePaymentCallCount()
        XCTAssertEqual(executePaymentCallCount, 0)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testRequestAnchorBindingMismatchIsRejectedBeforePaymentExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RequestAnchorMismatchProvider(recorder: recorder)
        let paymentSpy = PaymentExecutionSpy()
        let paymentExecutor = try FailingPaymentExecutionSpy(
            identity: anchorProvider.identity,
            spy: paymentSpy
        )
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-anchor-binding-mismatch",
            nonce: "nonce-dailymart-orchestrated-anchor-binding-mismatch",
            timestamp: "2026-05-31T12:00:00Z"
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .attemptedFailed)
        XCTAssertEqual(result.denialReason, "request anchor payload metadata mismatch")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        XCTAssertNotNil(result.guardResult)
        XCTAssertNil(result.requestAnchor)
        XCTAssertNil(result.paymentResult)
        let executePaymentCallCount = await paymentSpy.executePaymentCallCount()
        XCTAssertEqual(executePaymentCallCount, 0)
        let events = await recorder.events()
        XCTAssertEqual(events, ["anchor"])
    }

    func testConsentGrantSignerMismatchIsRejectedBeforeAnchorOrPaymentExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentSpy = PaymentExecutionSpy()
        let paymentExecutor = try FailingPaymentExecutionSpy(
            identity: anchorProvider.identity,
            spy: paymentSpy
        )
        let walletPolicyGuard = try DailyMartPreExecutionWalletPolicyGuard(
            policy: delegatedSpendingPolicy(
                startsAt: "2026-05-31T11:59:00Z",
                expiresAt: "2026-05-31T12:05:00Z"
            ),
            scopeConsentGate: try scopeConsentGate(
                signerKeyId: "other-hermes-agent-key",
                walletAddress: "maroo1dailyMartAgentWallet",
                expiresAt: "2026-05-31T12:05:00Z"
            )
        )
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor,
            walletPolicyGuard: walletPolicyGuard
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-grant-signer-mismatch",
            nonce: "nonce-dailymart-orchestrated-grant-signer-mismatch",
            timestamp: "2026-05-31T12:00:00Z"
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .policyDenied)
        XCTAssertEqual(result.denialReason, "consent grant signer binding mismatch")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        XCTAssertNil(result.guardResult)
        XCTAssertNil(result.requestAnchor)
        XCTAssertNil(result.paymentResult)
        let executePaymentCallCount = await paymentSpy.executePaymentCallCount()
        XCTAssertEqual(executePaymentCallCount, 0)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testConsentGrantWalletMismatchIsRejectedBeforeAnchorOrPaymentExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentSpy = PaymentExecutionSpy()
        let paymentExecutor = try FailingPaymentExecutionSpy(
            identity: anchorProvider.identity,
            spy: paymentSpy
        )
        let walletPolicyGuard = try DailyMartPreExecutionWalletPolicyGuard(
            policy: delegatedSpendingPolicy(
                startsAt: "2026-05-31T11:59:00Z",
                expiresAt: "2026-05-31T12:05:00Z"
            ),
            scopeConsentGate: try scopeConsentGate(
                signerKeyId: DailyMartDelegatedSpendingPolicy.consentGrantSignerKeyId,
                walletAddress: "maroo1differentAgentWallet",
                expiresAt: "2026-05-31T12:05:00Z"
            )
        )
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor,
            walletPolicyGuard: walletPolicyGuard
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-grant-wallet-mismatch",
            nonce: "nonce-dailymart-orchestrated-grant-wallet-mismatch",
            timestamp: "2026-05-31T12:00:00Z"
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .policyDenied)
        XCTAssertEqual(result.denialReason, "walletAddress")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        XCTAssertNil(result.guardResult)
        XCTAssertNil(result.requestAnchor)
        XCTAssertNil(result.paymentResult)
        let executePaymentCallCount = await paymentSpy.executePaymentCallCount()
        XCTAssertEqual(executePaymentCallCount, 0)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testOverbroadPolicyScopeIsRejectedBeforeAnchoringOrOKRWExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentSpy = PaymentExecutionSpy()
        let paymentExecutor = try FailingPaymentExecutionSpy(
            identity: anchorProvider.identity,
            spy: paymentSpy
        )
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-overbroad-policy-scope",
            nonce: "nonce-dailymart-orchestrated-overbroad-policy-scope",
            timestamp: "2026-05-31T12:00:00Z",
            payloadOverrides: [
                "paymentCapabilityScope": "\(DailyMartDelegatedSpendingPolicy.capabilityScope),grocery.issue_refund"
            ]
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .policyDenied)
        XCTAssertEqual(result.denialReason, "capability-scope-denied")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        XCTAssertNil(result.guardResult)
        XCTAssertNil(result.requestAnchor)
        XCTAssertNil(result.paymentResult)
        let executePaymentCallCount = await paymentSpy.executePaymentCallCount()
        XCTAssertEqual(executePaymentCallCount, 0)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testWalletPrincipalMismatchIsRejectedBeforeAnchorOrPaymentExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentExecutor = try RecordingPaymentExecutor(identity: anchorProvider.identity, recorder: recorder)
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor,
            walletIdentity: MeshAgentWalletIdentity(
                walletId: "dailymart-agent-wallet-demo",
                agentId: "principal-other-agent",
                walletAddress: "maroo1dailyMartAgentWallet",
                providerMetadata: MeshAgentWalletProviderMetadata(
                    chainProviderIdentity: anchorProvider.identity,
                    adapterId: "dailymart-agent-wallet-demo-adapter"
                ),
                signingBoundary: .providerSubmission
            )
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-principal-mismatch",
            nonce: "nonce-dailymart-orchestrated-principal-mismatch",
            timestamp: "2026-05-31T12:00:00Z"
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .policyDenied)
        XCTAssertEqual(result.denialReason, "principal-mismatch")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        XCTAssertNil(result.guardResult)
        XCTAssertNil(result.requestAnchor)
        XCTAssertNil(result.paymentResult)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testRemainingSessionBudgetDenialDoesNotInvokePaymentExecutionAdapter() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentExecutor = try RecordingPaymentExecutor(identity: anchorProvider.identity, recorder: recorder)
        let policy = try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash,
            consentGrantId: DailyMartDelegatedSpendingPolicy.consentGrantId,
            merchantScope: DailyMartDelegatedSpendingPolicy.merchantScope,
            capabilityScope: DailyMartDelegatedSpendingPolicy.capabilityScope,
            singlePaymentMax: Decimal(100),
            sessionTotalLimit: Decimal(100),
            remainingLimit: Decimal(50),
            expiresAt: "2026-12-31T23:59:59Z",
            asset: DailyMartDelegatedSpendingPolicy.asset,
            recipientAddress: DailyMartDelegatedSpendingPolicy.recipientAddress
        )
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor,
            walletPolicyGuard: DailyMartPreExecutionWalletPolicyGuard(policy: policy)
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-remaining-budget-denied",
            nonce: "nonce-dailymart-orchestrated-remaining-budget-denied",
            timestamp: "2026-05-31T12:00:00Z",
            payloadOverrides: ["budget_krw": "75"]
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .policyDenied)
        XCTAssertEqual(result.denialReason, "policy-remaining-limit-exceeded")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        XCTAssertNil(result.guardResult)
        XCTAssertNil(result.paymentResult)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testMerchantScopeMismatchIsDeniedBeforeAnchorOrPaymentExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentExecutor = try RecordingPaymentExecutor(identity: anchorProvider.identity, recorder: recorder)
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-merchant-scope-denied",
            nonce: "nonce-dailymart-orchestrated-merchant-scope-denied",
            timestamp: "2026-05-31T12:00:00Z",
            payloadOverrides: ["merchantScope": "merchant.other-grocery"]
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .policyDenied)
        XCTAssertEqual(result.denialReason, "merchant-scope-denied")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        XCTAssertNil(result.guardResult)
        XCTAssertNil(result.requestAnchor)
        XCTAssertNil(result.paymentResult)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testPaymentCapabilityOutsideConsentGrantScopeIsDeniedBeforePaymentExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentExecutor = try RecordingPaymentExecutor(identity: anchorProvider.identity, recorder: recorder)
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-payment-capability-denied",
            nonce: "nonce-dailymart-orchestrated-payment-capability-denied",
            timestamp: "2026-05-31T12:00:00Z",
            payloadOverrides: ["paymentCapability": "grocery.refund_order"]
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .policyDenied)
        XCTAssertEqual(result.denialReason, "capability-scope-denied")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        XCTAssertNil(result.guardResult)
        XCTAssertNil(result.requestAnchor)
        XCTAssertNil(result.paymentResult)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testCombinedMerchantAndCapabilityGateDeniesBeforeAnchorOrPaymentExecution() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentSpy = PaymentExecutionSpy()
        let paymentExecutor = try FailingPaymentExecutionSpy(
            identity: anchorProvider.identity,
            spy: paymentSpy
        )
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-combined-auth-denied",
            nonce: "nonce-dailymart-orchestrated-combined-auth-denied",
            timestamp: "2026-05-31T12:00:00Z",
            payloadOverrides: [
                "merchantScope": "merchant.other-grocery",
                "paymentCapability": "grocery.refund_order"
            ]
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )

        XCTAssertEqual(result.presentationState, .policyDenied)
        XCTAssertEqual(result.denialReason, "merchant-scope-denied")
        XCTAssertFalse(result.didAnchorRequest)
        XCTAssertFalse(result.didExecutePayment)
        let executePaymentCallCount = await paymentSpy.executePaymentCallCount()
        XCTAssertEqual(executePaymentCallCount, 0)
        let events = await recorder.events()
        XCTAssertEqual(events, [])
    }

    func testOrchestratorMapsPendingAndFailedExecutionsToPresentationStates() async throws {
        for scenario in [
            (status: MeshPaymentExecutionStatus.pending, expected: DailyMartGuardOrchestrationPresentationState.submittedNotFinal),
            (status: MeshPaymentExecutionStatus.failed, expected: DailyMartGuardOrchestrationPresentationState.attemptedFailed)
        ] {
            let recorder = InvocationRecorder()
            let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
            let paymentExecutor = try RecordingPaymentExecutor(
                identity: anchorProvider.identity,
                recorder: recorder,
                status: scenario.status
            )
            let orchestrator = try makeOrchestrator(
                anchorProvider: anchorProvider,
                paymentExecutor: paymentExecutor
            )
            let request = try signedDailyMartRequest(
                requestId: "ios-grocery-orchestrated-\(scenario.status.rawValue)",
                nonce: "nonce-dailymart-orchestrated-\(scenario.status.rawValue)",
                timestamp: "2026-05-31T12:00:00Z"
            )

            let result = try await orchestrator.execute(
                request: request,
                now: referenceDate,
                anchorSubmittedAt: "2026-05-31T12:00:01Z",
                authorizationDecidedAt: "2026-05-31T12:00:02Z",
                paymentRequestedAt: "2026-05-31T12:00:03Z",
                paymentSubmittedAt: "2026-05-31T12:00:04Z"
            )

            XCTAssertEqual(result.presentationState, scenario.expected)
            XCTAssertTrue(result.didAnchorRequest)
            XCTAssertTrue(result.didExecutePayment)
            XCTAssertEqual(result.paymentResult?.status, scenario.status)
            let events = await recorder.events()
            XCTAssertEqual(events, ["anchor", "execute"])
        }
    }

    func testPendingVerifiedExecutionAttemptMapsToPendingDailyMartOwnedReceipt() async throws {
        let recorder = InvocationRecorder()
        let anchorProvider = try RecordingAnchorProvider(recorder: recorder)
        let paymentExecutor = try RecordingPaymentExecutor(
            identity: anchorProvider.identity,
            recorder: recorder,
            status: .pending
        )
        let orchestrator = try makeOrchestrator(
            anchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-orchestrated-pending-receipt",
            nonce: "nonce-dailymart-orchestrated-pending-receipt",
            timestamp: "2026-05-31T12:00:00Z"
        )

        let result = try await orchestrator.execute(
            request: request,
            now: referenceDate,
            anchorSubmittedAt: "2026-05-31T12:00:01Z",
            authorizationDecidedAt: "2026-05-31T12:00:02Z",
            paymentRequestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z"
        )
        let receipt = try DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: "dailymart-receipt-key",
                privateKey: receiptSigningKey
            )
        ).makeVerifiedWalletExecutionReceipt(
            receiptId: "DM-2026-0531-pending-execution-receipt",
            request: request,
            orchestrationResult: result,
            walletAddress: "maroo1dailyMartAgentWallet",
            baseResult: [
                "order_id": "DM-2026-0531-pending-execution-receipt",
                "total_krw": "100",
                "payment_asset": DailyMartDelegatedSpendingPolicy.asset,
                "policy_verification": MeshDelegatedSpendingPolicyVerificationStatus.approved.rawValue
            ],
            nonce: "DM-2026-0531-pending-execution-receipt-nonce",
            timestamp: "2026-05-31T12:00:05Z"
        )
        let ownershipProof = try MeshReceiptChainProofSerializer.targetOwnedProof(
            in: receipt,
            expectedTargetAppId: DailyMartTargetReceiptFactory.targetAppId,
            expectedTargetBundleId: DailyMartTargetReceiptFactory.targetBundleId,
            expectedRequest: request
        )

        XCTAssertEqual(result.presentationState, .submittedNotFinal)
        XCTAssertEqual(receipt.status, "pending")
        XCTAssertEqual(receipt.result["receiptOwner"], "app.dailymart#ai.meshkit.sample.dailymart")
        XCTAssertEqual(receipt.result["targetReceiptOwner"], "app.dailymart#ai.meshkit.sample.dailymart")
        XCTAssertEqual(receipt.result["chainProofType"], "request_anchor")
        XCTAssertEqual(receipt.result["chainStatus"], "pending")
        XCTAssertEqual(receipt.result["presentationState"], "submitted_not_final")
        XCTAssertEqual(receipt.result["submittedAt"], "2026-05-31T12:00:04Z")
        XCTAssertNil(receipt.result["confirmedAt"])
        XCTAssertNil(receipt.result["txHash"])
        XCTAssertNil(receipt.result["explorerUrl"])
        XCTAssertEqual(receipt.result["requestHash"], try MeshRequestAnchorCanonicalization.signedRequestHash(for: request).value)
        XCTAssertEqual(receipt.result["requestNonce"], request.nonce)
        XCTAssertEqual(receipt.result["anchoringReference"], "anchor-\(request.requestId)")
        XCTAssertEqual(
            receipt.result["executionAttemptId"],
            "meshkit-execution-attempt/v1:pay-\(request.requestId):auth-exec-\(request.requestId):exec-\(request.requestId)"
        )
        XCTAssertEqual(ownershipProof.proof.status, .pending)
        XCTAssertEqual(ownershipProof.proof.presentationState, .submittedNotFinal)
        XCTAssertNil(ownershipProof.transactionReference)
        let events = await recorder.events()
        XCTAssertEqual(events, ["anchor", "execute"])
    }

    private func makeOrchestrator(
        anchorProvider: any MeshRequestAnchorProvider,
        paymentExecutor: any MeshPaymentExecutor,
        walletPolicyGuard: DailyMartPreExecutionWalletPolicyGuard = try! DailyMartPreExecutionWalletPolicyGuard(),
        walletIdentity: MeshAgentWalletIdentity? = nil
    ) throws -> DailyMartGuardOrchestrator {
        try DailyMartGuardOrchestrator(
            signedRequestGuard: DailyMartPreExecutionMCPGuard(
                expectedHermesAgentSigner: MeshSenderTrust(
                    callerAppId: "app.hermes-chat",
                    callerBundleId: "ai.meshkit.sample.hermeschat",
                    teamId: "DEVTEAMID",
                    requestSigningAlgorithm: "Ed25519",
                    requestSigningKeyId: DailyMartDelegatedSpendingPolicy.consentGrantSignerKeyId,
                    publicKey: signingKey.publicKey.rawRepresentation.base64EncodedString()
                ),
                freshnessStore: DailyMartRequestNonceFreshnessStore(
                    expirationValidator: DailyMartRequestNonceExpirationValidator(maxAgeSeconds: 300)
                )
            ),
            walletPolicyGuard: walletPolicyGuard,
            requestAnchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor,
            walletIdentity: walletIdentity
        )
    }

    private func signedDailyMartRequest(
        requestId: String,
        nonce: String,
        timestamp: String,
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
                publicKeyId: DailyMartDelegatedSpendingPolicy.consentGrantSignerKeyId
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: DailyMartDelegatedSpendingPolicy.capabilityScope,
                version: "1.0"
            ),
            payload: payload,
            nonce: nonce,
            timestamp: timestamp,
            signature: MeshSignature(algorithm: "Ed25519", keyId: DailyMartDelegatedSpendingPolicy.consentGrantSignerKeyId, value: "")
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
                keyId: DailyMartDelegatedSpendingPolicy.consentGrantSignerKeyId,
                value: signatureValue ?? signature
            )
        )
    }

    private func delegatedSpendingPolicy(
        consentGrantId: String = DailyMartDelegatedSpendingPolicy.consentGrantId,
        startsAt: String?,
        expiresAt: String
    ) throws -> MeshAgentWalletDelegatedSpendingPolicy {
        try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash,
            consentGrantId: consentGrantId,
            merchantScope: DailyMartDelegatedSpendingPolicy.merchantScope,
            capabilityScope: DailyMartDelegatedSpendingPolicy.capabilityScope,
            singlePaymentMax: Decimal(100),
            sessionTotalLimit: Decimal(100),
            remainingLimit: Decimal(100),
            startsAt: startsAt,
            expiresAt: expiresAt,
            asset: DailyMartDelegatedSpendingPolicy.asset,
            recipientAddress: DailyMartDelegatedSpendingPolicy.recipientAddress
        )
    }

    private func scopeConsentGate(
        signerKeyId: String,
        walletAddress: String,
        expiresAt: String
    ) throws -> DailyMartScopeConsentGate {
        let grant = try DailyMartConsentGrant(
            consentGrantId: DailyMartDelegatedSpendingPolicy.consentGrantId,
            callerAppId: "app.hermes-chat",
            callerBundleId: "ai.meshkit.sample.hermeschat",
            walletSessionId: DailyMartDelegatedSpendingPolicy.walletSessionId,
            principalId: DailyMartDelegatedSpendingPolicy.principalId,
            targetBundleId: "ai.meshkit.sample.dailymart",
            capabilityId: DailyMartDelegatedSpendingPolicy.capabilityScope,
            merchantScope: DailyMartDelegatedSpendingPolicy.merchantScope,
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            signerKeyId: signerKeyId,
            walletAddress: walletAddress,
            expiresAt: expiresAt
        )
        return DailyMartScopeConsentGate(
            merchantScopeValidator: try DailyMartMerchantScopeValidator(
                authorizedMerchantScope: DailyMartDelegatedSpendingPolicy.merchantScope
            ),
            capabilityScopeValidator: try DailyMartCapabilityScopeValidator(
                consentGrantId: DailyMartDelegatedSpendingPolicy.consentGrantId,
                consentedCapabilities: [DailyMartDelegatedSpendingPolicy.capabilityScope]
            ),
            consentGrantVerifier: try DailyMartConsentGrantVerifier(grants: [grant])
        )
    }
}

private actor InvocationRecorder {
    private var recordedEvents: [String] = []

    func record(_ event: String) {
        recordedEvents.append(event)
    }

    func events() -> [String] {
        recordedEvents
    }
}

private actor PaymentExecutionSpy {
    private var executePaymentCalls = 0

    func recordExecutePaymentCall() {
        executePaymentCalls += 1
    }

    func executePaymentCallCount() -> Int {
        executePaymentCalls
    }
}

private struct RecordingAnchorProvider: MeshRequestAnchorProvider {
    let identity: MeshChainProviderIdentity
    let capabilities: [MeshChainProviderCapability] = [.anchorSignedRequest, .lookupRequestAnchorStatus]
    let recorder: InvocationRecorder

    init(recorder: InvocationRecorder) throws {
        self.identity = try MeshChainProviderIdentity(
            providerName: "maroo",
            networkIdentity: "maroo-testnet",
            chainId: "maroo-testnet-1",
            rpcEndpoint: XCTUnwrap(URL(string: "https://rpc-testnet.maroo.io")),
            explorerBaseURL: XCTUnwrap(URL(string: "https://explorer-testnet.maroo.io"))
        )
        self.recorder = recorder
    }

    func anchorSignedRequest(
        metadata: MeshSignedRequestAnchorMetadata,
        submittedAt: String
    ) async throws -> MeshRequestAnchor {
        await recorder.record("anchor")
        return try MeshRequestAnchor(
            metadata: metadata,
            identifier: MeshRequestAnchorIdentifier(
                identity: identity,
                anchorId: "anchor-\(metadata.requestId)",
                transactionHash: "0xanchor\(metadata.requestId.filter { $0.isLetter || $0.isNumber })"
            ),
            status: .confirmed,
            submittedAt: submittedAt,
            observedAt: submittedAt
        )
    }

    func requestAnchorStatus(
        identifier: MeshRequestAnchorIdentifier,
        checkedAt: String
    ) async throws -> MeshRequestAnchor {
        throw MeshKitValidationError.requestAnchorReferenceNotFound(identifier.anchorId)
    }
}

private struct RequestAnchorMismatchProvider: MeshRequestAnchorProvider {
    let identity: MeshChainProviderIdentity
    let capabilities: [MeshChainProviderCapability] = [.anchorSignedRequest]
    let recorder: InvocationRecorder

    init(recorder: InvocationRecorder) throws {
        self.identity = try MeshChainProviderIdentity(
            providerName: "maroo",
            networkIdentity: "maroo-testnet",
            chainId: "maroo-testnet-1",
            rpcEndpoint: XCTUnwrap(URL(string: "https://rpc-testnet.maroo.io")),
            explorerBaseURL: XCTUnwrap(URL(string: "https://explorer-testnet.maroo.io"))
        )
        self.recorder = recorder
    }

    func anchorSignedRequest(
        metadata: MeshSignedRequestAnchorMetadata,
        submittedAt: String
    ) async throws -> MeshRequestAnchor {
        await recorder.record("anchor")
        let mismatchedMetadata = try MeshSignedRequestAnchorMetadata(
            requestId: "\(metadata.requestId)-other",
            nonce: metadata.nonce,
            timestamp: metadata.timestamp,
            callerAppId: metadata.callerAppId,
            callerBundleId: metadata.callerBundleId,
            targetBundleId: metadata.targetBundleId,
            capabilityId: metadata.capabilityId,
            payloadHash: metadata.payloadHash,
            signature: metadata.signature,
            signedRequestHash: metadata.signedRequestHash
        )
        return try MeshRequestAnchor(
            metadata: mismatchedMetadata,
            identifier: MeshRequestAnchorIdentifier(
                identity: identity,
                anchorId: "anchor-\(metadata.requestId)-other",
                transactionHash: "0xanchor\(metadata.requestId.filter { $0.isLetter || $0.isNumber })other"
            ),
            status: .confirmed,
            submittedAt: submittedAt,
            observedAt: submittedAt
        )
    }

    func requestAnchorStatus(
        identifier: MeshRequestAnchorIdentifier,
        checkedAt: String
    ) async throws -> MeshRequestAnchor {
        throw MeshKitValidationError.requestAnchorReferenceNotFound(identifier.anchorId)
    }
}

private struct FailingPaymentExecutionSpy: MeshPaymentExecutor {
    let identity: MeshChainProviderIdentity
    let capabilities: [MeshPaymentExecutorCapability] = [.executePayment]
    let spy: PaymentExecutionSpy

    init(
        identity: MeshChainProviderIdentity,
        spy: PaymentExecutionSpy
    ) throws {
        self.identity = identity
        self.spy = spy
    }

    func loadPaymentExecutorConfiguration() throws -> MeshPaymentExecutorConfiguration {
        try MeshPaymentExecutorConfiguration(identity: identity, capabilities: capabilities)
    }

    func executePayment(
        _ request: MeshPaymentExecutionRequest,
        submittedAt: String
    ) async throws -> MeshPaymentExecutionResult {
        await spy.recordExecutePaymentCall()
        throw MeshKitValidationError.invalidPaymentExecution("over-limit request reached payment executor")
    }

    func paymentExecutionStatus(
        paymentId: String,
        checkedAt: String
    ) async throws -> MeshPaymentExecutionResult {
        throw MeshKitValidationError.invalidPaymentExecution("paymentId")
    }
}

private struct RecordingPaymentExecutor: MeshPaymentExecutor {
    let identity: MeshChainProviderIdentity
    let capabilities: [MeshPaymentExecutorCapability] = [.executePayment, .executeTransfer, .lookupExecutionStatus]
    let recorder: InvocationRecorder
    let status: MeshPaymentExecutionStatus

    init(
        identity: MeshChainProviderIdentity,
        recorder: InvocationRecorder,
        status: MeshPaymentExecutionStatus = .confirmed
    ) throws {
        self.identity = identity
        self.recorder = recorder
        self.status = status
    }

    func loadPaymentExecutorConfiguration() throws -> MeshPaymentExecutorConfiguration {
        try MeshPaymentExecutorConfiguration(identity: identity, capabilities: capabilities)
    }

    func executePayment(
        _ request: MeshPaymentExecutionRequest,
        submittedAt: String
    ) async throws -> MeshPaymentExecutionResult {
        await recorder.record("execute")
        return try MeshPaymentExecutionResult(
            request: request,
            identity: identity,
            status: status,
            transactionHash: transactionHash(for: request),
            observedAt: submittedAt,
            message: status == .failed ? "maroo testnet OKRW execution failed" : nil
        )
    }

    func paymentExecutionStatus(
        paymentId: String,
        checkedAt: String
    ) async throws -> MeshPaymentExecutionResult {
        throw MeshKitValidationError.invalidPaymentExecution("paymentId")
    }

    private func transactionHash(for request: MeshPaymentExecutionRequest) -> String? {
        switch status {
        case .confirmed:
            return "0xpay\(request.paymentId.filter { $0.isLetter || $0.isNumber })"
        case .pending:
            return "0xpending\(request.paymentId.filter { $0.isLetter || $0.isNumber })"
        case .failed, .policyDenied:
            return nil
        }
    }
}
