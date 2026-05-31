import Foundation

public struct MeshDelegatedWalletViewModel: Codable, Equatable, Sendable {
    public let provider: String
    public let network: String
    public let chainId: String
    public let walletAddress: String?
    public let asset: String
    public let singlePaymentMax: Decimal
    public let sessionTotalLimit: Decimal
    public let remainingLimit: Decimal
    public let merchantScope: String
    public let capabilityScope: String
    public let targetBundleId: String
    public let consentGrantId: String
    public let policyId: String
    public let policyHash: MeshPayloadHash
    public let expiresAt: String

    public init(
        providerMetadata: MeshAgentWalletProviderMetadata,
        walletAddress: String? = nil,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        targetBundleId: String
    ) throws {
        try providerMetadata.validate()
        try policy.validate()
        self.provider = providerMetadata.provider
        self.network = providerMetadata.network
        self.chainId = providerMetadata.chainId
        self.walletAddress = try walletAddress.map {
            try MeshAgentWalletProviderMetadata.stableValue("walletAddress", $0)
        }
        self.asset = policy.asset
        self.singlePaymentMax = policy.singlePaymentMax
        self.sessionTotalLimit = policy.sessionTotalLimit
        self.remainingLimit = policy.remainingLimit
        self.merchantScope = policy.merchantScope
        self.capabilityScope = policy.capabilityScope
        self.targetBundleId = try MeshAgentWalletProviderMetadata.stableValue("targetBundleId", targetBundleId)
        self.consentGrantId = policy.consentGrantId
        self.policyId = policy.policyId
        self.policyHash = policy.policyHash
        self.expiresAt = policy.expiresAt
        try validate()
    }

    public func validate() throws {
        try MeshAgentWalletProviderMetadata.validateIdentifier("provider", provider)
        try MeshAgentWalletProviderMetadata.validateIdentifier("network", network)
        try MeshAgentWalletProviderMetadata.validateIdentifier("chainId", chainId)
        if let walletAddress {
            try MeshAgentWalletProviderMetadata.validateIdentifier("walletAddress", walletAddress)
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("asset", asset)
        guard singlePaymentMax > 0 else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("singlePaymentMax")
        }
        guard sessionTotalLimit > 0 else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("sessionTotalLimit")
        }
        guard remainingLimit >= 0 else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("remainingLimit")
        }
        guard singlePaymentMax <= sessionTotalLimit,
              remainingLimit <= sessionTotalLimit else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("limits")
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("merchantScope", merchantScope)
        try MeshAgentWalletProviderMetadata.validateIdentifier("capabilityScope", capabilityScope)
        try MeshAgentWalletProviderMetadata.validateIdentifier("targetBundleId", targetBundleId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("consentGrantId", consentGrantId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("policyId", policyId)
        try validateAgentWalletHash("policyHash", policyHash)
        try MeshAgentWalletProviderMetadata.validateIdentifier("expiresAt", expiresAt)
    }

    public var panelSnapshot: MeshDelegatedWalletPanelSnapshot {
        MeshDelegatedWalletPanelSnapshot(wallet: self)
    }

    public func callableAppPresentation(appName: String) -> MeshDelegatedWalletCallableAppPresentation {
        MeshDelegatedWalletCallableAppPresentation(appName: appName, wallet: self)
    }

    public func applyingDailyMartReceiptResult(_ result: [String: String]) throws -> MeshDelegatedWalletViewModel {
        guard Self.isAcceptedPaymentReceipt(result) else {
            return self
        }
        guard let rawAmount = result["total_krw"] ?? result["amount"] else {
            throw MeshKitValidationError.invalidPaymentExecution("amount")
        }
        guard let amount = Decimal(string: rawAmount), amount > 0 else {
            throw MeshKitValidationError.invalidPaymentExecution("amount")
        }
        return try applyingAcceptedPayment(amount: amount)
    }

    public func delegatedSpendingLimit() throws -> MeshAgentWalletDelegatedSpendingLimit {
        try MeshAgentWalletDelegatedSpendingLimit(
            limitAmount: sessionTotalLimit,
            availableLimit: remainingLimit,
            tokenSymbol: asset,
            scope: MeshAgentWalletSpendingScope(
                merchantId: merchantScope,
                targetBundleId: targetBundleId,
                capabilityId: capabilityScope,
                consentGrantId: consentGrantId
            ),
            expiresAt: expiresAt,
            policyMetadata: MeshAgentWalletDelegatedSpendingPolicyMetadata(
                policyId: policyId,
                policyHash: policyHash,
                consentGrantId: consentGrantId,
                merchantScope: merchantScope,
                capabilityScope: capabilityScope,
                expiresAt: expiresAt,
                asset: asset
            )
        )
    }

    public func applyingConfirmedOKRWReceipt(
        _ receipt: MeshReceipt,
        expectedTargetAppId: String? = nil,
        expectedTargetBundleId: String? = nil
    ) throws -> MeshDelegatedWalletViewModel {
        let extracted = try MeshDelegatedSpendConfirmedExecutionAmountExtractor.confirmedOKRWAmount(
            from: receipt,
            spendingLimit: delegatedSpendingLimit(),
            expectedTargetAppId: expectedTargetAppId,
            expectedTargetBundleId: expectedTargetBundleId ?? targetBundleId
        )
        guard let extracted else {
            return self
        }
        guard extracted.policyId == policyId,
              extracted.policyHash == policyHash else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("policyId")
        }
        return try applyingAcceptedPayment(amount: extracted.amount)
    }

    public func dailyMartReceiptDisplayState(
        afterProcessing result: [String: String],
        fallbackAuditId: String? = nil
    ) throws -> MeshDelegatedWalletReceiptDisplayState {
        let processedWallet = try applyingDailyMartReceiptResult(result)
        return MeshDelegatedWalletReceiptDisplayState(
            originalWallet: self,
            processedWallet: processedWallet,
            paymentPresentation: MeshDailyMartReceiptPaymentPresentation(
                receiptResult: result,
                fallbackAuditId: fallbackAuditId
            )
        )
    }

    public func applyingAcceptedPayment(amount: Decimal) throws -> MeshDelegatedWalletViewModel {
        try validate()
        guard amount > 0 else {
            throw MeshKitValidationError.invalidPaymentExecution("amount")
        }
        guard amount <= singlePaymentMax else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("singlePaymentMax")
        }
        guard amount <= remainingLimit else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("remainingLimit")
        }
        let updatedPolicy = try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: policyId,
            policyHash: policyHash,
            consentGrantId: consentGrantId,
            merchantScope: merchantScope,
            capabilityScope: capabilityScope,
            singlePaymentMax: singlePaymentMax,
            sessionTotalLimit: sessionTotalLimit,
            remainingLimit: remainingLimit - amount,
            expiresAt: expiresAt,
            asset: asset,
            recipientAddress: nil
        )
        return try MeshDelegatedWalletViewModel(
            providerMetadata: MeshAgentWalletProviderMetadata(
                provider: provider,
                network: network,
                chainId: chainId
            ),
            walletAddress: walletAddress,
            policy: updatedPolicy,
            targetBundleId: targetBundleId
        )
    }

    private static func isAcceptedPaymentReceipt(_ result: [String: String]) -> Bool {
        MeshHermesChatReceiptEligibilityClassifier.classify(receiptResult: result).isEligible
    }
}

public struct MeshDelegatedWalletReceiptDisplayState: Equatable, Sendable {
    public let originalWallet: MeshDelegatedWalletViewModel
    public let processedWallet: MeshDelegatedWalletViewModel
    public let paymentPresentation: MeshDailyMartReceiptPaymentPresentation
    public let processedPanelSnapshot: MeshDelegatedWalletPanelSnapshot
    public let remainingLimitLineAfterProcessing: String
    public let remainingLimitUnchanged: Bool

    public init(
        originalWallet: MeshDelegatedWalletViewModel,
        processedWallet: MeshDelegatedWalletViewModel,
        paymentPresentation: MeshDailyMartReceiptPaymentPresentation
    ) {
        self.originalWallet = originalWallet
        self.processedWallet = processedWallet
        self.paymentPresentation = paymentPresentation
        self.processedPanelSnapshot = processedWallet.panelSnapshot
        self.remainingLimitLineAfterProcessing = processedPanelSnapshot.remainingLimitLine
        self.remainingLimitUnchanged = originalWallet.remainingLimit == processedWallet.remainingLimit
    }

    public var remainingLimitUnchangedLine: String {
        "Remaining session limit unchanged: \(remainingLimitLineAfterProcessing)"
    }

    public var remainingLimitAfterProcessingLine: String {
        "Remaining session limit: \(remainingLimitLineAfterProcessing)"
    }

    public var renderedLines: [String] {
        paymentPresentation.renderedLines + [
            remainingLimitUnchanged ? remainingLimitUnchangedLine : remainingLimitAfterProcessingLine
        ]
    }
}

public enum MeshHermesChatReceiptEligibilityReason: String, Codable, Equatable, Sendable {
    case eligibleOKRWConfirmedExecution = "eligible_okrw_confirmed_execution"
    case notPaymentExecutionReceipt = "not_payment_execution_receipt"
    case notOKRWReceipt = "not_okrw_receipt"
    case notConfirmedReceipt = "not_confirmed_receipt"
    case missingExecutionReceipt = "missing_execution_receipt"
}

public struct MeshHermesChatReceiptEligibility: Codable, Equatable, Sendable {
    public let isEligible: Bool
    public let reason: MeshHermesChatReceiptEligibilityReason

    public init(isEligible: Bool, reason: MeshHermesChatReceiptEligibilityReason) {
        self.isEligible = isEligible
        self.reason = reason
    }
}

public enum MeshHermesChatReceiptEligibilityClassifier {
    public static func classify(receiptResult: [String: String]) -> MeshHermesChatReceiptEligibility {
        guard receiptResult["chainProofType"] == MeshChainProofType.paymentExecution.rawValue else {
            return MeshHermesChatReceiptEligibility(isEligible: false, reason: .notPaymentExecutionReceipt)
        }

        guard normalizedAsset(receiptResult["asset"]) == "OKRW" else {
            return MeshHermesChatReceiptEligibility(isEligible: false, reason: .notOKRWReceipt)
        }

        let presentationState = receiptResult["presentationState"]
        let nonFinalPresentationStates: Set<String> = [
            MeshChainProofPresentationState.policyDenied.rawValue,
            MeshChainProofPresentationState.submittedNotFinal.rawValue,
            MeshChainProofPresentationState.attemptedFailed.rawValue
        ]
        if let presentationState, nonFinalPresentationStates.contains(presentationState) {
            return MeshHermesChatReceiptEligibility(isEligible: false, reason: .notConfirmedReceipt)
        }

        let status = receiptResult["chainStatus"] ?? receiptResult["status"]
        guard status == MeshChainProofStatus.confirmed.rawValue else {
            return MeshHermesChatReceiptEligibility(isEligible: false, reason: .notConfirmedReceipt)
        }

        guard hasExecutionReceipt(receiptResult) else {
            return MeshHermesChatReceiptEligibility(isEligible: false, reason: .missingExecutionReceipt)
        }

        return MeshHermesChatReceiptEligibility(isEligible: true, reason: .eligibleOKRWConfirmedExecution)
    }

    public static func isEligible(receiptResult: [String: String]) -> Bool {
        classify(receiptResult: receiptResult).isEligible
    }

    private static func normalizedAsset(_ asset: String?) -> String? {
        asset?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func hasExecutionReceipt(_ receiptResult: [String: String]) -> Bool {
        guard let txHash = receiptResult["txHash"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !txHash.isEmpty else {
            return false
        }
        return true
    }
}

public struct MeshDelegatedWalletReceiptDecrementResult: Equatable, Sendable {
    public let wallet: MeshDelegatedWalletViewModel
    public let eligibility: MeshHermesChatReceiptEligibility
    public let didDecrement: Bool
    public let receiptId: String
    public let extractedConfirmedOKRWAmount: MeshDelegatedSpendConfirmedExecutionAmount?

    public init(
        wallet: MeshDelegatedWalletViewModel,
        eligibility: MeshHermesChatReceiptEligibility,
        didDecrement: Bool,
        receiptId: String,
        extractedConfirmedOKRWAmount: MeshDelegatedSpendConfirmedExecutionAmount? = nil
    ) {
        self.wallet = wallet
        self.eligibility = eligibility
        self.didDecrement = didDecrement
        self.receiptId = receiptId
        self.extractedConfirmedOKRWAmount = extractedConfirmedOKRWAmount
    }
}

public struct MeshDelegatedWalletReceiptDecrementHandler: Equatable, Sendable {
    private var appliedEligibleReceiptIds: Set<String>

    public init(appliedEligibleReceiptIds: Set<String> = []) {
        self.appliedEligibleReceiptIds = appliedEligibleReceiptIds
    }

    public var appliedReceiptIds: Set<String> {
        appliedEligibleReceiptIds
    }

    public mutating func apply(
        receiptId: String,
        receiptResult: [String: String],
        to wallet: MeshDelegatedWalletViewModel
    ) throws -> MeshDelegatedWalletReceiptDecrementResult {
        let stableReceiptId = try MeshAgentWalletProviderMetadata.stableValue("receiptId", receiptId)
        let eligibility = MeshHermesChatReceiptEligibilityClassifier.classify(receiptResult: receiptResult)

        guard eligibility.isEligible else {
            return MeshDelegatedWalletReceiptDecrementResult(
                wallet: wallet,
                eligibility: eligibility,
                didDecrement: false,
                receiptId: stableReceiptId
            )
        }

        guard !appliedEligibleReceiptIds.contains(stableReceiptId) else {
            return MeshDelegatedWalletReceiptDecrementResult(
                wallet: wallet,
                eligibility: eligibility,
                didDecrement: false,
                receiptId: stableReceiptId
            )
        }

        let updatedWallet = try wallet.applyingDailyMartReceiptResult(receiptResult)
        appliedEligibleReceiptIds.insert(stableReceiptId)
        return MeshDelegatedWalletReceiptDecrementResult(
            wallet: updatedWallet,
            eligibility: eligibility,
            didDecrement: true,
            receiptId: stableReceiptId
        )
    }

    public mutating func apply(
        receipt: MeshReceipt,
        to wallet: MeshDelegatedWalletViewModel,
        expectedTargetAppId: String? = nil,
        expectedTargetBundleId: String? = nil
    ) throws -> MeshDelegatedWalletReceiptDecrementResult {
        let stableReceiptId = try MeshAgentWalletProviderMetadata.stableValue("receiptId", receipt.receiptId)
        let resultEligibility = MeshHermesChatReceiptEligibilityClassifier.classify(receiptResult: receipt.result)
        let extracted = try MeshDelegatedSpendConfirmedExecutionAmountExtractor.confirmedOKRWAmount(
            from: receipt,
            spendingLimit: wallet.delegatedSpendingLimit(),
            expectedTargetAppId: expectedTargetAppId,
            expectedTargetBundleId: expectedTargetBundleId ?? wallet.targetBundleId
        )

        guard let extracted else {
            let proofEligibility = try? MeshDelegatedSpendReceiptEligibilityEvaluator.evaluate(
                receipt: receipt,
                expectedAsset: MeshDelegatedSpendConfirmedExecutionAmountExtractor.okrwDenomination,
                expectedTargetAppId: expectedTargetAppId,
                expectedTargetBundleId: expectedTargetBundleId ?? wallet.targetBundleId
            )
            let eligibility = Self.receiptEligibility(
                resultEligibility: resultEligibility,
                proofEligibility: proofEligibility
            )
            return MeshDelegatedWalletReceiptDecrementResult(
                wallet: wallet,
                eligibility: eligibility,
                didDecrement: false,
                receiptId: stableReceiptId
            )
        }
        guard extracted.policyId == wallet.policyId,
              extracted.policyHash == wallet.policyHash else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("policyId")
        }
        guard !appliedEligibleReceiptIds.contains(stableReceiptId) else {
            return MeshDelegatedWalletReceiptDecrementResult(
                wallet: wallet,
                eligibility: MeshHermesChatReceiptEligibility(
                    isEligible: true,
                    reason: .eligibleOKRWConfirmedExecution
                ),
                didDecrement: false,
                receiptId: stableReceiptId,
                extractedConfirmedOKRWAmount: extracted
            )
        }

        let updatedWallet = try wallet.applyingAcceptedPayment(amount: extracted.amount)
        appliedEligibleReceiptIds.insert(stableReceiptId)
        return MeshDelegatedWalletReceiptDecrementResult(
            wallet: updatedWallet,
            eligibility: MeshHermesChatReceiptEligibility(
                isEligible: true,
                reason: .eligibleOKRWConfirmedExecution
            ),
            didDecrement: true,
            receiptId: stableReceiptId,
            extractedConfirmedOKRWAmount: extracted
        )
    }

    private static func receiptEligibility(
        resultEligibility: MeshHermesChatReceiptEligibility,
        proofEligibility: MeshDelegatedSpendReceiptEligibility?
    ) -> MeshHermesChatReceiptEligibility {
        guard let reason = proofEligibility?.reason else {
            return resultEligibility
        }
        guard resultEligibility.isEligible || resultEligibility.reason == .missingExecutionReceipt else {
            return resultEligibility
        }
        return MeshHermesChatReceiptEligibility(
            isEligible: false,
            reason: hermesEligibilityReason(for: reason)
        )
    }

    private static func hermesEligibilityReason(
        for reason: MeshDelegatedSpendReceiptIneligibilityReason
    ) -> MeshHermesChatReceiptEligibilityReason {
        switch reason {
        case .unsupportedAsset:
            return .notOKRWReceipt
        case .notConfirmed:
            return .notConfirmedReceipt
        case .notTargetOwned, .unsupportedExecutionKind, .notPaymentExecution:
            return .notPaymentExecutionReceipt
        case .missingTransactionProof:
            return .missingExecutionReceipt
        }
    }
}

public struct MeshDelegatedWalletPanelSnapshot: Equatable, Sendable {
    public static let headerLabel = "AgentOS/OCG delegated wallet"
    public static let providerLabel = "Provider"
    public static let totalSessionLimitLabel = "Total session limit"
    public static let remainingLimitLabel = "Remaining limit"
    public static let remainingSessionLimitSummaryLabel = "Remaining session limit"
    public static let perPaymentMaxLabel = "Per-payment max"
    public static let authorizationLabel = "Authorization"
    public static let assetLabel = "Asset"
    public static let scopeLabel = "Scope"
    public static let scopeStatusLabel = "Scope status"

    public let headerLabel: String
    public let remainingSessionLimitSummaryLine: String
    public let authorizationLine: String
    public let providerLine: String
    public let sessionLimitLine: String
    public let remainingLimitLine: String
    public let perPaymentMaxLine: String
    public let assetLine: String
    public let scopeLine: String
    public let scopeStatusLine: String
    public let scopePresentation: MeshDelegatedWalletScopePresentation
    public let rows: [MeshDelegatedWalletPanelRow]
    public let accessibilityLabel: String

    public init(wallet: MeshDelegatedWalletViewModel) {
        let formatter = MeshDelegatedWalletPolicyFormatter(wallet: wallet)
        let scopePresentation = MeshDelegatedWalletScopePresentation(
            merchantScope: wallet.merchantScope,
            capabilityScope: wallet.capabilityScope,
            consentGrantId: wallet.consentGrantId
        )
        let providerDisplay = Self.providerDisplayName(provider: wallet.provider, network: wallet.network)

        self.headerLabel = Self.headerLabel
        self.providerLine = providerDisplay
        self.sessionLimitLine = formatter.totalSessionLimit
        self.remainingLimitLine = formatter.remainingLimit
        self.remainingSessionLimitSummaryLine = "\(Self.remainingSessionLimitSummaryLabel): \(formatter.remainingLimit)"
        self.perPaymentMaxLine = formatter.perPaymentMax
        self.assetLine = formatter.asset
        self.scopeLine = scopePresentation.label
        self.authorizationLine = "\(formatter.asset) · \(scopePresentation.label)"
        self.scopeStatusLine = scopePresentation.statusLabel
        self.scopePresentation = scopePresentation
        self.rows = [
            MeshDelegatedWalletPanelRow(label: Self.providerLabel, value: providerLine),
            MeshDelegatedWalletPanelRow(label: Self.totalSessionLimitLabel, value: sessionLimitLine),
            MeshDelegatedWalletPanelRow(label: Self.remainingLimitLabel, value: remainingLimitLine),
            MeshDelegatedWalletPanelRow(label: Self.perPaymentMaxLabel, value: perPaymentMaxLine),
            MeshDelegatedWalletPanelRow(label: Self.authorizationLabel, value: authorizationLine),
            MeshDelegatedWalletPanelRow(label: Self.assetLabel, value: assetLine),
            MeshDelegatedWalletPanelRow(label: Self.scopeLabel, value: scopeLine),
            MeshDelegatedWalletPanelRow(label: Self.scopeStatusLabel, value: scopeStatusLine)
        ]
        self.accessibilityLabel = "\(Self.headerLabel) provider \(providerDisplay) total session limit \(formatter.totalSessionLimit) remaining session limit \(formatter.remainingLimit) remaining limit \(formatter.remainingLimit) per payment max \(formatter.perPaymentMax) authorization \(authorizationLine) asset \(formatter.asset) scope \(scopePresentation.label) status \(scopePresentation.statusLabel) raw scope \(scopePresentation.rawScopeLine)"
    }

    private static func providerDisplayName(provider: String, network: String) -> String {
        if provider == "maroo", network == "maroo-testnet" {
            return "maroo testnet"
        }
        return "\(provider) \(network)"
    }
}

public struct MeshDelegatedWalletPanelRow: Equatable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct MeshDelegatedWalletPanelComponent: Equatable, Sendable {
    public let snapshot: MeshDelegatedWalletPanelSnapshot

    public init(snapshot: MeshDelegatedWalletPanelSnapshot) {
        self.snapshot = snapshot
    }

    public init(wallet: MeshDelegatedWalletViewModel) {
        self.init(snapshot: wallet.panelSnapshot)
    }

    public var headerLabel: String {
        snapshot.headerLabel
    }

    public var rows: [MeshDelegatedWalletPanelRow] {
        snapshot.rows
    }

    public var accessibilityLabel: String {
        snapshot.accessibilityLabel
    }

    public var renderedLines: [String] {
        [snapshot.headerLabel] + snapshot.rows.map { "\($0.label): \($0.value)" }
    }

    public var renderedPanelLines: [String] {
        [snapshot.headerLabel, snapshot.remainingSessionLimitSummaryLine] +
            snapshot.rows.map { "\($0.label): \($0.value)" }
    }

    public var rendersAllowedDailyMartEssentialsScope: Bool {
        snapshot.scopePresentation.status == .allowed &&
            snapshot.scopePresentation.merchantScope == DailyMartDelegatedSpendingPolicy.merchantScope &&
            snapshot.scopePresentation.capabilityScope == DailyMartDelegatedSpendingPolicy.capabilityScope &&
            snapshot.scopeLine == "DailyMart grocery.purchase_essentials" &&
            snapshot.scopeStatusLine == "Allowed by saved grant"
    }
}

public struct MeshDelegatedWalletCallableAppPresentation: Equatable, Sendable {
    public let appName: String
    public let subtitle: String
    public let capabilityScope: String
    public let scopePresentation: MeshDelegatedWalletScopePresentation
    public let accessibilityScopeLabel: String

    public init(appName: String, wallet: MeshDelegatedWalletViewModel) {
        let formatter = MeshDelegatedWalletPolicyFormatter(wallet: wallet)
        let scopePresentation = MeshDelegatedWalletScopePresentation(
            merchantScope: wallet.merchantScope,
            capabilityScope: wallet.capabilityScope,
            consentGrantId: wallet.consentGrantId
        )

        self.appName = appName
        let providerDisplay = wallet.provider == "maroo" && wallet.network == "maroo-testnet"
            ? "maroo testnet"
            : wallet.provider
        self.subtitle = "\(providerDisplay) \(formatter.asset) · \(formatter.remainingLimit) limit · \(wallet.capabilityScope)"
        self.capabilityScope = wallet.capabilityScope
        self.scopePresentation = scopePresentation
        self.accessibilityScopeLabel = "\(appName) \(scopePresentation.label) \(wallet.capabilityScope)"
    }

    public func matchesPanelScope(_ snapshot: MeshDelegatedWalletPanelSnapshot) -> Bool {
        capabilityScope == snapshot.scopePresentation.capabilityScope &&
            scopePresentation == snapshot.scopePresentation
    }
}

public enum MeshDelegatedWalletScopeStatus: String, Codable, Equatable, Sendable {
    case allowed
    case unavailable
}

public struct MeshDelegatedWalletScopePresentation: Codable, Equatable, Sendable {
    public let merchantScope: String
    public let capabilityScope: String
    public let consentGrantId: String
    public let label: String
    public let status: MeshDelegatedWalletScopeStatus
    public let statusLabel: String
    public let rawScopeLine: String

    public init(
        merchantScope: String,
        capabilityScope: String,
        consentGrantId: String
    ) {
        self.merchantScope = merchantScope
        self.capabilityScope = capabilityScope
        self.consentGrantId = consentGrantId
        self.rawScopeLine = "\(merchantScope) · \(capabilityScope)"

        if merchantScope == DailyMartDelegatedSpendingPolicy.merchantScope,
           capabilityScope == DailyMartDelegatedSpendingPolicy.capabilityScope,
           consentGrantId == DailyMartDelegatedSpendingPolicy.consentGrantId {
            self.label = "DailyMart grocery.purchase_essentials"
            self.status = .allowed
            self.statusLabel = "Allowed by saved grant"
        } else {
            self.label = capabilityScope
            self.status = .unavailable
            self.statusLabel = "Not allowed by saved grant"
        }
    }
}

public struct MeshDelegatedWalletPolicyFormatter: Equatable, Sendable {
    public let totalSessionLimit: String
    public let remainingLimit: String
    public let perPaymentMax: String
    public let asset: String

    public init(wallet: MeshDelegatedWalletViewModel) {
        self.init(
            sessionTotalLimit: wallet.sessionTotalLimit,
            remainingLimit: wallet.remainingLimit,
            singlePaymentMax: wallet.singlePaymentMax,
            asset: wallet.asset
        )
    }

    public init(policy: MeshAgentWalletDelegatedSpendingPolicy) throws {
        try policy.validate()
        self.init(
            sessionTotalLimit: policy.sessionTotalLimit,
            remainingLimit: policy.remainingLimit,
            singlePaymentMax: policy.singlePaymentMax,
            asset: policy.asset
        )
    }

    private init(
        sessionTotalLimit: Decimal,
        remainingLimit: Decimal,
        singlePaymentMax: Decimal,
        asset: String
    ) {
        self.totalSessionLimit = Self.amountLine(sessionTotalLimit, asset: asset)
        self.remainingLimit = Self.amountLine(remainingLimit, asset: asset)
        self.perPaymentMax = Self.amountLine(singlePaymentMax, asset: asset)
        self.asset = asset
    }

    private static func amountLine(_ decimal: Decimal, asset: String) -> String {
        "\(NSDecimalNumber(decimal: decimal).stringValue) \(asset)"
    }
}

public enum HermesChatDelegatedWalletViewModels {
    public static let dailyMartTargetBundleId = "ai.meshkit.sample.dailymart"
    public static let demoWalletAddress = "maroo1dailyMartAgentWallet"

    public static func viewModel(
        providerMetadata: MeshAgentWalletProviderMetadata,
        walletAddress: String? = nil,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        targetBundleId: String
    ) throws -> MeshDelegatedWalletViewModel {
        try MeshDelegatedWalletViewModel(
            providerMetadata: providerMetadata,
            walletAddress: walletAddress,
            policy: policy,
            targetBundleId: targetBundleId
        )
    }

    public static func marooTestnetOKRWDailyMartGrocerySession(
        walletAddress: String = demoWalletAddress,
        expiresAt: String = "2026-12-31T23:59:59Z"
    ) throws -> MeshDelegatedWalletViewModel {
        try viewModel(
            providerMetadata: MeshAgentWalletProviderMetadata(
                chainProviderIdentity: MeshMarooTestnetChainProvider().identity,
                adapterId: "maroo-testnet-agent-wallet-adapter"
            ),
            walletAddress: walletAddress,
            policy: DailyMartDelegatedSpendingPolicy.expectedPolicy(expiresAt: expiresAt),
            targetBundleId: dailyMartTargetBundleId
        )
    }
}

public enum MeshDailyMartReceiptPaymentPresentationKind: String, Codable, Equatable, Sendable {
    case paidComplete = "paid_complete"
    case submittedNotFinal = "submitted_not_final"
    case attemptedFailed = "attempted_failed"
    case policyDenied = "policy_denied"
}

public struct MeshDailyMartExternalChainEvidencePresentation: Codable, Equatable, Sendable {
    public let exitCondition: String
    public let blockerType: String?
    public let operation: String?
    public let observedAt: String?
    public let endpoint: String?
    public let message: String?

    public init?(receiptResult: [String: String]) {
        guard receiptResult[MeshReceiptChainProofSerializer.externalChainExitConditionResultKey] == MeshExternalChainBlockerEvidence.exitCondition else {
            return nil
        }
        self.exitCondition = MeshExternalChainBlockerEvidence.exitCondition
        self.blockerType = receiptResult[MeshReceiptChainProofSerializer.externalChainBlockerTypeResultKey]
        self.operation = receiptResult[MeshReceiptChainProofSerializer.externalChainOperationResultKey]
        self.observedAt = receiptResult[MeshReceiptChainProofSerializer.externalChainObservedAtResultKey]
        self.endpoint = receiptResult[MeshReceiptChainProofSerializer.externalChainEndpointResultKey]
        self.message = receiptResult[MeshReceiptChainProofSerializer.externalChainMessageResultKey]
    }

    public var summaryLine: String {
        [exitCondition, blockerType, operation].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ")
    }

    public var detailLine: String? {
        [endpoint, observedAt, message].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ").nilIfEmpty
    }
}

public struct MeshDailyMartReceiptPaymentPresentation: Codable, Equatable, Sendable {
    public let kind: MeshDailyMartReceiptPaymentPresentationKind
    public let title: String
    public let body: String
    public let auditLine: String
    public let paymentStateLine: String
    public let pendingSubmittedAtLine: String?
    public let pendingAnchoringReferenceLine: String?
    public let errorCodeLine: String?
    public let errorMessageLine: String?
    public let explorerURL: URL?
    public let explorerLinkTitle: String?
    public let isPaymentAttempted: Bool
    public let isPaid: Bool
    public let isComplete: Bool
    public let isPaidComplete: Bool
    public let externalChainEvidence: MeshDailyMartExternalChainEvidencePresentation?

    public init(receiptResult: [String: String], fallbackAuditId: String? = nil) {
        let presentationState = receiptResult["presentationState"]
        let chainProofType = receiptResult["chainProofType"]
        let chainStatus = receiptResult["chainStatus"] ?? receiptResult["status"]
        let legacyStatus = receiptResult["status"]
        let evidence = MeshDailyMartExternalChainEvidencePresentation(receiptResult: receiptResult)
        let anchoringReference = receiptResult["anchoringReference"] ?? fallbackAuditId ?? "unavailable"
        let submittedAt = receiptResult["submittedAt"] ?? "unavailable"
        let errorCode = receiptResult["errorCode"] ?? "payment_execution_failed"
        let errorMessage = receiptResult["errorMessage"] ?? "DailyMart could not complete the OKRW execution."
        let isConfirmedPaymentExecution = chainProofType == MeshChainProofType.paymentExecution.rawValue &&
            chainStatus == MeshChainProofStatus.confirmed.rawValue
        let isLegacyPaidReceiptStatus = ["purchased", "complete", "completed"].contains(legacyStatus)
        let explorerURL = Self.validConfirmedExplorerURL(
            receiptResult["explorerUrl"],
            isConfirmedPaymentExecution: isConfirmedPaymentExecution
        )

        self.externalChainEvidence = evidence
        self.explorerURL = explorerURL
        self.explorerLinkTitle = explorerURL.map { "Open maroo explorer: \($0.absoluteString)" }

        if presentationState == MeshChainProofPresentationState.policyDenied.rawValue {
            self.kind = .policyDenied
            self.title = "DailyMart returned a target-signed policy-denied receipt"
            self.body = "\(errorCode) · \(errorMessage)"
            self.auditLine = "grocery.purchase_essentials.policy_denied · errorCode=\(errorCode) · errorMessage=\(errorMessage) · no txHash."
            self.paymentStateLine = "Payment state: not attempted · unpaid · incomplete"
            self.pendingSubmittedAtLine = nil
            self.pendingAnchoringReferenceLine = nil
            self.errorCodeLine = nil
            self.errorMessageLine = nil
            self.isPaymentAttempted = false
            self.isPaid = false
            self.isComplete = false
            self.isPaidComplete = false
        } else if presentationState == MeshChainProofPresentationState.submittedNotFinal.rawValue ||
                    chainStatus == MeshChainProofStatus.pending.rawValue {
            self.kind = .submittedNotFinal
            self.title = "DailyMart returned a target-signed pending receipt"
            self.body = "Submitted, not final · anchoring reference \(anchoringReference) · no paid order until maroo confirms"
            self.auditLine = [
                "grocery.purchase_essentials.submitted_not_final",
                "anchoringReference=\(anchoringReference)",
                evidence?.summaryLine ?? "no BlockedByExternalChain evidence",
                "no txHash accepted as confirmed fallback"
            ].joined(separator: " · ")
            self.paymentStateLine = "Payment state: attempted · unpaid · incomplete"
            self.pendingSubmittedAtLine = "submittedAt=\(submittedAt)"
            self.pendingAnchoringReferenceLine = "anchoringReference=\(anchoringReference)"
            self.errorCodeLine = nil
            self.errorMessageLine = nil
            self.isPaymentAttempted = true
            self.isPaid = false
            self.isComplete = false
            self.isPaidComplete = false
        } else if presentationState == MeshChainProofPresentationState.attemptedFailed.rawValue ||
                    chainStatus == MeshChainProofStatus.failed.rawValue {
            self.kind = .attemptedFailed
            self.title = "DailyMart returned a target-signed failed receipt"
            self.body = "Attempted, not paid · \(errorCode) · \(errorMessage)"
            self.auditLine = [
                "grocery.purchase_essentials.attempted_failed",
                "errorCode=\(errorCode)",
                "errorMessage=\(errorMessage)",
                evidence?.summaryLine ?? "no BlockedByExternalChain evidence",
                "no txHash accepted as confirmed fallback"
            ].joined(separator: " · ")
            self.paymentStateLine = "Payment state: attempted · unpaid · incomplete"
            self.pendingSubmittedAtLine = nil
            self.pendingAnchoringReferenceLine = nil
            self.errorCodeLine = "errorCode: \(errorCode)"
            self.errorMessageLine = "errorMessage: \(errorMessage)"
            self.isPaymentAttempted = true
            self.isPaid = false
            self.isComplete = false
            self.isPaidComplete = false
        } else if presentationState == MeshChainProofPresentationState.paidComplete.rawValue ||
                    isConfirmedPaymentExecution ||
                    isLegacyPaidReceiptStatus {
            let orderId = receiptResult["order_id"] ?? "DM-2026-0509-001"
            let total = receiptResult["total_krw"] ?? receiptResult["amount"] ?? "100"
            let txHash = receiptResult["txHash"]
            let txHashLine = txHash.map { " · txHash=\($0)" } ?? ""
            let explorerLine = explorerURL.map { " · explorerUrl=\($0.absoluteString)" } ?? ""
            self.kind = .paidComplete
            self.title = "DailyMart background checkout complete"
            self.body = "Order \(orderId) · Total ₩\(total) · Delivery 7-9 PM\(txHashLine)\(explorerLine)"
            self.auditLine = "grocery.purchase_essentials.paid_complete · requestId/payloadHash/signature verified\(txHashLine)\(explorerLine)"
            self.paymentStateLine = "Payment state: attempted · paid · complete"
            self.pendingSubmittedAtLine = nil
            self.pendingAnchoringReferenceLine = nil
            self.errorCodeLine = nil
            self.errorMessageLine = nil
            self.isPaymentAttempted = true
            self.isPaid = true
            self.isComplete = true
            self.isPaidComplete = true
        } else {
            self.kind = .attemptedFailed
            self.title = "DailyMart returned a target-signed failed receipt"
            self.body = "Attempted, not paid · \(errorCode) · \(errorMessage)"
            self.auditLine = [
                "grocery.purchase_essentials.attempted_failed",
                "errorCode=\(errorCode)",
                "errorMessage=\(errorMessage)",
                "unconfirmed receipt status",
                "no txHash accepted as confirmed fallback"
            ].joined(separator: " · ")
            self.paymentStateLine = "Payment state: attempted · unpaid · incomplete"
            self.pendingSubmittedAtLine = nil
            self.pendingAnchoringReferenceLine = nil
            self.errorCodeLine = "errorCode: \(errorCode)"
            self.errorMessageLine = "errorMessage: \(errorMessage)"
            self.isPaymentAttempted = true
            self.isPaid = false
            self.isComplete = false
            self.isPaidComplete = false
        }
    }

    public var renderedLines: [String] {
        var lines = [title, body, paymentStateLine, auditLine]
        if let pendingSubmittedAtLine {
            lines.append(pendingSubmittedAtLine)
        }
        if let pendingAnchoringReferenceLine {
            lines.append(pendingAnchoringReferenceLine)
        }
        if let errorCodeLine {
            lines.append(errorCodeLine)
        }
        if let errorMessageLine {
            lines.append(errorMessageLine)
        }
        if let evidenceDetail = externalChainEvidence?.detailLine {
            lines.append(evidenceDetail)
        }
        if let explorerLinkTitle {
            lines.append(explorerLinkTitle)
        }
        return lines
    }

    private static func validConfirmedExplorerURL(
        _ rawValue: String?,
        isConfirmedPaymentExecution: Bool
    ) -> URL? {
        guard isConfirmedPaymentExecution,
              let rawValue,
              let components = URLComponents(string: rawValue),
              components.scheme == "https",
              components.host?.lowercased() == "explorer-testnet.maroo.io",
              components.path.hasPrefix("/tx/"),
              components.path.count > "/tx/".count,
              let url = components.url else {
            return nil
        }
        return url
    }
}

public enum MeshHermesChatDailyMartOrderStateKind: String, Codable, Equatable, Sendable {
    case paidComplete = "paid_complete"
    case submittedNotFinal = "submitted_not_final"
    case attemptedFailed = "attempted_failed"
    case policyDenied = "policy_denied"
}

public struct MeshHermesChatDailyMartOrderStateRecord: Codable, Equatable, Sendable {
    public let kind: MeshHermesChatDailyMartOrderStateKind
    public let lastAction: String
    public let persistsPaidStatus: Bool
    public let persistsCompleteStatus: Bool

    public init(
        kind: MeshHermesChatDailyMartOrderStateKind,
        lastAction: String,
        persistsPaidStatus: Bool,
        persistsCompleteStatus: Bool
    ) {
        self.kind = kind
        self.lastAction = lastAction
        self.persistsPaidStatus = persistsPaidStatus
        self.persistsCompleteStatus = persistsCompleteStatus
    }
}

public enum MeshHermesChatDailyMartOrderStateRecorder {
    public static func record(
        receiptResult: [String: String],
        callbackStatus: String?
    ) -> MeshHermesChatDailyMartOrderStateRecord {
        let presentation = MeshDailyMartReceiptPaymentPresentation(receiptResult: receiptResult)

        switch presentation.kind {
        case .submittedNotFinal:
            return MeshHermesChatDailyMartOrderStateRecord(
                kind: .submittedNotFinal,
                lastAction: "DailyMart OKRW execution submitted",
                persistsPaidStatus: false,
                persistsCompleteStatus: false
            )
        case .attemptedFailed:
            return MeshHermesChatDailyMartOrderStateRecord(
                kind: .attemptedFailed,
                lastAction: "DailyMart OKRW execution failed",
                persistsPaidStatus: false,
                persistsCompleteStatus: false
            )
        case .policyDenied:
            return MeshHermesChatDailyMartOrderStateRecord(
                kind: .policyDenied,
                lastAction: "DailyMart policy denied",
                persistsPaidStatus: false,
                persistsCompleteStatus: false
            )
        case .paidComplete:
            guard isConfirmedPaidReceipt(receiptResult, callbackStatus: callbackStatus) else {
                return MeshHermesChatDailyMartOrderStateRecord(
                    kind: .submittedNotFinal,
                    lastAction: "DailyMart OKRW execution submitted",
                    persistsPaidStatus: false,
                    persistsCompleteStatus: false
                )
            }
            return MeshHermesChatDailyMartOrderStateRecord(
                kind: .paidComplete,
                lastAction: "DailyMart order confirmed",
                persistsPaidStatus: true,
                persistsCompleteStatus: true
            )
        }
    }

    private static func isConfirmedPaidReceipt(
        _ receiptResult: [String: String],
        callbackStatus: String?
    ) -> Bool {
        let chainStatus = receiptResult["chainStatus"] ?? receiptResult["status"]
        if chainStatus == MeshChainProofStatus.pending.rawValue {
            return false
        }
        if receiptResult["presentationState"] == MeshChainProofPresentationState.submittedNotFinal.rawValue {
            return false
        }
        if receiptResult["chainProofType"] == MeshChainProofType.paymentExecution.rawValue {
            return chainStatus == MeshChainProofStatus.confirmed.rawValue &&
                MeshHermesChatReceiptEligibilityClassifier.isEligible(receiptResult: receiptResult)
        }
        guard let normalizedCallbackStatus = callbackStatus?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return ["purchased", "complete", "completed", "confirmed"].contains(normalizedCallbackStatus)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
