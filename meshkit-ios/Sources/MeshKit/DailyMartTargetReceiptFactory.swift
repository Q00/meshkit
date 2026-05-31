import Foundation

public struct DailyMartTargetReceiptFactory: Sendable {
    public static let targetAppId = "app.dailymart"
    public static let targetBundleId = "ai.meshkit.sample.dailymart"

    public let signer: MeshReceiptSigner
    private let receiptIdGenerator: @Sendable (MeshRequest) throws -> String

    public init(signer: MeshReceiptSigner) {
        self.signer = signer
        self.receiptIdGenerator = { request in
            try DailyMartTargetReceiptFactory.freshReceiptId(for: request)
        }
    }

    public init(
        signer: MeshReceiptSigner,
        receiptIdGenerator: @escaping @Sendable (MeshRequest) throws -> String
    ) {
        self.signer = signer
        self.receiptIdGenerator = receiptIdGenerator
    }

    public func makeAcceptedCallReceipt(
        request: MeshRequest,
        status: String,
        baseResult: [String: String],
        chainProof: MeshChainProof? = nil,
        nonce: String = UUID().uuidString,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) throws -> MeshReceipt {
        try makeAcceptedCallReceipt(
            receiptId: receiptIdGenerator(request),
            request: request,
            status: status,
            baseResult: baseResult,
            chainProof: chainProof,
            nonce: nonce,
            timestamp: timestamp
        )
    }

    public func makeAcceptedCallReceipt(
        receiptId: String,
        request: MeshRequest,
        status: String,
        baseResult: [String: String],
        chainProof: MeshChainProof? = nil,
        nonce: String = UUID().uuidString,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) throws -> MeshReceipt {
        try makeAcceptedCallReceipt(
            receiptId: receiptId,
            request: request,
            status: status,
            baseResult: baseResult,
            chainProof: chainProof,
            enforceExecutionAttemptVerification: true,
            nonce: nonce,
            timestamp: timestamp
        )
    }

    private func makeAcceptedCallReceipt(
        receiptId: String,
        request: MeshRequest,
        status: String,
        baseResult: [String: String],
        chainProof: MeshChainProof? = nil,
        enforceExecutionAttemptVerification: Bool,
        nonce: String = UUID().uuidString,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) throws -> MeshReceipt {
        guard request.target.targetBundleId == Self.targetBundleId,
              request.target.capabilityId == DailyMartDelegatedSpendingPolicy.capabilityScope else {
            throw MeshKitValidationError.targetIdentityMismatch
        }

        let ownedResult = try MeshReceiptOwnershipMapper.targetOwnedResultFields(
            baseResult: baseResult,
            targetAppId: Self.targetAppId,
            targetBundleId: Self.targetBundleId
        )
        let result: [String: String]
        if let chainProof {
            if enforceExecutionAttemptVerification {
                try Self.validateVerifiedExecutionAttempt(
                    request: request,
                    baseResult: ownedResult,
                    chainProof: chainProof
                )
            }
            result = try MeshReceiptChainProofSerializer.receiptResultFields(
                baseResult: ownedResult,
                proof: chainProof
            )
        } else {
            result = ownedResult
        }

        let receipt = try signer.makeReceipt(
            receiptId: receiptId,
            request: request,
            targetAppId: Self.targetAppId,
            targetBundleId: Self.targetBundleId,
            status: status,
            result: result,
            nonce: nonce,
            timestamp: timestamp
        )
        try MeshReceiptOwnershipMapper.assertTargetOwned(
            receipt,
            expectedTargetAppId: Self.targetAppId,
            expectedTargetBundleId: Self.targetBundleId
        )
        return receipt
    }

    public func makePolicyDeniedWalletExecutionReceipt(
        request: MeshRequest,
        executionRequest: MeshAgentWalletExecutionRequest,
        providerIdentity: MeshChainProviderIdentity,
        walletAddress: String,
        anchoringReference: String,
        denialReason: String,
        baseResult: [String: String] = [:],
        errorCode: String = "policy_denied",
        nonce: String = UUID().uuidString,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) throws -> MeshReceipt {
        try makePolicyDeniedWalletExecutionReceipt(
            receiptId: receiptIdGenerator(request),
            request: request,
            executionRequest: executionRequest,
            providerIdentity: providerIdentity,
            walletAddress: walletAddress,
            anchoringReference: anchoringReference,
            denialReason: denialReason,
            baseResult: baseResult,
            errorCode: errorCode,
            nonce: nonce,
            timestamp: timestamp
        )
    }

    public func makePolicyDeniedWalletExecutionReceipt(
        receiptId: String,
        request: MeshRequest,
        executionRequest: MeshAgentWalletExecutionRequest,
        providerIdentity: MeshChainProviderIdentity,
        walletAddress: String,
        anchoringReference: String,
        denialReason: String,
        baseResult: [String: String] = [:],
        errorCode: String = "policy_denied",
        nonce: String = UUID().uuidString,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) throws -> MeshReceipt {
        try executionRequest.validate()
        let signedRequestHash = try MeshRequestAnchorCanonicalization.signedRequestHash(for: request)
        guard executionRequest.requestAnchorMetadata.requestId == request.requestId,
              executionRequest.requestAnchorMetadata.nonce == request.nonce,
              executionRequest.requestAnchorMetadata.signedRequestHash == signedRequestHash else {
            throw MeshKitValidationError.invalidPaymentExecution("requestAnchorMetadata")
        }

        let denialError = try Self.policyDenialErrorFields(
            baseResult: baseResult,
            fallbackErrorCode: errorCode,
            fallbackErrorMessage: denialReason
        )
        let proof = try MeshChainProof(
            provider: providerIdentity.provider,
            chainId: providerIdentity.chainId,
            network: providerIdentity.network,
            proofType: .policyDenial,
            status: .failed,
            presentationState: .policyDenied,
            requestHash: executionRequest.requestAnchorMetadata.signedRequestHash,
            requestNonce: executionRequest.requestAnchorMetadata.nonce,
            policyId: executionRequest.policyId,
            policyHash: executionRequest.policyHash,
            walletAddress: walletAddress,
            amount: executionRequest.amount,
            asset: executionRequest.tokenSymbol ?? executionRequest.currencyCode ?? DailyMartDelegatedSpendingPolicy.asset,
            recipient: executionRequest.recipientAddress,
            anchoringReference: anchoringReference,
            executionAttemptId: MeshChainProof.executionAttemptIdentity(executionId: executionRequest.executionId),
            executionId: executionRequest.executionId,
            errorCode: denialError.errorCode,
            errorMessage: denialError.errorMessage,
            submittedAt: timestamp
        )
        var deniedResult = baseResult
        deniedResult["policy_verification"] = MeshDelegatedSpendingPolicyVerificationStatus.denied.rawValue
        return try makeAcceptedCallReceipt(
            receiptId: receiptId,
            request: request,
            status: "failed",
            baseResult: deniedResult,
            chainProof: proof,
            enforceExecutionAttemptVerification: false,
            nonce: nonce,
            timestamp: timestamp
        )
    }

    public func makeVerifiedWalletExecutionReceipt(
        request: MeshRequest,
        paymentResult: MeshPaymentExecutionResult,
        executionRequest: MeshAgentWalletExecutionRequest,
        walletAddress: String,
        baseResult: [String: String],
        nonce: String = UUID().uuidString,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) throws -> MeshReceipt {
        try makeVerifiedWalletExecutionReceipt(
            receiptId: receiptIdGenerator(request),
            request: request,
            paymentResult: paymentResult,
            executionRequest: executionRequest,
            walletAddress: walletAddress,
            baseResult: baseResult,
            nonce: nonce,
            timestamp: timestamp
        )
    }

    public func makeVerifiedWalletExecutionReceipt(
        request: MeshRequest,
        orchestrationResult: DailyMartGuardOrchestrationResult,
        walletAddress: String,
        baseResult: [String: String],
        nonce: String = UUID().uuidString,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) throws -> MeshReceipt {
        try makeVerifiedWalletExecutionReceipt(
            receiptId: receiptIdGenerator(request),
            request: request,
            orchestrationResult: orchestrationResult,
            walletAddress: walletAddress,
            baseResult: baseResult,
            nonce: nonce,
            timestamp: timestamp
        )
    }

    public func makeVerifiedWalletExecutionReceipt(
        receiptId: String,
        request: MeshRequest,
        orchestrationResult: DailyMartGuardOrchestrationResult,
        walletAddress: String,
        baseResult: [String: String],
        nonce: String = UUID().uuidString,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) throws -> MeshReceipt {
        try orchestrationResult.validate()
        guard orchestrationResult.requestId == request.requestId,
              orchestrationResult.nonce == request.nonce else {
            throw MeshKitValidationError.invalidPaymentExecution("orchestrationResult")
        }
        guard let guardResult = orchestrationResult.guardResult,
              let paymentResult = orchestrationResult.paymentResult else {
            throw MeshKitValidationError.invalidPaymentExecution("verifiedExecutionAttempt")
        }

        return try makeVerifiedWalletExecutionReceipt(
            receiptId: receiptId,
            request: request,
            paymentResult: paymentResult,
            executionRequest: guardResult.executionRequest,
            walletAddress: walletAddress,
            baseResult: baseResult,
            nonce: nonce,
            timestamp: timestamp
        )
    }

    public func makeVerifiedWalletExecutionReceipt(
        receiptId: String,
        request: MeshRequest,
        paymentResult: MeshPaymentExecutionResult,
        executionRequest: MeshAgentWalletExecutionRequest,
        walletAddress: String,
        baseResult: [String: String],
        nonce: String = UUID().uuidString,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) throws -> MeshReceipt {
        let linkage = try MeshPaymentExecutionReceiptLinkageMapper.map(
            paymentResult: paymentResult,
            executionRequest: executionRequest,
            walletAddress: walletAddress
        )
        guard linkage.proof.proofType != .policyDenial else {
            throw MeshKitValidationError.invalidPaymentExecution("policyDeniedReceipt")
        }

        return try makeAcceptedCallReceipt(
            receiptId: receiptId,
            request: request,
            status: Self.receiptStatus(for: linkage.proof.status),
            baseResult: baseResult,
            chainProof: linkage.proof,
            nonce: nonce,
            timestamp: timestamp
        )
    }

    private static func policyDenialErrorFields(
        baseResult: [String: String],
        fallbackErrorCode: String,
        fallbackErrorMessage: String
    ) throws -> (errorCode: String, errorMessage: String) {
        let resolvedErrorCode = baseResult["errorCode"] ?? fallbackErrorCode
        let resolvedErrorMessage = baseResult["errorMessage"] ?? fallbackErrorMessage
        return (
            errorCode: try MeshChainProof.stableReceiptField("errorCode", resolvedErrorCode),
            errorMessage: try MeshChainProof.stableReceiptField("errorMessage", resolvedErrorMessage)
        )
    }

    private static func validateVerifiedExecutionAttempt(
        request: MeshRequest,
        baseResult: [String: String],
        chainProof: MeshChainProof
    ) throws {
        try chainProof.validate()
        guard chainProof.proofType != .policyDenial else {
            throw MeshKitValidationError.invalidPaymentExecution("policyDeniedReceipt")
        }

        let signedRequestHash = try MeshRequestAnchorCanonicalization.signedRequestHash(for: request)
        guard chainProof.requestHash == signedRequestHash else {
            throw MeshKitValidationError.invalidChainProof("requestHash")
        }
        guard chainProof.requestNonce == request.nonce else {
            throw MeshKitValidationError.invalidChainProof("requestNonce")
        }
        guard chainProof.policyId == DailyMartDelegatedSpendingPolicy.policyId,
              chainProof.policyHash == DailyMartDelegatedSpendingPolicy.policyHash else {
            throw MeshKitValidationError.invalidChainProof("policyId")
        }
        guard baseResult["policy_verification"] == MeshDelegatedSpendingPolicyVerificationStatus.approved.rawValue else {
            throw MeshKitValidationError.invalidPaymentExecution("policyVerification")
        }
    }

    private static func receiptStatus(for chainStatus: MeshChainProofStatus) -> String {
        switch chainStatus {
        case .confirmed:
            return "confirmed"
        case .pending:
            return "pending"
        case .failed:
            return "failed"
        }
    }

    private static func freshReceiptId(for request: MeshRequest) throws -> String {
        try MeshAgentWalletProviderMetadata.stableValue(
            "receiptId",
            "dailymart-\(request.requestId)-receipt-\(UUID().uuidString)"
        )
    }
}
