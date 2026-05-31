import XCTest
@testable import MeshKit

final class MeshAgentWalletSignedArtifactSubmissionTests: XCTestCase {
    func testAgentWalletPaymentSubmissionAcceptsSignedRequestArtifactAndUsesConfiguredExecutionPath() async throws {
        let log = SignedArtifactSubmissionLog()
        let chainIdentity = try MeshMarooTestnetChainProvider().identity
        let walletIdentity = try agentWalletIdentity(chainIdentity: chainIdentity)
        let policy = try delegatedSpendingPolicy()
        let signedRequest = dailyMartSignedRequest()
        let artifact = try MeshAgentWalletSignedRequestArtifact(
            walletIdentity: walletIdentity,
            signedRequest: signedRequest,
            signedAt: "2026-05-31T13:00:00Z"
        )
        let wallet = SignedArtifactAgentWallet(identity: walletIdentity, policy: policy, log: log)
        let anchorProvider = SignedArtifactAnchorProvider(identity: chainIdentity, log: log)
        let paymentExecutor = SignedArtifactPaymentExecutor(
            identity: chainIdentity,
            capabilities: [.executePayment],
            log: log
        )
        let submissionPath = MeshAgentWalletPaymentSubmissionPath(
            wallet: wallet,
            requestAnchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )

        let submission = try await submissionPath.submitPayment(
            artifact: artifact,
            policy: policy,
            executionId: "exec-signed-artifact-payment",
            amount: Decimal(42),
            currencyCode: "krw",
            tokenSymbol: "okrw",
            recipientAddress: "maroo1DailyMartMerchant",
            paymentId: "pay-signed-artifact-payment",
            anchorSubmittedAt: "2026-05-31T13:00:01Z",
            anchorSignedAt: "2026-05-31T13:00:02Z",
            authorizationDecidedAt: "2026-05-31T13:00:03Z",
            paymentRequestedAt: "2026-05-31T13:00:04Z",
            paymentSubmittedAt: "2026-05-31T13:00:05Z"
        )

        XCTAssertEqual(submission.paymentResult.kind, .payment)
        XCTAssertEqual(submission.paymentResult.status, .confirmed)
        XCTAssertEqual(submission.anchorRecord.requestNonce, artifact.signedRequest.nonce)
        XCTAssertEqual(submission.anchorRecord.requestHash, artifact.anchorMetadata.signedRequestHash)
        XCTAssertEqual(submission.paymentRequest.requestHash, artifact.anchorMetadata.signedRequestHash)
        XCTAssertEqual(submission.paymentRequest.requestAnchor, submission.anchorRecord.anchor)
        XCTAssertEqual(log.events(), [
            "wallet.authorizeExecution:payment",
            "wallet.signRequestAnchorPayload",
            "anchor.submitPayload",
            "executor.executePayment:payment"
        ])
    }

    func testAgentWalletPaymentSubmissionRejectsLocalSignatureSignedArtifactBeforeExecutionBoundary() async throws {
        let log = SignedArtifactSubmissionLog()
        let chainIdentity = try MeshMarooTestnetChainProvider().identity
        let walletIdentity = try agentWalletIdentity(
            chainIdentity: chainIdentity,
            signingBoundary: .localSignature
        )
        let policy = try delegatedSpendingPolicy()
        let signedRequest = dailyMartSignedRequest()
        let artifact = try MeshAgentWalletSignedRequestArtifact(
            walletIdentity: walletIdentity,
            signedRequest: signedRequest,
            signedAt: "2026-05-31T13:10:00Z"
        )
        let wallet = SignedArtifactAgentWallet(identity: walletIdentity, policy: policy, log: log)
        let anchorProvider = SignedArtifactAnchorProvider(identity: chainIdentity, log: log)
        let paymentExecutor = SignedArtifactPaymentExecutor(
            identity: chainIdentity,
            capabilities: [.executePayment],
            log: log
        )
        let submissionPath = MeshAgentWalletPaymentSubmissionPath(
            wallet: wallet,
            requestAnchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )

        do {
            _ = try await submissionPath.submitPayment(
                artifact: artifact,
                policy: policy,
                executionId: "exec-local-signature-artifact-bypass",
                amount: Decimal(42),
                currencyCode: "krw",
                tokenSymbol: "okrw",
                recipientAddress: "maroo1DailyMartMerchant",
                paymentId: "pay-local-signature-artifact-bypass",
                anchorSubmittedAt: "2026-05-31T13:10:01Z",
                anchorSignedAt: "2026-05-31T13:10:02Z",
                authorizationDecidedAt: "2026-05-31T13:10:03Z",
                paymentRequestedAt: "2026-05-31T13:10:04Z",
                paymentSubmittedAt: "2026-05-31T13:10:05Z"
            )
            XCTFail("Expected local-signature signed artifact to be rejected before execution")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("signingBoundary"))
        }

        XCTAssertEqual(log.events(), [])
    }

    func testAgentWalletPaymentSubmissionRejectsRawLocalSignatureRequestBeforeAnchorOrProviderExecution() async throws {
        let log = SignedArtifactSubmissionLog()
        let chainIdentity = try MeshMarooTestnetChainProvider().identity
        let walletIdentity = try agentWalletIdentity(
            chainIdentity: chainIdentity,
            signingBoundary: .localSignature
        )
        let policy = try delegatedSpendingPolicy()
        let wallet = SignedArtifactAgentWallet(identity: walletIdentity, policy: policy, log: log)
        let anchorProvider = SignedArtifactAnchorProvider(identity: chainIdentity, log: log)
        let paymentExecutor = SignedArtifactPaymentExecutor(
            identity: chainIdentity,
            capabilities: [.executePayment],
            log: log
        )
        let submissionPath = MeshAgentWalletPaymentSubmissionPath(
            wallet: wallet,
            requestAnchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )

        do {
            _ = try await submissionPath.submitPayment(
                request: dailyMartSignedRequest(),
                policy: policy,
                executionId: "exec-local-signature-request-bypass",
                amount: Decimal(42),
                currencyCode: "krw",
                tokenSymbol: "okrw",
                recipientAddress: "maroo1DailyMartMerchant",
                paymentId: "pay-local-signature-request-bypass",
                anchorSubmittedAt: "2026-05-31T13:11:01Z",
                anchorSignedAt: "2026-05-31T13:11:02Z",
                authorizationDecidedAt: "2026-05-31T13:11:03Z",
                paymentRequestedAt: "2026-05-31T13:11:04Z",
                paymentSubmittedAt: "2026-05-31T13:11:05Z"
            )
            XCTFail("Expected local-signature request to be rejected before execution")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("signingBoundary"))
        }

        XCTAssertEqual(log.events(), [])
    }

    private func delegatedSpendingPolicy() throws -> MeshAgentWalletDelegatedSpendingPolicy {
        try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64)),
            consentGrantId: "grant-hermes-dailymart-001",
            merchantScope: "merchant.dailymart",
            capabilityScope: "grocery.purchase_essentials",
            singlePaymentMax: Decimal(100),
            sessionTotalLimit: Decimal(500),
            remainingLimit: Decimal(500),
            expiresAt: "2026-06-30T00:00:00Z",
            asset: "OKRW",
            recipientAddress: "maroo1DailyMartMerchant"
        )
    }

    private func agentWalletIdentity(
        chainIdentity: MeshChainProviderIdentity,
        signingBoundary: MeshAgentWalletSigningBoundary = .providerSubmission
    ) throws -> MeshAgentWalletIdentity {
        try MeshAgentWalletIdentity(
            walletId: "wallet-signed-artifact-submission",
            agentId: "agent.hermes-chat.daily-mart",
            walletAddress: "maroo1DailyMartAgentWallet",
            providerMetadata: MeshAgentWalletProviderMetadata(
                chainProviderIdentity: chainIdentity,
                adapterId: "signed-artifact-submission-test-wallet"
            ),
            signingBoundary: signingBoundary
        )
    }

    private func dailyMartSignedRequest() -> MeshRequest {
        MeshRequest(
            requestId: "ios-grocery-signed-artifact-submission",
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
                "budget_krw": "42",
                "merchantScope": "merchant.dailymart",
                "capabilityScope": "grocery.purchase_essentials",
                "consentGrantId": "grant-hermes-dailymart-001",
                "policyId": "policy-hermes-dailymart-okrw-v1",
                "policyHash": String(repeating: "f", count: 64)
            ],
            nonce: "nonce-signed-artifact-submission",
            timestamp: "2026-05-31T13:00:00Z",
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "sample-ios-ed25519",
                value: "signed-artifact-request-signature"
            )
        )
    }
}

private final class SignedArtifactSubmissionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [String] = []

    func append(_ event: String) {
        lock.lock()
        defer { lock.unlock() }
        recordedEvents.append(event)
    }

    func events() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEvents
    }
}

private struct SignedArtifactAgentWallet: MeshAgentWallet {
    let identity: MeshAgentWalletIdentity
    let policy: MeshAgentWalletDelegatedSpendingPolicy
    let log: SignedArtifactSubmissionLog
    let capabilities: [MeshAgentWalletCapability] = [
        .authorizeExecution,
        .signRequestAnchorPayload,
        .validatePolicy
    ]

    func loadWalletConfiguration() throws -> MeshAgentWalletConfiguration {
        try MeshAgentWalletConfiguration(identity: identity, capabilities: capabilities)
    }

    func reportWalletAddress() throws -> String {
        try loadWalletConfiguration().require(.reportWalletAddress)
        return identity.walletAddress
    }

    func delegatedSpendingLimit() throws -> MeshAgentWalletDelegatedSpendingLimit {
        try loadWalletConfiguration().require(.reportDelegatedSpendingLimit)
        throw MeshKitValidationError.unsupportedCapability
    }

    func signingBoundary() throws -> MeshAgentWalletSigningBoundary {
        try loadWalletConfiguration().require(.exposeSigningBoundary)
        return identity.signingBoundary
    }

    func signRequestAnchorPayload(
        _ payload: MeshAgentWalletAnchorSigningPayload,
        signedAt: String
    ) throws -> MeshAgentWalletAnchorSignature {
        log.append("wallet.signRequestAnchorPayload")
        return try MeshAgentWalletAnchorSignature(
            walletIdentity: identity,
            payload: payload,
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "\(identity.walletId)#request-anchor",
                value: "signed-artifact-anchor-signature"
            ),
            signedAt: signedAt
        )
    }

    func signExecutionAuthorizationPayload(
        _ payload: MeshAgentWalletExecutionAuthorizationPayload,
        signedAt: String
    ) throws -> MeshAgentWalletExecutionAuthorization {
        throw MeshKitValidationError.unsupportedCapability
    }

    func authorizeExecution(
        _ request: MeshAgentWalletExecutionRequest,
        decidedAt: String
    ) throws -> MeshAgentWalletAuthorizationDecision {
        log.append("wallet.authorizeExecution:\(request.kind.rawValue)")
        try policy.validateExecutionRequest(request, requestedAt: decidedAt)
        return try MeshAgentWalletAuthorizationDecision(
            authorizationId: "auth-\(request.executionId)",
            walletIdentity: identity,
            executionRequest: request,
            status: .approved,
            approvedAmount: request.amount,
            decidedAt: decidedAt
        )
    }
}

private struct SignedArtifactAnchorProvider: MeshRequestAnchorProvider {
    let identity: MeshChainProviderIdentity
    let log: SignedArtifactSubmissionLog
    let capabilities: [MeshChainProviderCapability] = [.anchorSignedRequest]

    func anchorSignedRequest(
        payload: MeshRequestAnchorPayload,
        submittedAt: String
    ) async throws -> MeshRequestAnchor {
        log.append("anchor.submitPayload")
        return try MeshRequestAnchor(
            metadata: payload.metadata,
            payload: payload,
            identifier: MeshRequestAnchorIdentifier(
                identity: identity,
                anchorId: "anchor-\(payload.metadata.requestId)",
                transactionHash: "0xsignedArtifactAnchor"
            ),
            status: .confirmed,
            submittedAt: submittedAt,
            observedAt: submittedAt
        )
    }

    func anchorSignedRequest(
        metadata: MeshSignedRequestAnchorMetadata,
        submittedAt: String
    ) async throws -> MeshRequestAnchor {
        throw MeshKitValidationError.invalidChainProviderIdentity("metadata-only anchor path")
    }

    func requestAnchorStatus(
        identifier: MeshRequestAnchorIdentifier,
        checkedAt: String
    ) async throws -> MeshRequestAnchor {
        throw MeshKitValidationError.unsupportedCapability
    }
}

private struct SignedArtifactPaymentExecutor: MeshPaymentExecutor {
    let identity: MeshChainProviderIdentity
    let capabilities: [MeshPaymentExecutorCapability]
    let log: SignedArtifactSubmissionLog

    func loadPaymentExecutorConfiguration() throws -> MeshPaymentExecutorConfiguration {
        try MeshPaymentExecutorConfiguration(identity: identity, capabilities: capabilities)
    }

    func executePayment(
        _ request: MeshPaymentExecutionRequest,
        submittedAt: String
    ) async throws -> MeshPaymentExecutionResult {
        let requiredCapability: MeshPaymentExecutorCapability = request.executionRequest.kind == .payment
            ? .executePayment
            : .executeTransfer
        try loadPaymentExecutorConfiguration().require(requiredCapability)
        log.append("executor.executePayment:\(request.executionRequest.kind.rawValue)")
        return try MeshPaymentExecutionResult(
            request: request,
            identity: identity,
            status: .confirmed,
            transactionHash: "0xsignedArtifactPayment",
            observedAt: submittedAt
        )
    }

    func paymentExecutionStatus(
        paymentId: String,
        checkedAt: String
    ) async throws -> MeshPaymentExecutionResult {
        throw MeshKitValidationError.unsupportedCapability
    }
}
