import Foundation

public enum MeshDelegatedSpendReceiptIneligibilityReason: String, Codable, Equatable, Sendable {
    case notTargetOwned
    case unsupportedAsset
    case unsupportedExecutionKind
    case notConfirmed
    case notPaymentExecution
    case missingTransactionProof
}

public struct MeshDelegatedSpendReceiptEligibility: Codable, Equatable, Sendable {
    public let receiptId: String
    public let requestId: String
    public let isEligibleForDelegatedLimitDecrement: Bool
    public let reason: MeshDelegatedSpendReceiptIneligibilityReason?
    public let proof: MeshChainProof
    public let executionKind: MeshAgentWalletExecutionKind?
    public let debitAmount: Decimal?
    public let asset: String
    public let transactionHash: String?
    public let anchoringReference: String

    public init(
        receiptId: String,
        requestId: String,
        isEligibleForDelegatedLimitDecrement: Bool,
        reason: MeshDelegatedSpendReceiptIneligibilityReason?,
        proof: MeshChainProof,
        executionKind: MeshAgentWalletExecutionKind?,
        debitAmount: Decimal?,
        asset: String,
        transactionHash: String?,
        anchoringReference: String
    ) throws {
        self.receiptId = try MeshChainProof.stableReceiptField("receiptId", receiptId)
        self.requestId = try MeshChainProof.stableReceiptField("requestId", requestId)
        self.isEligibleForDelegatedLimitDecrement = isEligibleForDelegatedLimitDecrement
        self.reason = reason
        self.proof = proof
        self.executionKind = executionKind
        self.debitAmount = debitAmount
        self.asset = try Self.normalizedAsset(asset)
        self.transactionHash = try transactionHash.map { try MeshChainProof.stableReceiptField("transactionHash", $0) }
        self.anchoringReference = try MeshChainProof.stableReceiptField(
            "anchoringReference",
            anchoringReference
        )
        try validate()
    }

    public func validate() throws {
        _ = try MeshChainProof.stableReceiptField("receiptId", receiptId)
        _ = try MeshChainProof.stableReceiptField("requestId", requestId)
        try proof.validate()
        try MeshAgentWalletProviderMetadata.validateIdentifier("asset", asset)
        if let transactionHash {
            _ = try MeshChainProof.stableReceiptField("transactionHash", transactionHash)
        }
        _ = try MeshChainProof.stableReceiptField("anchoringReference", anchoringReference)
        if isEligibleForDelegatedLimitDecrement {
            guard reason == nil else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("reason")
            }
            guard debitAmount == proof.amount,
                  debitAmount ?? 0 > 0 else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("debitAmount")
            }
            guard transactionHash == proof.txHash,
                  transactionHash != nil else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("transactionHash")
            }
        } else {
            guard reason != nil, debitAmount == nil else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("eligibility")
            }
        }
    }

    private static func normalizedAsset(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("asset")
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("asset", normalized)
        return normalized
    }
}

public struct MeshDelegatedSpendConfirmedExecutionAmount: Codable, Equatable, Sendable {
    public let receiptId: String
    public let requestId: String
    public let amount: Decimal
    public let denomination: String
    public let executionKind: MeshAgentWalletExecutionKind
    public let transactionHash: String
    public let anchoringReference: String
    public let policyId: String
    public let policyHash: MeshPayloadHash

    public init(
        receiptId: String,
        requestId: String,
        amount: Decimal,
        denomination: String,
        executionKind: MeshAgentWalletExecutionKind,
        transactionHash: String,
        anchoringReference: String,
        policyId: String,
        policyHash: MeshPayloadHash
    ) throws {
        self.receiptId = try MeshChainProof.stableReceiptField("receiptId", receiptId)
        self.requestId = try MeshChainProof.stableReceiptField("requestId", requestId)
        guard amount > 0 else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("amount")
        }
        self.amount = amount
        self.denomination = try MeshDelegatedSpendConfirmedExecutionAmountExtractor.normalizedDenomination(
            denomination
        )
        self.executionKind = executionKind
        self.transactionHash = try MeshChainProof.stableReceiptField("transactionHash", transactionHash)
        self.anchoringReference = try MeshChainProof.stableReceiptField(
            "anchoringReference",
            anchoringReference
        )
        self.policyId = try MeshChainProof.stableReceiptField("policyId", policyId)
        self.policyHash = policyHash
    }
}

public enum MeshDelegatedSpendConfirmedExecutionAmountExtractor {
    public static let okrwDenomination = "OKRW"

    public static func confirmedOKRWAmount(
        from receipt: MeshReceipt,
        spendingLimit: MeshAgentWalletDelegatedSpendingLimit,
        expectedTargetAppId: String? = nil,
        expectedTargetBundleId: String? = nil
    ) throws -> MeshDelegatedSpendConfirmedExecutionAmount? {
        try confirmedAmount(
            from: receipt,
            spendingLimit: spendingLimit,
            expectedDenomination: okrwDenomination,
            expectedTargetAppId: expectedTargetAppId,
            expectedTargetBundleId: expectedTargetBundleId
        )
    }

    public static func confirmedAmount(
        from receipt: MeshReceipt,
        spendingLimit: MeshAgentWalletDelegatedSpendingLimit,
        expectedDenomination: String? = nil,
        expectedTargetAppId: String? = nil,
        expectedTargetBundleId: String? = nil
    ) throws -> MeshDelegatedSpendConfirmedExecutionAmount? {
        try spendingLimit.validate()
        let denomination = try canonicalDenomination(for: spendingLimit)
        if let expectedDenomination {
            guard denomination == (try normalizedDenomination(expectedDenomination)) else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("denomination")
            }
        }

        let eligibility = try MeshDelegatedSpendReceiptEligibilityEvaluator.evaluate(
            receipt: receipt,
            expectedAsset: denomination,
            expectedTargetAppId: expectedTargetAppId,
            expectedTargetBundleId: expectedTargetBundleId
        )
        guard eligibility.isEligibleForDelegatedLimitDecrement,
              let amount = eligibility.debitAmount,
              let executionKind = eligibility.executionKind,
              let transactionHash = eligibility.transactionHash else {
            return nil
        }

        return try MeshDelegatedSpendConfirmedExecutionAmount(
            receiptId: eligibility.receiptId,
            requestId: eligibility.requestId,
            amount: amount,
            denomination: denomination,
            executionKind: executionKind,
            transactionHash: transactionHash,
            anchoringReference: eligibility.anchoringReference,
            policyId: eligibility.proof.policyId,
            policyHash: eligibility.proof.policyHash
        )
    }

    public static func canonicalDenomination(
        for spendingLimit: MeshAgentWalletDelegatedSpendingLimit
    ) throws -> String {
        if let tokenSymbol = spendingLimit.tokenSymbol {
            return try normalizedDenomination(tokenSymbol)
        }
        if let currencyCode = spendingLimit.currencyCode {
            return try normalizedDenomination(currencyCode)
        }
        throw MeshKitValidationError.invalidAgentWalletIdentity("denomination")
    }

    static func normalizedDenomination(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("denomination")
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("denomination", normalized)
        return normalized
    }
}

public enum MeshDelegatedSpendReceiptEligibilityEvaluator {
    public static let okrwAsset = "OKRW"
    public static let allowedExecutionKinds: Set<MeshAgentWalletExecutionKind> = [.payment, .transfer]

    public static func evaluate(
        receipt: MeshReceipt,
        expectedAsset: String = okrwAsset,
        allowedExecutionKinds: Set<MeshAgentWalletExecutionKind> = allowedExecutionKinds,
        expectedTargetAppId: String? = nil,
        expectedTargetBundleId: String? = nil
    ) throws -> MeshDelegatedSpendReceiptEligibility {
        let proof = try MeshReceiptChainProofSerializer.decodeProof(from: receipt.result)
        let targetOwned = try isTargetOwned(
            receipt,
            expectedTargetAppId: expectedTargetAppId,
            expectedTargetBundleId: expectedTargetBundleId
        )
        let normalizedExpectedAsset = try normalizeAsset(expectedAsset)
        let normalizedProofAsset = try normalizeAsset(proof.asset)

        if !targetOwned {
            return try ineligible(receipt: receipt, proof: proof, reason: .notTargetOwned)
        }
        guard normalizedProofAsset == normalizedExpectedAsset else {
            return try ineligible(receipt: receipt, proof: proof, reason: .unsupportedAsset)
        }
        guard proof.proofType == .paymentExecution else {
            return try ineligible(receipt: receipt, proof: proof, reason: .notPaymentExecution)
        }
        guard proof.status == .confirmed,
              proof.presentationState == .paidComplete else {
            return try ineligible(receipt: receipt, proof: proof, reason: .notConfirmed)
        }
        guard let executionKind = proof.executionKind,
              allowedExecutionKinds.contains(executionKind) else {
            return try ineligible(receipt: receipt, proof: proof, reason: .unsupportedExecutionKind)
        }
        guard proof.txHash != nil,
              try proof.transactionReference() != nil else {
            return try ineligible(receipt: receipt, proof: proof, reason: .missingTransactionProof)
        }

        return try MeshDelegatedSpendReceiptEligibility(
            receiptId: receipt.receiptId,
            requestId: receipt.requestId,
            isEligibleForDelegatedLimitDecrement: true,
            reason: nil,
            proof: proof,
            executionKind: executionKind,
            debitAmount: proof.amount,
            asset: normalizedProofAsset,
            transactionHash: proof.txHash,
            anchoringReference: proof.anchoringReference
        )
    }

    private static func ineligible(
        receipt: MeshReceipt,
        proof: MeshChainProof,
        reason: MeshDelegatedSpendReceiptIneligibilityReason
    ) throws -> MeshDelegatedSpendReceiptEligibility {
        try MeshDelegatedSpendReceiptEligibility(
            receiptId: receipt.receiptId,
            requestId: receipt.requestId,
            isEligibleForDelegatedLimitDecrement: false,
            reason: reason,
            proof: proof,
            executionKind: proof.executionKind,
            debitAmount: nil,
            asset: proof.asset,
            transactionHash: proof.txHash,
            anchoringReference: proof.anchoringReference
        )
    }

    private static func isTargetOwned(
        _ receipt: MeshReceipt,
        expectedTargetAppId: String?,
        expectedTargetBundleId: String?
    ) throws -> Bool {
        if let expectedTargetAppId, let expectedTargetBundleId {
            do {
                _ = try MeshReceiptOwnershipMapper.assertTargetOwned(
                    receipt,
                    expectedTargetAppId: expectedTargetAppId,
                    expectedTargetBundleId: expectedTargetBundleId
                )
                return true
            } catch MeshKitValidationError.targetIdentityMismatch {
                return false
            }
        }
        return try MeshReceiptOwnershipMapper.ownership(of: receipt).isTargetOwned
    }

    private static func normalizeAsset(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("asset")
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("asset", normalized)
        return normalized
    }
}
