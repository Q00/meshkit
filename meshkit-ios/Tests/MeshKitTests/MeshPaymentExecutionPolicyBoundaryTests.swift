import XCTest
@testable import MeshKit

final class MeshPaymentExecutionPolicyBoundaryTests: XCTestCase {
    func testSubmitAndExecuteAllowsPerPaymentMaximumAmountThroughProviderExecution() async throws {
        let recorder = PaymentBoundaryRecorder()
        let anchorProvider = try BoundaryAnchorProvider(recorder: recorder)
        let paymentExecutor = try BoundaryPaymentExecutor(identity: anchorProvider.identity, recorder: recorder)
        let policy = try delegatedSpendingPolicy(singlePaymentMax: Decimal(100))
        let request = dailyMartRequest(amount: Decimal(100))
        let submission = try MeshRequestAnchorSubmission(
            request: request,
            policy: policy,
            providerIdentity: anchorProvider.identity,
            submittedAt: "2026-05-31T12:00:01Z"
        )
        let executionRequest = try MeshAgentWalletExecutionRequest(
            executionId: "exec-at-per-payment-max",
            kind: .payment,
            requestAnchorMetadata: MeshSignedRequestAnchorMetadata(request: request),
            scope: MeshAgentWalletSpendingScope(
                merchantId: policy.merchantScope,
                targetBundleId: request.target.targetBundleId,
                capabilityId: policy.capabilityScope,
                consentGrantId: policy.consentGrantId
            ),
            amount: Decimal(100),
            currencyCode: "KRW",
            tokenSymbol: "OKRW",
            recipientAddress: "0x000000000000000000000000000000000000d417",
            policyId: policy.policyId,
            policyHash: policy.policyHash
        )
        let authorizationDecision = try MeshAgentWalletAuthorizationDecision(
            authorizationId: "auth-at-per-payment-max",
            walletIdentity: walletIdentity(providerIdentity: anchorProvider.identity),
            executionRequest: executionRequest,
            status: .approved,
            approvedAmount: Decimal(100),
            decidedAt: "2026-05-31T12:00:02Z"
        )
        let submissionModule = MeshRequestAnchorSubmissionModule(provider: anchorProvider)

        let result = try await submissionModule.submitAndExecute(
            submission,
            boundTo: request,
            policy: policy,
            authorizationDecision: authorizationDecision,
            paymentId: "pay-at-per-payment-max",
            requestedAt: "2026-05-31T12:00:03Z",
            paymentSubmittedAt: "2026-05-31T12:00:04Z",
            executor: paymentExecutor
        )

        XCTAssertEqual(result.status, .confirmed)
        XCTAssertEqual(result.amount, Decimal(100))
        XCTAssertEqual(result.tokenSymbol, "OKRW")
        let anchorCallCount = await recorder.anchorCallCount()
        let paymentExecutionCallCount = await recorder.paymentExecutionCallCount()
        XCTAssertEqual(anchorCallCount, 1)
        XCTAssertEqual(paymentExecutionCallCount, 1)
    }

    func testSubmitAndExecuteRejectsPerPaymentMaximumBeforeProviderExecution() async throws {
        let recorder = PaymentBoundaryRecorder()
        let anchorProvider = try BoundaryAnchorProvider(recorder: recorder)
        let paymentExecutor = try BoundaryPaymentExecutor(identity: anchorProvider.identity, recorder: recorder)
        let policy = try delegatedSpendingPolicy(singlePaymentMax: Decimal(100))
        let request = dailyMartRequest(amount: Decimal(101))
        let submission = try MeshRequestAnchorSubmission(
            request: request,
            policy: policy,
            providerIdentity: anchorProvider.identity,
            submittedAt: "2026-05-31T12:00:01Z"
        )
        let executionRequest = try MeshAgentWalletExecutionRequest(
            executionId: "exec-over-per-payment-max",
            kind: .payment,
            requestAnchorMetadata: MeshSignedRequestAnchorMetadata(request: request),
            scope: MeshAgentWalletSpendingScope(
                merchantId: policy.merchantScope,
                targetBundleId: request.target.targetBundleId,
                capabilityId: policy.capabilityScope,
                consentGrantId: policy.consentGrantId
            ),
            amount: Decimal(101),
            currencyCode: "KRW",
            tokenSymbol: "OKRW",
            recipientAddress: "0x000000000000000000000000000000000000d417",
            policyId: policy.policyId,
            policyHash: policy.policyHash
        )
        let authorizationDecision = try MeshAgentWalletAuthorizationDecision(
            authorizationId: "auth-over-per-payment-max",
            walletIdentity: walletIdentity(providerIdentity: anchorProvider.identity),
            executionRequest: executionRequest,
            status: .approved,
            approvedAmount: Decimal(101),
            decidedAt: "2026-05-31T12:00:02Z"
        )
        let submissionModule = MeshRequestAnchorSubmissionModule(provider: anchorProvider)

        do {
            _ = try await submissionModule.submitAndExecute(
                submission,
                boundTo: request,
                policy: policy,
                authorizationDecision: authorizationDecision,
                paymentId: "pay-over-per-payment-max",
                requestedAt: "2026-05-31T12:00:03Z",
                paymentSubmittedAt: "2026-05-31T12:00:04Z",
                executor: paymentExecutor
            )
            XCTFail("Expected per-payment max denial before provider execution")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("singlePaymentMax"))
        }

        let anchorCallCount = await recorder.anchorCallCount()
        let paymentExecutionCallCount = await recorder.paymentExecutionCallCount()
        XCTAssertEqual(anchorCallCount, 0)
        XCTAssertEqual(paymentExecutionCallCount, 0)
    }

    private func delegatedSpendingPolicy(singlePaymentMax: Decimal) throws -> MeshAgentWalletDelegatedSpendingPolicy {
        try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64)),
            consentGrantId: "grant-hermes-dailymart-001",
            merchantScope: "merchant.dailymart",
            capabilityScope: "grocery.purchase_essentials",
            singlePaymentMax: singlePaymentMax,
            sessionTotalLimit: Decimal(500),
            remainingLimit: Decimal(500),
            expiresAt: "2026-06-30T00:00:00Z",
            asset: "OKRW",
            recipientAddress: "0x000000000000000000000000000000000000d417"
        )
    }

    private func dailyMartRequest(amount: Decimal) -> MeshRequest {
        MeshRequest(
            requestId: "ios-grocery-payment-boundary-over-max",
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
            nonce: "nonce-payment-boundary-over-max",
            timestamp: "2026-05-31T12:00:00Z",
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "sample-ios-ed25519",
                value: "test-signature"
            )
        )
    }

    private func walletIdentity(providerIdentity: MeshChainProviderIdentity) throws -> MeshAgentWalletIdentity {
        try MeshAgentWalletIdentity(
            walletId: "dailymart-agent-wallet-demo",
            agentId: "app.hermes-chat",
            walletAddress: "maroo1dailyMartAgentWallet",
            providerMetadata: MeshAgentWalletProviderMetadata(
                chainProviderIdentity: providerIdentity,
                adapterId: "dailymart-agent-wallet-demo-adapter"
            ),
            signingBoundary: .providerSubmission
        )
    }
}

private actor PaymentBoundaryRecorder {
    private var anchorCalls = 0
    private var paymentExecutionCalls = 0

    func recordAnchorCall() {
        anchorCalls += 1
    }

    func recordPaymentExecutionCall() {
        paymentExecutionCalls += 1
    }

    func anchorCallCount() -> Int {
        anchorCalls
    }

    func paymentExecutionCallCount() -> Int {
        paymentExecutionCalls
    }
}

private struct BoundaryAnchorProvider: MeshRequestAnchorProvider {
    let identity: MeshChainProviderIdentity
    let capabilities: [MeshChainProviderCapability] = [.anchorSignedRequest, .lookupRequestAnchorStatus]
    let recorder: PaymentBoundaryRecorder

    init(recorder: PaymentBoundaryRecorder) throws {
        self.identity = try MeshChainProviderIdentity(
            providerName: "maroo",
            networkIdentity: "maroo-testnet",
            chainId: "maroo-testnet-1",
            rpcEndpoint: URL(string: "https://rpc-testnet.maroo.io")!,
            explorerBaseURL: URL(string: "https://explorer-testnet.maroo.io")!
        )
        self.recorder = recorder
    }

    func anchorSignedRequest(
        metadata: MeshSignedRequestAnchorMetadata,
        submittedAt: String
    ) async throws -> MeshRequestAnchor {
        await recorder.recordAnchorCall()
        return try MeshRequestAnchor(
            metadata: metadata,
            identifier: MeshRequestAnchorIdentifier(
                identity: identity,
                anchorId: "anchor-\(metadata.requestId)",
                transactionHash: "0xanchor"
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

private struct BoundaryPaymentExecutor: MeshPaymentExecutor {
    let identity: MeshChainProviderIdentity
    let capabilities: [MeshPaymentExecutorCapability] = [.executePayment, .lookupExecutionStatus]
    let recorder: PaymentBoundaryRecorder

    init(identity: MeshChainProviderIdentity, recorder: PaymentBoundaryRecorder) throws {
        self.identity = identity
        self.recorder = recorder
    }

    func loadPaymentExecutorConfiguration() throws -> MeshPaymentExecutorConfiguration {
        try MeshPaymentExecutorConfiguration(identity: identity, capabilities: capabilities)
    }

    func executePayment(
        _ request: MeshPaymentExecutionRequest,
        submittedAt: String
    ) async throws -> MeshPaymentExecutionResult {
        await recorder.recordPaymentExecutionCall()
        return try MeshPaymentExecutionResult(
            request: request,
            identity: identity,
            status: .confirmed,
            transactionHash: "0xpayment",
            observedAt: submittedAt
        )
    }

    func paymentExecutionStatus(
        paymentId: String,
        checkedAt: String
    ) async throws -> MeshPaymentExecutionResult {
        throw MeshKitValidationError.invalidPaymentExecution("paymentId")
    }
}
