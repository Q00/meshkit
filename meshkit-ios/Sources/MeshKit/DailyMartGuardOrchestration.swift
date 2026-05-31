import Foundation

public enum DailyMartGuardOrchestrationPresentationState: String, Codable, Equatable, Sendable {
    case paidComplete = "paid_complete"
    case submittedNotFinal = "submitted_not_final"
    case attemptedFailed = "attempted_failed"
    case policyDenied = "policy_denied"
    case validationDenied = "validation_denied"
}

public struct DailyMartGuardOrchestrationResult: Equatable, Sendable {
    public let requestId: String
    public let nonce: String
    public let presentationState: DailyMartGuardOrchestrationPresentationState
    public let denialReason: String?
    public let guardResult: DailyMartPreExecutionWalletPolicyGuardResult?
    public let requestAnchor: MeshRequestAnchor?
    public let paymentResult: MeshPaymentExecutionResult?

    public var didAnchorRequest: Bool { requestAnchor != nil }
    public var didExecutePayment: Bool { paymentResult != nil }

    public init(
        requestId: String,
        nonce: String,
        presentationState: DailyMartGuardOrchestrationPresentationState,
        denialReason: String? = nil,
        guardResult: DailyMartPreExecutionWalletPolicyGuardResult? = nil,
        requestAnchor: MeshRequestAnchor? = nil,
        paymentResult: MeshPaymentExecutionResult? = nil
    ) throws {
        self.requestId = try MeshAgentWalletProviderMetadata.stableValue("requestId", requestId)
        self.nonce = try MeshAgentWalletProviderMetadata.stableValue("nonce", nonce)
        self.presentationState = presentationState
        self.denialReason = try denialReason.map { try MeshAgentWalletProviderMetadata.stableValue("denialReason", $0) }
        self.guardResult = guardResult
        self.requestAnchor = requestAnchor
        self.paymentResult = paymentResult
        try validate()
    }

    public func validate() throws {
        try MeshAgentWalletProviderMetadata.validateIdentifier("requestId", requestId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("nonce", nonce)
        if let denialReason {
            try MeshAgentWalletProviderMetadata.validateIdentifier("denialReason", denialReason)
        }
        try guardResult?.validate()
        try requestAnchor?.validate()
        try paymentResult?.validate()

        switch presentationState {
        case .validationDenied, .policyDenied:
            guard denialReason != nil, requestAnchor == nil, paymentResult == nil else {
                throw MeshKitValidationError.invalidPaymentExecution("guardDenied")
            }
        case .paidComplete:
            guard requestAnchor != nil, paymentResult?.status == .confirmed else {
                throw MeshKitValidationError.invalidPaymentExecution("paidComplete")
            }
        case .submittedNotFinal:
            guard requestAnchor != nil else {
                throw MeshKitValidationError.invalidPaymentExecution("submittedNotFinal")
            }
        case .attemptedFailed:
            guard denialReason != nil || requestAnchor != nil || paymentResult?.status == .failed else {
                throw MeshKitValidationError.invalidPaymentExecution("attemptedFailed")
            }
        }
    }
}

public struct DailyMartGuardOrchestrator: Sendable {
    public let signedRequestGuard: DailyMartPreExecutionMCPGuard
    public let walletPolicyGuard: DailyMartPreExecutionWalletPolicyGuard
    public let requestAnchorSubmissionModule: MeshRequestAnchorSubmissionModule
    public let paymentExecutor: any MeshPaymentExecutor
    public let walletIdentity: MeshAgentWalletIdentity

    public init(
        signedRequestGuard: DailyMartPreExecutionMCPGuard,
        walletPolicyGuard: DailyMartPreExecutionWalletPolicyGuard,
        requestAnchorProvider: any MeshRequestAnchorProvider,
        paymentExecutor: any MeshPaymentExecutor,
        walletIdentity: MeshAgentWalletIdentity? = nil
    ) throws {
        self.signedRequestGuard = signedRequestGuard
        self.walletPolicyGuard = walletPolicyGuard
        self.requestAnchorSubmissionModule = MeshRequestAnchorSubmissionModule(provider: requestAnchorProvider)
        self.paymentExecutor = paymentExecutor
        self.walletIdentity = try walletIdentity ?? Self.defaultWalletIdentity(
            providerIdentity: requestAnchorProvider.identity
        )
    }

    public func execute(
        request: MeshRequest,
        executionKind: MeshAgentWalletExecutionKind = .payment,
        now: Date = Date(),
        anchorSubmittedAt: String,
        authorizationDecidedAt: String,
        paymentRequestedAt: String,
        paymentSubmittedAt: String
    ) async throws -> DailyMartGuardOrchestrationResult {
        do {
            _ = try signedRequestGuard.acceptForPreExecution(request, now: now)
        } catch {
            return try Self.deniedResult(
                request: request,
                presentationState: Self.preExecutionDenialPresentationState(for: error),
                reason: Self.denialReason(for: error)
            )
        }

        do {
            try Self.validatePrincipalBinding(request: request, walletIdentity: walletIdentity)
            try Self.validateConsentGrantBinding(
                request: request,
                walletIdentity: walletIdentity,
                consentGrantVerifier: walletPolicyGuard.scopeConsentGate.consentGrantVerifier,
                verifiedAt: authorizationDecidedAt
            )
        } catch {
            return try Self.deniedResult(
                request: request,
                presentationState: .policyDenied,
                reason: Self.denialReason(for: error)
            )
        }

        let guardResult: DailyMartPreExecutionWalletPolicyGuardResult
        do {
            guardResult = try walletPolicyGuard.evaluate(
                request,
                executionKind: executionKind,
                executionId: "exec-\(request.requestId)",
                verifiedAt: authorizationDecidedAt
            )
        } catch {
            return try Self.deniedResult(
                request: request,
                presentationState: .policyDenied,
                reason: Self.denialReason(for: error)
            )
        }

        do {
            let paymentWindowEvaluation = try walletPolicyGuard.policy.evaluateExecutionRequest(
                guardResult.executionRequest,
                requestedAt: paymentRequestedAt
            )
            guard paymentWindowEvaluation.status == .allowed else {
                return try Self.deniedResult(
                    request: request,
                    presentationState: .policyDenied,
                    reason: paymentWindowEvaluation.reason ?? "policy-evaluation-denied"
                )
            }
        } catch {
            return try Self.deniedResult(
                request: request,
                presentationState: .policyDenied,
                reason: Self.denialReason(for: error)
            )
        }

        let authorizationDecision = try MeshAgentWalletAuthorizationDecision(
            authorizationId: "auth-\(guardResult.executionRequest.executionId)",
            walletIdentity: walletIdentity,
            executionRequest: guardResult.executionRequest,
            status: .approved,
            approvedAmount: guardResult.executionRequest.amount,
            decidedAt: authorizationDecidedAt
        )

        let submission = try MeshRequestAnchorSubmission(
            request: request,
            policy: walletPolicyGuard.policy,
            providerIdentity: requestAnchorSubmissionModule.provider.identity,
            submittedAt: anchorSubmittedAt
        )
        let anchor: MeshRequestAnchor
        do {
            anchor = try await requestAnchorSubmissionModule.submit(
                submission,
                boundTo: request,
                policy: walletPolicyGuard.policy
            )
        } catch {
            return try DailyMartGuardOrchestrationResult(
                requestId: request.requestId,
                nonce: request.nonce,
                presentationState: .attemptedFailed,
                denialReason: Self.denialReason(for: error),
                guardResult: guardResult
            )
        }

        let paymentRequest = try MeshPaymentExecutionRequest(
            paymentId: "pay-\(request.requestId)",
            authorizationDecision: authorizationDecision,
            requestAnchor: anchor,
            requestedAt: paymentRequestedAt
        )
        do {
            let paymentResult = try await paymentExecutor.executePayment(
                paymentRequest,
                originatingRequest: request,
                submittedAt: paymentSubmittedAt
            )
            return try DailyMartGuardOrchestrationResult(
                requestId: request.requestId,
                nonce: request.nonce,
                presentationState: Self.presentationState(for: paymentResult.status),
                guardResult: guardResult,
                requestAnchor: anchor,
                paymentResult: paymentResult
            )
        } catch {
            return try DailyMartGuardOrchestrationResult(
                requestId: request.requestId,
                nonce: request.nonce,
                presentationState: .attemptedFailed,
                denialReason: Self.denialReason(for: error),
                guardResult: guardResult,
                requestAnchor: anchor
            )
        }
    }

    private static func defaultWalletIdentity(
        providerIdentity: MeshChainProviderIdentity
    ) throws -> MeshAgentWalletIdentity {
        try MeshAgentWalletIdentity(
            walletId: "dailymart-agent-wallet-demo",
            agentId: DailyMartDelegatedSpendingPolicy.principalId,
            walletAddress: "maroo1dailyMartAgentWallet",
            providerMetadata: MeshAgentWalletProviderMetadata(
                chainProviderIdentity: providerIdentity,
                adapterId: "dailymart-agent-wallet-demo-adapter"
            ),
            signingBoundary: .providerSubmission
        )
    }

    private static func validatePrincipalBinding(
        request: MeshRequest,
        walletIdentity: MeshAgentWalletIdentity
    ) throws {
        guard let requestPrincipalId = request.payload["principalId"] else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("principal-mismatch")
        }
        let principalId = try MeshAgentWalletProviderMetadata.stableValue(
            "principalId",
            requestPrincipalId
        )
        guard walletIdentity.agentId == principalId else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("principal-mismatch")
        }
    }

    private static func validateConsentGrantBinding(
        request: MeshRequest,
        walletIdentity: MeshAgentWalletIdentity,
        consentGrantVerifier: DailyMartConsentGrantVerifier,
        verifiedAt: String
    ) throws {
        _ = try consentGrantVerifier.verifyBoundRequest(
            request,
            walletAddress: walletIdentity.walletAddress,
            requestAnchorMetadata: MeshSignedRequestAnchorMetadata(request: request),
            verifiedAt: verifiedAt
        )
    }

    private static func deniedResult(
        request: MeshRequest,
        presentationState: DailyMartGuardOrchestrationPresentationState,
        reason: String
    ) throws -> DailyMartGuardOrchestrationResult {
        try DailyMartGuardOrchestrationResult(
            requestId: request.requestId,
            nonce: request.nonce,
            presentationState: presentationState,
            denialReason: reason
        )
    }

    private static func presentationState(
        for status: MeshPaymentExecutionStatus
    ) -> DailyMartGuardOrchestrationPresentationState {
        switch status {
        case .confirmed:
            return .paidComplete
        case .pending:
            return .submittedNotFinal
        case .failed:
            return .attemptedFailed
        case .policyDenied:
            return .policyDenied
        }
    }

    private static func preExecutionDenialPresentationState(
        for error: Error
    ) -> DailyMartGuardOrchestrationPresentationState {
        guard case MeshKitValidationError.consentRequired(let reason) = error else {
            return .validationDenied
        }
        switch reason {
        case "merchant-scope-denied",
             "capability-scope-denied",
             "consent-grant-denied",
             "consent-grant-unknown",
             "consent-grant-expired",
             "consent-grant-not-yet-valid",
             "consent-grant-revoked",
             "consent-grant-context",
             "policy-id-mismatch",
             "policy-hash-mismatch",
             "missing-policy":
            return .policyDenied
        default:
            return .validationDenied
        }
    }

    private static func denialReason(for error: Error) -> String {
        switch error {
        case MeshKitValidationError.payloadHashMismatch:
            return "payload-hash-mismatch"
        case MeshKitValidationError.signatureRequired:
            return "signature-required"
        case MeshKitValidationError.staleTimestamp:
            return "stale-timestamp"
        case MeshKitValidationError.trustedCallerMismatch:
            return "trusted-caller-mismatch"
        case MeshKitValidationError.callerBundleClaimMismatch:
            return "caller-bundle-claim-mismatch"
        case MeshKitValidationError.unsupportedCapability:
            return "unsupported-capability"
        case MeshKitValidationError.consentRequired(let reason):
            return reason
        case MeshKitValidationError.replayDetected:
            return "replay-detected"
        case MeshKitValidationError.signatureMismatch(let reason):
            return reason
        case MeshKitValidationError.invalidSecurityField(let field):
            return field == "nonce" ? "invalid-nonce" : "invalid-\(field)"
        case MeshKitValidationError.invalidAgentWalletIdentity(let reason),
             MeshKitValidationError.invalidPaymentExecution(let reason),
             MeshKitValidationError.invalidChainProviderIdentity(let reason):
            switch reason {
            case "consentGrantId",
                 "consentGrantId.unknown",
                 "consentGrantId.expired",
                 "consentGrantId.notYetValid",
                 "consentGrantId.context",
                 "walletSessionId":
                return DailyMartScopeConsentGate.denialReasonCode(for: reason)
            default:
                break
            }
            return reason
        default:
            return "guard-orchestration-failed"
        }
    }
}
