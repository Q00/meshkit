import XCTest
@testable import MeshKit

final class MeshAgentWalletSubmissionPolicyOrderingTests: XCTestCase {
    func testPaymentSubmissionPathRejectsPolicyDeniedRequestBeforeWalletSigningOrProviderSubmission() async throws {
        let log = SubmissionPolicyOrderingLog()
        let policy = try delegatedSpendingPolicy(singlePaymentMax: Decimal(100))
        let request = signedDailyMartRequest(amount: Decimal(101))
        let chainIdentity = try MeshMarooTestnetChainProvider().identity
        let wallet = try OrderingAgentWallet(
            identity: walletIdentity(chainIdentity: chainIdentity),
            log: log
        )
        let anchorProvider = OrderingAnchorProvider(identity: chainIdentity, log: log)
        let paymentExecutor = OrderingPaymentExecutor(identity: chainIdentity, log: log)
        let submissionPath = MeshAgentWalletPaymentSubmissionPath(
            wallet: wallet,
            requestAnchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )

        do {
            _ = try await submissionPath.submitPayment(
                request: request,
                policy: policy,
                executionId: "exec-policy-ordering-denied",
                amount: Decimal(101),
                currencyCode: "krw",
                tokenSymbol: "okrw",
                recipientAddress: "maroo1DailyMartMerchant",
                paymentId: "pay-policy-ordering-denied",
                anchorSubmittedAt: "2026-05-31T12:00:01Z",
                anchorSignedAt: "2026-05-31T12:00:02Z",
                authorizationDecidedAt: "2026-05-31T12:00:03Z",
                paymentRequestedAt: "2026-05-31T12:00:04Z",
                paymentSubmittedAt: "2026-05-31T12:00:05Z"
            )
            XCTFail("Expected delegated spending policy denial before wallet signing or provider submission")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("singlePaymentMax"))
        }

        let events = await log.events()
        XCTAssertEqual(events, [])
    }

    func testPaymentSubmissionPathRejectsPolicyExpiredAtPaymentRequestBeforeWalletSigningOrProviderSubmission() async throws {
        let log = SubmissionPolicyOrderingLog()
        let policy = try delegatedSpendingPolicy(
            singlePaymentMax: Decimal(100),
            startsAt: "2026-05-31T11:59:00Z",
            expiresAt: "2026-05-31T12:00:02Z"
        )
        let request = signedDailyMartRequest(amount: Decimal(50))
        let chainIdentity = try MeshMarooTestnetChainProvider().identity
        let wallet = try OrderingAgentWallet(
            identity: walletIdentity(chainIdentity: chainIdentity),
            log: log
        )
        let anchorProvider = OrderingAnchorProvider(identity: chainIdentity, log: log)
        let paymentExecutor = OrderingPaymentExecutor(identity: chainIdentity, log: log)
        let submissionPath = MeshAgentWalletPaymentSubmissionPath(
            wallet: wallet,
            requestAnchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )

        do {
            _ = try await submissionPath.submitPayment(
                request: request,
                policy: policy,
                executionId: "exec-policy-ordering-expired-at-payment",
                amount: Decimal(50),
                currencyCode: "krw",
                tokenSymbol: "okrw",
                recipientAddress: "maroo1DailyMartMerchant",
                paymentId: "pay-policy-ordering-expired-at-payment",
                anchorSubmittedAt: "2026-05-31T12:00:01Z",
                anchorSignedAt: "2026-05-31T12:00:01Z",
                authorizationDecidedAt: "2026-05-31T12:00:02Z",
                paymentRequestedAt: "2026-05-31T12:00:03Z",
                paymentSubmittedAt: "2026-05-31T12:00:04Z"
            )
            XCTFail("Expected expired delegated spending policy to reject before wallet signing or provider submission")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("expiresAt"))
        }

        let events = await log.events()
        XCTAssertEqual(events, [])
    }

    private func delegatedSpendingPolicy(
        singlePaymentMax: Decimal,
        startsAt: String? = nil,
        expiresAt: String = "2026-06-30T00:00:00Z"
    ) throws -> MeshAgentWalletDelegatedSpendingPolicy {
        try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64)),
            consentGrantId: "grant-hermes-dailymart-001",
            merchantScope: "merchant.dailymart",
            capabilityScope: "grocery.purchase_essentials",
            singlePaymentMax: singlePaymentMax,
            sessionTotalLimit: Decimal(500),
            remainingLimit: Decimal(500),
            startsAt: startsAt,
            expiresAt: expiresAt,
            asset: "OKRW",
            recipientAddress: "maroo1DailyMartMerchant"
        )
    }

    private func walletIdentity(chainIdentity: MeshChainProviderIdentity) throws -> MeshAgentWalletIdentity {
        try MeshAgentWalletIdentity(
            walletId: "wallet-policy-ordering",
            agentId: "agent.hermes-chat.daily-mart",
            walletAddress: "maroo1DailyMartAgentWallet",
            providerMetadata: MeshAgentWalletProviderMetadata(
                chainProviderIdentity: chainIdentity,
                adapterId: "ordering-test-agent-wallet"
            ),
            signingBoundary: .providerSubmission
        )
    }

    private func signedDailyMartRequest(amount: Decimal) -> MeshRequest {
        MeshRequest(
            requestId: "ios-grocery-policy-ordering-denied",
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
                "budget_krw": "\(amount)",
                "merchantScope": "merchant.dailymart",
                "capabilityScope": "grocery.purchase_essentials",
                "consentGrantId": "grant-hermes-dailymart-001",
                "policyId": "policy-hermes-dailymart-okrw-v1",
                "policyHash": String(repeating: "f", count: 64)
            ],
            nonce: "nonce-policy-ordering-denied",
            timestamp: "2026-05-31T12:00:00Z",
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "sample-ios-ed25519",
                value: "test-signature"
            )
        )
    }
}

private actor SubmissionPolicyOrderingLog {
    private var recordedEvents: [String] = []

    func append(_ event: String) {
        recordedEvents.append(event)
    }

    func events() -> [String] {
        recordedEvents
    }
}

private struct OrderingAgentWallet: MeshAgentWallet {
    let identity: MeshAgentWalletIdentity
    let log: SubmissionPolicyOrderingLog
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
        Task { await log.append("wallet.signRequestAnchorPayload") }
        throw MeshKitValidationError.signatureRequired
    }

    func signExecutionAuthorizationPayload(
        _ payload: MeshAgentWalletExecutionAuthorizationPayload,
        signedAt: String
    ) throws -> MeshAgentWalletExecutionAuthorization {
        Task { await log.append("wallet.signExecutionAuthorizationPayload") }
        throw MeshKitValidationError.signatureRequired
    }

    func authorizeExecution(
        _ request: MeshAgentWalletExecutionRequest,
        decidedAt: String
    ) throws -> MeshAgentWalletAuthorizationDecision {
        Task { await log.append("wallet.authorizeExecution") }
        throw MeshKitValidationError.invalidPaymentExecution("authorizationDecision")
    }
}

private struct OrderingAnchorProvider: MeshRequestAnchorProvider {
    let identity: MeshChainProviderIdentity
    let log: SubmissionPolicyOrderingLog
    let capabilities: [MeshChainProviderCapability] = [.anchorSignedRequest]

    func anchorSignedRequest(
        metadata: MeshSignedRequestAnchorMetadata,
        submittedAt: String
    ) async throws -> MeshRequestAnchor {
        await log.append("provider.anchorSignedRequest")
        throw MeshKitValidationError.invalidChainProviderIdentity("anchorSignedRequest")
    }

    func requestAnchorStatus(
        identifier: MeshRequestAnchorIdentifier,
        checkedAt: String
    ) async throws -> MeshRequestAnchor {
        throw MeshKitValidationError.unsupportedCapability
    }
}

private struct OrderingPaymentExecutor: MeshPaymentExecutor {
    let identity: MeshChainProviderIdentity
    let log: SubmissionPolicyOrderingLog
    let capabilities: [MeshPaymentExecutorCapability] = [.executePayment]

    func loadPaymentExecutorConfiguration() throws -> MeshPaymentExecutorConfiguration {
        try MeshPaymentExecutorConfiguration(identity: identity, capabilities: capabilities)
    }

    func executePayment(
        _ request: MeshPaymentExecutionRequest,
        submittedAt: String
    ) async throws -> MeshPaymentExecutionResult {
        await log.append("provider.executePayment")
        throw MeshKitValidationError.invalidPaymentExecution("executePayment")
    }

    func paymentExecutionStatus(
        paymentId: String,
        checkedAt: String
    ) async throws -> MeshPaymentExecutionResult {
        throw MeshKitValidationError.unsupportedCapability
    }
}
