import Foundation

public struct MeshAgentWalletProviderMetadata: Codable, Equatable, Sendable {
    public let provider: String
    public let network: String
    public let chainId: String
    public let rpcEndpoint: URL?
    public let explorerBaseUrl: URL?
    public let adapterId: String?

    public init(
        provider: String,
        network: String,
        chainId: String,
        rpcEndpoint: URL? = nil,
        explorerBaseUrl: URL? = nil,
        adapterId: String? = nil
    ) throws {
        self.provider = try Self.normalizedIdentifier("provider", provider)
        self.network = try Self.normalizedIdentifier("network", network)
        self.chainId = try Self.normalizedIdentifier("chainId", chainId)
        self.rpcEndpoint = try rpcEndpoint.map { try Self.normalizedNetworkURL("rpcEndpoint", $0) }
        self.explorerBaseUrl = try explorerBaseUrl.map { try Self.normalizedNetworkURL("explorerBaseUrl", $0) }
        self.adapterId = try adapterId.map { try Self.normalizedIdentifier("adapterId", $0) }
        try validate()
    }

    public init(chainProviderIdentity: MeshChainProviderIdentity, adapterId: String? = nil) throws {
        try self.init(
            provider: chainProviderIdentity.provider,
            network: chainProviderIdentity.network,
            chainId: chainProviderIdentity.chainId,
            rpcEndpoint: chainProviderIdentity.rpcEndpoint,
            explorerBaseUrl: chainProviderIdentity.explorerBaseUrl,
            adapterId: adapterId
        )
    }

    public func validate() throws {
        try Self.validateIdentifier("provider", provider)
        try Self.validateIdentifier("network", network)
        try Self.validateIdentifier("chainId", chainId)
        if let rpcEndpoint {
            try Self.validateNetworkURL("rpcEndpoint", rpcEndpoint)
        }
        if let explorerBaseUrl {
            try Self.validateNetworkURL("explorerBaseUrl", explorerBaseUrl)
        }
        if let adapterId {
            try Self.validateIdentifier("adapterId", adapterId)
        }
    }

    fileprivate static func normalizedIdentifier(_ field: String, _ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(field)
        }
        try validateIdentifier(field, normalized)
        return normalized
    }

    static func stableValue(_ field: String, _ value: String) throws -> String {
        let stable = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stable.isEmpty, stable == value else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(field)
        }
        try validateIdentifier(field, stable)
        return stable
    }

    static func validateIdentifier(_ field: String, _ value: String) throws {
        guard !value.isEmpty else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(field)
        }
        guard value.rangeOfCharacter(from: CharacterSet.newlines.union(.controlCharacters)) == nil else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(field)
        }
    }

    fileprivate static func normalizedNetworkURL(_ field: String, _ url: URL) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(field)
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.path == "/" {
            components.path = ""
        }
        guard let normalized = components.url else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(field)
        }
        try validateNetworkURL(field, normalized)
        return normalized
    }

    fileprivate static func validateNetworkURL(_ field: String, _ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(field)
        }
        guard let host = url.host, !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(field)
        }
    }
}

public enum MeshAgentWalletCapability: String, Codable, CaseIterable, Comparable, Sendable {
    case reportWalletAddress
    case validatePolicy
    case reportDelegatedSpendingLimit
    case exposeSigningBoundary
    case signMCPRequest
    case signRequestAnchorPayload
    case checkExecutionAuthorization
    case signExecutionAuthorizationPayload
    case authorizeExecution
    case submitTransaction
    case accountForPendingSpendReservation
    case accountForConfirmedSpend

    public static func < (lhs: MeshAgentWalletCapability, rhs: MeshAgentWalletCapability) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum MeshAgentWalletSigningBoundary: String, Codable, Equatable, Sendable {
    case localSignature
    case providerSubmission
    case externalWalletApp
}

public struct MeshAgentWalletSpendingScope: Codable, Equatable, Sendable {
    public let merchantId: String
    public let targetBundleId: String
    public let capabilityId: String
    public let consentGrantId: String?

    public init(
        merchantId: String,
        targetBundleId: String,
        capabilityId: String,
        consentGrantId: String? = nil
    ) throws {
        self.merchantId = try MeshAgentWalletProviderMetadata.stableValue("merchantId", merchantId)
        self.targetBundleId = try MeshAgentWalletProviderMetadata.stableValue("targetBundleId", targetBundleId)
        self.capabilityId = try MeshAgentWalletProviderMetadata.stableValue("capabilityId", capabilityId)
        self.consentGrantId = try consentGrantId.map { try MeshAgentWalletProviderMetadata.stableValue("consentGrantId", $0) }
        try validate()
    }

    public func validate() throws {
        try MeshAgentWalletProviderMetadata.validateIdentifier("merchantId", merchantId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("targetBundleId", targetBundleId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("capabilityId", capabilityId)
        if let consentGrantId {
            try MeshAgentWalletProviderMetadata.validateIdentifier("consentGrantId", consentGrantId)
        }
    }
}

public struct MeshAgentWalletDelegatedSpendingLimit: Codable, Equatable, Sendable {
    public let limitAmount: Decimal
    public let availableLimit: Decimal
    public let currencyCode: String?
    public let tokenSymbol: String?
    public let scope: MeshAgentWalletSpendingScope
    public let expiresAt: String
    public let policyMetadata: MeshAgentWalletDelegatedSpendingPolicyMetadata?

    public init(
        limitAmount: Decimal,
        availableLimit: Decimal? = nil,
        currencyCode: String? = nil,
        tokenSymbol: String? = nil,
        scope: MeshAgentWalletSpendingScope,
        expiresAt: String,
        policyMetadata: MeshAgentWalletDelegatedSpendingPolicyMetadata? = nil
    ) throws {
        self.limitAmount = limitAmount
        self.availableLimit = availableLimit ?? limitAmount
        self.currencyCode = try currencyCode.map { try Self.normalizedAssetIdentifier("currencyCode", $0) }
        self.tokenSymbol = try tokenSymbol.map { try Self.normalizedAssetIdentifier("tokenSymbol", $0) }
        self.scope = scope
        self.expiresAt = try MeshAgentWalletProviderMetadata.stableValue("expiresAt", expiresAt)
        self.policyMetadata = policyMetadata
        try validate()
    }

    public func validate() throws {
        guard limitAmount > 0 else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("limitAmount")
        }
        guard availableLimit >= 0 else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("availableLimit")
        }
        guard availableLimit <= limitAmount else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("availableLimit")
        }
        guard currencyCode != nil || tokenSymbol != nil else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("currencyCode")
        }
        if let currencyCode {
            try MeshAgentWalletProviderMetadata.validateIdentifier("currencyCode", currencyCode)
        }
        if let tokenSymbol {
            try MeshAgentWalletProviderMetadata.validateIdentifier("tokenSymbol", tokenSymbol)
        }
        try scope.validate()
        try MeshAgentWalletProviderMetadata.validateIdentifier("expiresAt", expiresAt)
        if let policyMetadata {
            try policyMetadata.validate()
            guard policyMetadata.consentGrantId == scope.consentGrantId else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("policyMetadata.consentGrantId")
            }
            guard policyMetadata.merchantScope == scope.merchantId else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("policyMetadata.merchantScope")
            }
            guard policyMetadata.capabilityScope == scope.capabilityId else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("policyMetadata.capabilityScope")
            }
            guard policyMetadata.expiresAt == expiresAt else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("policyMetadata.expiresAt")
            }
        }
    }

    private static func normalizedAssetIdentifier(_ field: String, _ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(field)
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier(field, normalized)
        return normalized
    }
}

public struct MeshAgentWalletDelegatedSpendingPolicyMetadata: Codable, Equatable, Sendable {
    public let policyId: String
    public let policyHash: MeshPayloadHash
    public let consentGrantId: String
    public let merchantScope: String
    public let capabilityScope: String
    public let startsAt: String?
    public let expiresAt: String
    public let asset: String
    public let recipientAddress: String?

    public init(
        policyId: String,
        policyHash: MeshPayloadHash,
        consentGrantId: String,
        merchantScope: String,
        capabilityScope: String,
        startsAt: String? = nil,
        expiresAt: String,
        asset: String,
        recipientAddress: String? = nil
    ) throws {
        self.policyId = try MeshAgentWalletProviderMetadata.stableValue("policyId", policyId)
        self.policyHash = policyHash
        self.consentGrantId = try MeshAgentWalletProviderMetadata.stableValue("consentGrantId", consentGrantId)
        self.merchantScope = try MeshAgentWalletProviderMetadata.stableValue("merchantScope", merchantScope)
        self.capabilityScope = try MeshAgentWalletProviderMetadata.stableValue("capabilityScope", capabilityScope)
        self.startsAt = try startsAt.map { try MeshAgentWalletProviderMetadata.stableValue("startsAt", $0) }
        self.expiresAt = try MeshAgentWalletProviderMetadata.stableValue("expiresAt", expiresAt)
        self.asset = try Self.normalizedAssetIdentifier("asset", asset)
        self.recipientAddress = try recipientAddress.map { try MeshAgentWalletProviderMetadata.stableValue("recipientAddress", $0) }
        try validate()
    }

    public init(policy: MeshAgentWalletDelegatedSpendingPolicy) throws {
        try self.init(
            policyId: policy.policyId,
            policyHash: policy.policyHash,
            consentGrantId: policy.consentGrantId,
            merchantScope: policy.merchantScope,
            capabilityScope: policy.capabilityScope,
            startsAt: policy.startsAt,
            expiresAt: policy.expiresAt,
            asset: policy.asset,
            recipientAddress: policy.recipientAddress
        )
    }

    public func validate() throws {
        try MeshAgentWalletProviderMetadata.validateIdentifier("policyId", policyId)
        try validateAgentWalletHash("policyHash", policyHash)
        try MeshAgentWalletProviderMetadata.validateIdentifier("consentGrantId", consentGrantId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("merchantScope", merchantScope)
        try MeshAgentWalletProviderMetadata.validateIdentifier("capabilityScope", capabilityScope)
        if let startsAt {
            try MeshAgentWalletProviderMetadata.validateIdentifier("startsAt", startsAt)
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("expiresAt", expiresAt)
        try MeshAgentWalletDelegatedSpendingPolicyExpiryWindowValidator(
            startsAt: startsAt,
            expiresAt: expiresAt
        ).validateWindowDefinition()
        try MeshAgentWalletProviderMetadata.validateIdentifier("asset", asset)
        if let recipientAddress {
            try MeshAgentWalletProviderMetadata.validateIdentifier("recipientAddress", recipientAddress)
        }
    }

    private static func normalizedAssetIdentifier(_ field: String, _ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(field)
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier(field, normalized)
        return normalized
    }
}

public struct MeshAgentWalletDelegatedSpendingPolicy: Codable, Equatable, Sendable {
    public let policyId: String
    public let policyHash: MeshPayloadHash
    public let consentGrantId: String
    public let merchantScope: String
    public let capabilityScope: String
    public let singlePaymentMax: Decimal
    public let sessionTotalLimit: Decimal
    public let remainingLimit: Decimal
    public let startsAt: String?
    public let expiresAt: String
    public let asset: String
    public let recipientAddress: String?

    public init(
        policyId: String,
        policyHash: MeshPayloadHash,
        consentGrantId: String,
        merchantScope: String,
        capabilityScope: String,
        singlePaymentMax: Decimal,
        sessionTotalLimit: Decimal,
        remainingLimit: Decimal,
        startsAt: String? = nil,
        expiresAt: String,
        asset: String,
        recipientAddress: String? = nil
    ) throws {
        self.policyId = try MeshAgentWalletProviderMetadata.stableValue("policyId", policyId)
        self.policyHash = policyHash
        self.consentGrantId = try MeshAgentWalletProviderMetadata.stableValue("consentGrantId", consentGrantId)
        self.merchantScope = try MeshAgentWalletProviderMetadata.stableValue("merchantScope", merchantScope)
        self.capabilityScope = try MeshAgentWalletProviderMetadata.stableValue("capabilityScope", capabilityScope)
        self.singlePaymentMax = singlePaymentMax
        self.sessionTotalLimit = sessionTotalLimit
        self.remainingLimit = remainingLimit
        self.startsAt = try startsAt.map { try MeshAgentWalletProviderMetadata.stableValue("startsAt", $0) }
        self.expiresAt = try MeshAgentWalletProviderMetadata.stableValue("expiresAt", expiresAt)
        self.asset = try Self.normalizedAssetIdentifier("asset", asset)
        self.recipientAddress = try recipientAddress.map { try MeshAgentWalletProviderMetadata.stableValue("recipientAddress", $0) }
        try validate()
    }

    public func validate() throws {
        try MeshAgentWalletProviderMetadata.validateIdentifier("policyId", policyId)
        try validateAgentWalletHash("policyHash", policyHash)
        try MeshAgentWalletProviderMetadata.validateIdentifier("consentGrantId", consentGrantId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("merchantScope", merchantScope)
        try MeshAgentWalletProviderMetadata.validateIdentifier("capabilityScope", capabilityScope)
        guard singlePaymentMax > 0 else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("singlePaymentMax")
        }
        guard sessionTotalLimit > 0 else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("sessionTotalLimit")
        }
        guard remainingLimit >= 0 else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("remainingLimit")
        }
        guard singlePaymentMax <= sessionTotalLimit else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("singlePaymentMax")
        }
        guard remainingLimit <= sessionTotalLimit else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("remainingLimit")
        }
        if let startsAt {
            try MeshAgentWalletProviderMetadata.validateIdentifier("startsAt", startsAt)
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("expiresAt", expiresAt)
        try MeshAgentWalletDelegatedSpendingPolicyExpiryWindowValidator(
            startsAt: startsAt,
            expiresAt: expiresAt
        ).validateWindowDefinition()
        try MeshAgentWalletProviderMetadata.validateIdentifier("asset", asset)
        if let recipientAddress {
            try MeshAgentWalletProviderMetadata.validateIdentifier("recipientAddress", recipientAddress)
        }
    }

    public func validateSessionRemainingBalanceEligibility(paymentAmount: Decimal) throws {
        try validate()
        guard paymentAmount > 0 else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("amount")
        }
        guard paymentAmount <= remainingLimit else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("remainingLimit")
        }
    }

    public func isSessionRemainingBalanceEligible(paymentAmount: Decimal) throws -> Bool {
        do {
            try validateSessionRemainingBalanceEligibility(paymentAmount: paymentAmount)
            return true
        } catch MeshKitValidationError.invalidAgentWalletIdentity(let field) where field == "remainingLimit" {
            return false
        }
    }

    public func validatePolicyInput(
        amount: Decimal,
        merchantScope: String,
        capabilityScope: String,
        consentGrantId: String,
        asset: String,
        recipientAddress: String? = nil,
        requestedAt: String? = nil
    ) throws {
        try validate()
        guard amount > 0 else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("amount")
        }
        guard amount <= singlePaymentMax else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("singlePaymentMax")
        }
        try validateSessionRemainingBalanceEligibility(paymentAmount: amount)
        guard self.merchantScope == merchantScope else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("merchantScope")
        }
        guard self.capabilityScope == capabilityScope else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("capabilityScope")
        }
        guard self.consentGrantId == consentGrantId else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("consentGrantId")
        }
        guard self.asset == (try Self.normalizedAssetIdentifier("asset", asset)) else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("asset")
        }
        if let selfRecipientAddress = self.recipientAddress {
            guard selfRecipientAddress == recipientAddress else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("recipientAddress")
            }
        }
        if let requestedAt {
            try MeshAgentWalletDelegatedSpendingPolicyExpiryWindowValidator(
                startsAt: startsAt,
                expiresAt: expiresAt
            ).validateActive(at: requestedAt)
        }
    }

    public func evaluateExecutionRequest(
        _ request: MeshAgentWalletExecutionRequest,
        requestedAt: String
    ) throws -> MeshAgentWalletPolicyEvaluationResult {
        do {
            try validatePolicyInput(
                amount: request.amount,
                merchantScope: request.scope.merchantId,
                capabilityScope: request.scope.capabilityId,
                consentGrantId: request.scope.consentGrantId ?? "",
                asset: request.tokenSymbol ?? request.currencyCode ?? "",
                recipientAddress: request.recipientAddress,
                requestedAt: requestedAt
            )
            return try MeshAgentWalletPolicyEvaluationResult(
                policyId: policyId,
                executionId: request.executionId,
                status: .allowed,
                approvedAmount: request.amount,
                reason: nil,
                evaluatedAt: requestedAt
            )
        } catch MeshKitValidationError.invalidAgentWalletIdentity(let field) {
            return try MeshAgentWalletPolicyEvaluationResult(
                policyId: policyId,
                executionId: request.executionId,
                status: .denied,
                approvedAmount: nil,
                reason: Self.denialReason(forPolicyViolationField: field),
                evaluatedAt: requestedAt
            )
        }
    }

    public func validateExecutionRequest(
        _ request: MeshAgentWalletExecutionRequest,
        requestedAt: String
    ) throws {
        try validatePolicyInput(
            amount: request.amount,
            merchantScope: request.scope.merchantId,
            capabilityScope: request.scope.capabilityId,
            consentGrantId: request.scope.consentGrantId ?? "",
            asset: request.tokenSymbol ?? request.currencyCode ?? "",
            recipientAddress: request.recipientAddress,
            requestedAt: requestedAt
        )
        guard request.policyId == policyId,
              request.policyHash == policyHash else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("policyId")
        }
    }

    public static func denialReason(forPolicyViolationField field: String) -> String {
        switch field {
        case "amount":
            return "policy-amount-invalid"
        case "singlePaymentMax":
            return "policy-single-payment-max-exceeded"
        case "remainingLimit":
            return "policy-remaining-limit-exceeded"
        case "merchantScope":
            return "policy-merchant-scope-mismatch"
        case "capabilityScope":
            return "policy-capability-scope-mismatch"
        case "consentGrantId":
            return "policy-consent-grant-mismatch"
        case "asset":
            return "policy-asset-mismatch"
        case "recipientAddress":
            return "policy-recipient-address-mismatch"
        case "startsAt":
            return "policy-not-yet-active"
        case "expiresAt":
            return "policy-expired"
        case "policyId":
            return "policy-id-mismatch"
        case "policyHash":
            return "policy-hash-mismatch"
        case "availableLimit":
            return "policy-available-limit-exceeded"
        default:
            return "policy-\(field)-mismatch"
        }
    }

    private static func normalizedAssetIdentifier(_ field: String, _ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(field)
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier(field, normalized)
        return normalized
    }
}

public struct MeshAgentWalletDelegatedSpendingPolicyExpiryWindowValidator: Codable, Equatable, Sendable {
    public let startsAt: String?
    public let expiresAt: String

    public init(startsAt: String? = nil, expiresAt: String) throws {
        self.startsAt = try startsAt.map { try MeshAgentWalletProviderMetadata.stableValue("startsAt", $0) }
        self.expiresAt = try MeshAgentWalletProviderMetadata.stableValue("expiresAt", expiresAt)
        try validateWindowDefinition()
    }

    public func validateWindowDefinition() throws {
        if let startsAt {
            guard Self.iso8601Date(from: startsAt) != nil else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("startsAt")
            }
        }
        guard let expirationDate = Self.iso8601Date(from: expiresAt) else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("expiresAt")
        }
        if let startsAt, let startDate = Self.iso8601Date(from: startsAt) {
            guard startDate <= expirationDate else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("startsAt")
            }
        }
    }

    public func validateActive(at requestedAt: String) throws {
        let normalizedRequestedAt = try MeshAgentWalletProviderMetadata.stableValue("requestedAt", requestedAt)
        guard let requestedDate = Self.iso8601Date(from: normalizedRequestedAt) else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("requestedAt")
        }
        if let startsAt, let startDate = Self.iso8601Date(from: startsAt), requestedDate < startDate {
            throw MeshKitValidationError.invalidAgentWalletIdentity("startsAt")
        }
        guard let expirationDate = Self.iso8601Date(from: expiresAt), requestedDate <= expirationDate else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("expiresAt")
        }
    }

    private static func iso8601Date(from value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}

public enum MeshAgentWalletPolicyEvaluationStatus: String, Codable, Equatable, Sendable {
    case allowed
    case denied
}

public struct MeshAgentWalletPolicyEvaluationResult: Codable, Equatable, Sendable {
    public let policyId: String
    public let executionId: String
    public let status: MeshAgentWalletPolicyEvaluationStatus
    public let approvedAmount: Decimal?
    public let reason: String?
    public let evaluatedAt: String

    public init(
        policyId: String,
        executionId: String,
        status: MeshAgentWalletPolicyEvaluationStatus,
        approvedAmount: Decimal? = nil,
        reason: String? = nil,
        evaluatedAt: String
    ) throws {
        self.policyId = try MeshAgentWalletProviderMetadata.stableValue("policyId", policyId)
        self.executionId = try MeshAgentWalletProviderMetadata.stableValue("executionId", executionId)
        self.status = status
        self.approvedAmount = approvedAmount
        self.reason = try reason.map { try MeshAgentWalletProviderMetadata.stableValue("reason", $0) }
        self.evaluatedAt = try MeshAgentWalletProviderMetadata.stableValue("evaluatedAt", evaluatedAt)
        try validate()
    }

    public func validate() throws {
        try MeshAgentWalletProviderMetadata.validateIdentifier("policyId", policyId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("executionId", executionId)
        switch status {
        case .allowed:
            guard let approvedAmount, approvedAmount > 0 else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("approvedAmount")
            }
            guard reason == nil else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("reason")
            }
        case .denied:
            guard approvedAmount == nil else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("approvedAmount")
            }
            guard let reason, !reason.isEmpty else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("reason")
            }
        }
        if let reason {
            try MeshAgentWalletProviderMetadata.validateIdentifier("reason", reason)
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("evaluatedAt", evaluatedAt)
    }
}

public enum MeshAgentWalletPolicyValidationStatus: String, Codable, Equatable, Sendable {
    case allowed
    case policyDenied = "policy_denied"
}

public struct MeshAgentWalletPolicyValidationResult: Codable, Equatable, Sendable {
    public let walletIdentity: MeshAgentWalletIdentity
    public let executionRequest: MeshAgentWalletExecutionRequest
    public let policyEvaluation: MeshAgentWalletPolicyEvaluationResult
    public let status: MeshAgentWalletPolicyValidationStatus
    public let approvedAmount: Decimal?
    public let availableLimitBeforeValidation: Decimal
    public let reason: String?
    public let validatedAt: String

    public init(
        walletIdentity: MeshAgentWalletIdentity,
        executionRequest: MeshAgentWalletExecutionRequest,
        policyEvaluation: MeshAgentWalletPolicyEvaluationResult,
        status: MeshAgentWalletPolicyValidationStatus,
        approvedAmount: Decimal? = nil,
        availableLimitBeforeValidation: Decimal,
        reason: String? = nil,
        validatedAt: String
    ) throws {
        self.walletIdentity = walletIdentity
        self.executionRequest = executionRequest
        self.policyEvaluation = policyEvaluation
        self.status = status
        self.approvedAmount = approvedAmount
        self.availableLimitBeforeValidation = availableLimitBeforeValidation
        self.reason = try reason.map { try MeshAgentWalletProviderMetadata.stableValue("reason", $0) }
        self.validatedAt = try MeshAgentWalletProviderMetadata.stableValue("validatedAt", validatedAt)
        try validate()
    }

    public func validate() throws {
        try walletIdentity.validate()
        try executionRequest.validate()
        try policyEvaluation.validate()
        guard policyEvaluation.executionId == executionRequest.executionId else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("executionId")
        }
        guard availableLimitBeforeValidation >= 0 else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("availableLimit")
        }
        switch status {
        case .allowed:
            guard policyEvaluation.status == .allowed else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("policyEvaluation")
            }
            guard let approvedAmount, approvedAmount > 0, approvedAmount <= executionRequest.amount else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("approvedAmount")
            }
            guard approvedAmount <= availableLimitBeforeValidation else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("availableLimit")
            }
            guard reason == nil else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("reason")
            }
        case .policyDenied:
            guard policyEvaluation.status == .denied else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("policyEvaluation")
            }
            guard approvedAmount == nil else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("approvedAmount")
            }
            guard let reason, !reason.isEmpty else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("reason")
            }
        }
        if let reason {
            try MeshAgentWalletProviderMetadata.validateIdentifier("reason", reason)
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("validatedAt", validatedAt)
    }
}

public enum MeshAgentWalletExecutionAccountingStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case attempted
    case pendingReservation
    case confirmed
    case failed
    case policyDenied
    case released
}

public struct MeshAgentWalletExecutionAccountingRecord: Codable, Equatable, Sendable {
    public let executionId: String
    public let policyId: String
    public let requestNonce: String
    public let amount: Decimal
    public let asset: String
    public let status: MeshAgentWalletExecutionAccountingStatus
    public let recordedAt: String
    public let reason: String?

    public init(
        executionRequest: MeshAgentWalletExecutionRequest,
        status: MeshAgentWalletExecutionAccountingStatus,
        recordedAt: String,
        reason: String? = nil
    ) throws {
        self.executionId = executionRequest.executionId
        self.policyId = executionRequest.policyId
        self.requestNonce = executionRequest.requestAnchorMetadata.nonce
        self.amount = executionRequest.amount
        self.asset = try Self.normalizedAssetIdentifier(executionRequest.tokenSymbol ?? executionRequest.currencyCode ?? "")
        self.status = status
        self.recordedAt = try MeshAgentWalletProviderMetadata.stableValue("recordedAt", recordedAt)
        self.reason = try reason.map { try MeshAgentWalletProviderMetadata.stableValue("reason", $0) }
        try validate()
    }

    public init(
        executionId: String,
        policyId: String,
        requestNonce: String,
        amount: Decimal,
        asset: String,
        status: MeshAgentWalletExecutionAccountingStatus,
        recordedAt: String,
        reason: String? = nil
    ) throws {
        self.executionId = try MeshAgentWalletProviderMetadata.stableValue("executionId", executionId)
        self.policyId = try MeshAgentWalletProviderMetadata.stableValue("policyId", policyId)
        self.requestNonce = try MeshAgentWalletProviderMetadata.stableValue("requestNonce", requestNonce)
        self.amount = amount
        self.asset = try Self.normalizedAssetIdentifier(asset)
        self.status = status
        self.recordedAt = try MeshAgentWalletProviderMetadata.stableValue("recordedAt", recordedAt)
        self.reason = try reason.map { try MeshAgentWalletProviderMetadata.stableValue("reason", $0) }
        try validate()
    }

    public func validate() throws {
        try MeshAgentWalletProviderMetadata.validateIdentifier("executionId", executionId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("policyId", policyId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("requestNonce", requestNonce)
        guard amount > 0 else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("amount")
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("asset", asset)
        try MeshAgentWalletProviderMetadata.validateIdentifier("recordedAt", recordedAt)
        if let reason {
            try MeshAgentWalletProviderMetadata.validateIdentifier("reason", reason)
        }
        switch status {
        case .failed, .policyDenied, .released:
            guard reason != nil else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("reason")
            }
        case .attempted, .pendingReservation, .confirmed:
            break
        }
    }

    private static func normalizedAssetIdentifier(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("asset")
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("asset", normalized)
        return normalized
    }
}

public struct MeshAgentWalletDelegatedSpendAccounting: Codable, Equatable, Sendable {
    public let policy: MeshAgentWalletDelegatedSpendingPolicy
    public let records: [MeshAgentWalletExecutionAccountingRecord]

    public var attemptedExecutionCount: Int {
        latestRecords.filter { $0.status != .policyDenied }.count
    }

    public var attemptedAmount: Decimal {
        sumLatestRecords { $0.status != .policyDenied && $0.status != .released }
    }

    public var pendingReservedAmount: Decimal {
        sumLatestRecords { $0.status == .pendingReservation }
    }

    public var confirmedSpendAmount: Decimal {
        sumLatestRecords { $0.status == .confirmed }
    }

    public var failedAttemptAmount: Decimal {
        sumLatestRecords { $0.status == .failed }
    }

    public var policyDeniedAuditRecords: [MeshAgentWalletExecutionAccountingRecord] {
        records.filter { $0.status == .policyDenied }
    }

    public var policyDeniedExecutionCount: Int {
        policyDeniedAuditRecords.count
    }

    public var availableLimit: Decimal {
        max(0, policy.remainingLimit - pendingReservedAmount - confirmedSpendAmount)
    }

    public var remainingLimitAfterConfirmedSpend: Decimal {
        max(0, policy.remainingLimit - confirmedSpendAmount)
    }

    public var balance: MeshAgentWalletDelegatedSpendBalance {
        get throws {
            try MeshAgentWalletDelegatedSpendBalance(accounting: self)
        }
    }

    public init(
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        records: [MeshAgentWalletExecutionAccountingRecord] = []
    ) throws {
        self.policy = policy
        self.records = records
        try validate()
    }

    public func validate() throws {
        try policy.validate()
        for record in records {
            try record.validate()
            guard record.policyId == policy.policyId else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("policyId")
            }
            guard record.asset == policy.asset else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("asset")
            }
        }
        guard pendingReservedAmount + confirmedSpendAmount <= policy.remainingLimit else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("availableLimit")
        }
    }

    public func canReserve(_ request: MeshAgentWalletExecutionRequest, requestedAt: String) throws -> Bool {
        try validateRequestAgainstPolicy(request, requestedAt: requestedAt)
        return request.amount <= availableLimit
    }

    public func recordingAttemptedExecution(
        _ request: MeshAgentWalletExecutionRequest,
        recordedAt: String
    ) throws -> MeshAgentWalletDelegatedSpendAccounting {
        try validateRequestAgainstPolicy(request, requestedAt: recordedAt)
        return try appendingRecord(
            MeshAgentWalletExecutionAccountingRecord(
                executionRequest: request,
                status: .attempted,
                recordedAt: recordedAt
            )
        )
    }

    public func reservingPendingExecution(
        _ request: MeshAgentWalletExecutionRequest,
        recordedAt: String
    ) throws -> MeshAgentWalletDelegatedSpendAccounting {
        try validateRequestAgainstPolicy(request, requestedAt: recordedAt)
        guard request.amount <= availableLimit else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("availableLimit")
        }
        return try appendingRecord(
            MeshAgentWalletExecutionAccountingRecord(
                executionRequest: request,
                status: .pendingReservation,
                recordedAt: recordedAt
            )
        )
    }

    public func recordingConfirmedSpend(
        _ request: MeshAgentWalletExecutionRequest,
        recordedAt: String
    ) throws -> MeshAgentWalletDelegatedSpendAccounting {
        try validateRequestAgainstPolicy(request, requestedAt: recordedAt)
        if latestStatus(for: request.executionId) == .confirmed {
            return self
        }
        guard request.amount <= availableLimit + pendingReservedAmount(for: request.executionId) else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("availableLimit")
        }
        return try appendingRecord(
            MeshAgentWalletExecutionAccountingRecord(
                executionRequest: request,
                status: .confirmed,
                recordedAt: recordedAt
            )
        )
    }

    public func recordingPaymentExecutionResult(
        _ result: MeshPaymentExecutionResult,
        for paymentRequest: MeshPaymentExecutionRequest,
        recordedAt: String
    ) throws -> MeshAgentWalletDelegatedSpendAccounting {
        try validatePaymentExecutionResult(result, for: paymentRequest)

        switch result.status {
        case .confirmed:
            return try recordingConfirmedSpend(
                paymentRequest.executionRequest,
                recordedAt: recordedAt
            )
        case .pending:
            if latestStatus(for: paymentRequest.executionRequest.executionId) == .pendingReservation {
                return self
            }
            return try reservingPendingExecution(
                paymentRequest.executionRequest,
                recordedAt: recordedAt
            )
        case .failed:
            return try recordingFailedExecution(
                paymentRequest.executionRequest,
                recordedAt: recordedAt,
                reason: result.message ?? result.errorPayload?.message ?? "payment-execution-failed"
            )
        case .policyDenied:
            return try recordingPolicyDeniedExecution(
                paymentRequest.executionRequest,
                recordedAt: recordedAt,
                reason: result.message ?? result.errorPayload?.message ?? "policy-denied"
            )
        }
    }

    public func policySnapshotAfterConfirmedSpend() throws -> MeshAgentWalletDelegatedSpendingPolicy {
        try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: policy.policyId,
            policyHash: policy.policyHash,
            consentGrantId: policy.consentGrantId,
            merchantScope: policy.merchantScope,
            capabilityScope: policy.capabilityScope,
            singlePaymentMax: policy.singlePaymentMax,
            sessionTotalLimit: policy.sessionTotalLimit,
            remainingLimit: remainingLimitAfterConfirmedSpend,
            expiresAt: policy.expiresAt,
            asset: policy.asset,
            recipientAddress: policy.recipientAddress
        )
    }

    public func recordingFailedExecution(
        _ request: MeshAgentWalletExecutionRequest,
        recordedAt: String,
        reason: String
    ) throws -> MeshAgentWalletDelegatedSpendAccounting {
        try validateRequestIdentity(request)
        switch latestStatus(for: request.executionId) {
        case .confirmed, .failed:
            return self
        case .attempted, .pendingReservation, .policyDenied, .released, nil:
            break
        }
        return try appendingRecord(
            MeshAgentWalletExecutionAccountingRecord(
                executionRequest: request,
                status: .failed,
                recordedAt: recordedAt,
                reason: reason
            )
        )
    }

    public func recordingPolicyDeniedExecution(
        _ request: MeshAgentWalletExecutionRequest,
        recordedAt: String,
        reason: String
    ) throws -> MeshAgentWalletDelegatedSpendAccounting {
        try validateRequestIdentity(request)
        switch latestStatus(for: request.executionId) {
        case .confirmed, .policyDenied:
            return self
        case .attempted, .pendingReservation, .failed, .released, nil:
            break
        }
        return try appendingRecord(
            MeshAgentWalletExecutionAccountingRecord(
                executionRequest: request,
                status: .policyDenied,
                recordedAt: recordedAt,
                reason: reason
            )
        )
    }

    public func releasingPendingReservation(
        _ request: MeshAgentWalletExecutionRequest,
        recordedAt: String,
        reason: String
    ) throws -> MeshAgentWalletDelegatedSpendAccounting {
        try validateRequestIdentity(request)
        switch latestStatus(for: request.executionId) {
        case .pendingReservation:
            break
        case .released, .confirmed, .failed, .policyDenied:
            return self
        case .attempted, nil:
            break
        }
        return try appendingRecord(
            MeshAgentWalletExecutionAccountingRecord(
                executionRequest: request,
                status: .released,
                recordedAt: recordedAt,
                reason: reason
            )
        )
    }

    private func appendingRecord(
        _ record: MeshAgentWalletExecutionAccountingRecord
    ) throws -> MeshAgentWalletDelegatedSpendAccounting {
        try MeshAgentWalletDelegatedSpendAccounting(policy: policy, records: records + [record])
    }

    private func validateRequestAgainstPolicy(
        _ request: MeshAgentWalletExecutionRequest,
        requestedAt: String
    ) throws {
        try validateRequestIdentity(request)
        try policy.validateExecutionRequest(request, requestedAt: requestedAt)
    }

    private func validateRequestIdentity(_ request: MeshAgentWalletExecutionRequest) throws {
        try request.validate()
        guard request.policyId == policy.policyId,
              request.policyHash == policy.policyHash else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("policyId")
        }
        guard (request.tokenSymbol ?? request.currencyCode ?? "").uppercased() == policy.asset else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("asset")
        }
    }

    private func validatePaymentExecutionResult(
        _ result: MeshPaymentExecutionResult,
        for paymentRequest: MeshPaymentExecutionRequest
    ) throws {
        try paymentRequest.validate()
        try result.validate(originatingSignedRequestHash: paymentRequest.requestHash)
        try validateRequestIdentity(paymentRequest.executionRequest)
        guard result.paymentId == paymentRequest.paymentId,
              result.authorizationId == paymentRequest.authorizationDecision.authorizationId,
              result.kind == paymentRequest.executionRequest.kind,
              result.amount == paymentRequest.executionRequest.amount,
              result.currencyCode == paymentRequest.executionRequest.currencyCode,
              result.tokenSymbol == paymentRequest.executionRequest.tokenSymbol,
              result.recipientAddress == paymentRequest.executionRequest.recipientAddress,
              result.requestAnchorIdentifier == paymentRequest.requestAnchor.identifier else {
            throw MeshKitValidationError.invalidPaymentExecution("paymentResult")
        }
    }

    private var latestRecords: [MeshAgentWalletExecutionAccountingRecord] {
        var latestByExecutionId: [String: MeshAgentWalletExecutionAccountingRecord] = [:]
        var executionOrder: [String] = []
        for record in records {
            if latestByExecutionId[record.executionId] == nil {
                executionOrder.append(record.executionId)
            }
            latestByExecutionId[record.executionId] = record
        }
        return executionOrder.compactMap { latestByExecutionId[$0] }
    }

    private func latestStatus(for executionId: String) -> MeshAgentWalletExecutionAccountingStatus? {
        latestRecords.first { $0.executionId == executionId }?.status
    }

    private func pendingReservedAmount(for executionId: String) -> Decimal {
        latestRecords.first { $0.executionId == executionId && $0.status == .pendingReservation }?.amount ?? 0
    }

    private func sumLatestRecords(
        where include: (MeshAgentWalletExecutionAccountingRecord) -> Bool
    ) -> Decimal {
        latestRecords.reduce(Decimal(0)) { partial, record in
            include(record) ? partial + record.amount : partial
        }
    }
}

public struct MeshAgentWalletDelegatedSpendBalance: Codable, Equatable, Sendable {
    public let policyId: String
    public let configuredLimitAmount: Decimal
    public let priorSettledDebitAmount: Decimal
    public let recordedSettledDebitAmount: Decimal
    public let settledDebitAmount: Decimal
    public let pendingReservationAmount: Decimal
    public let remainingBalanceAmount: Decimal
    public let availableBalanceAmount: Decimal
    public let asset: String

    public init(accounting: MeshAgentWalletDelegatedSpendAccounting) throws {
        let policy = accounting.policy
        let priorSettledDebitAmount = max(0, policy.sessionTotalLimit - policy.remainingLimit)
        let recordedSettledDebitAmount = accounting.confirmedSpendAmount
        let settledDebitAmount = priorSettledDebitAmount + recordedSettledDebitAmount
        try self.init(
            policyId: policy.policyId,
            configuredLimitAmount: policy.sessionTotalLimit,
            priorSettledDebitAmount: priorSettledDebitAmount,
            recordedSettledDebitAmount: recordedSettledDebitAmount,
            settledDebitAmount: settledDebitAmount,
            pendingReservationAmount: accounting.pendingReservedAmount,
            remainingBalanceAmount: max(0, policy.sessionTotalLimit - settledDebitAmount),
            availableBalanceAmount: accounting.availableLimit,
            asset: policy.asset
        )
    }

    public init(
        policyId: String,
        configuredLimitAmount: Decimal,
        priorSettledDebitAmount: Decimal,
        recordedSettledDebitAmount: Decimal,
        settledDebitAmount: Decimal,
        pendingReservationAmount: Decimal,
        remainingBalanceAmount: Decimal,
        availableBalanceAmount: Decimal,
        asset: String
    ) throws {
        self.policyId = try MeshAgentWalletProviderMetadata.stableValue("policyId", policyId)
        self.configuredLimitAmount = configuredLimitAmount
        self.priorSettledDebitAmount = priorSettledDebitAmount
        self.recordedSettledDebitAmount = recordedSettledDebitAmount
        self.settledDebitAmount = settledDebitAmount
        self.pendingReservationAmount = pendingReservationAmount
        self.remainingBalanceAmount = remainingBalanceAmount
        self.availableBalanceAmount = availableBalanceAmount
        self.asset = try Self.normalizedAssetIdentifier(asset)
        try validate()
    }

    public func validate() throws {
        try MeshAgentWalletProviderMetadata.validateIdentifier("policyId", policyId)
        guard configuredLimitAmount > 0 else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("configuredLimitAmount")
        }
        guard priorSettledDebitAmount >= 0 else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("priorSettledDebitAmount")
        }
        guard recordedSettledDebitAmount >= 0 else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("recordedSettledDebitAmount")
        }
        guard settledDebitAmount == priorSettledDebitAmount + recordedSettledDebitAmount else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("settledDebitAmount")
        }
        guard pendingReservationAmount >= 0 else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("pendingReservationAmount")
        }
        guard remainingBalanceAmount == max(0, configuredLimitAmount - settledDebitAmount) else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("remainingBalanceAmount")
        }
        guard availableBalanceAmount == max(0, remainingBalanceAmount - pendingReservationAmount) else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("availableBalanceAmount")
        }
        guard settledDebitAmount + pendingReservationAmount <= configuredLimitAmount else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("availableBalanceAmount")
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("asset", asset)
    }

    private static func normalizedAssetIdentifier(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("asset")
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("asset", normalized)
        return normalized
    }
}

public struct MeshAgentWalletDelegatedSpendDebitResult: Codable, Equatable, Sendable {
    public let walletIdentity: MeshAgentWalletIdentity
    public let executionRequest: MeshAgentWalletExecutionRequest
    public let accounting: MeshAgentWalletDelegatedSpendAccounting
    public let balanceBeforeDebit: MeshAgentWalletDelegatedSpendBalance
    public let balanceAfterDebit: MeshAgentWalletDelegatedSpendBalance
    public let debitedAmount: Decimal
    public let debitedAt: String

    public init(
        walletIdentity: MeshAgentWalletIdentity,
        executionRequest: MeshAgentWalletExecutionRequest,
        accounting: MeshAgentWalletDelegatedSpendAccounting,
        balanceBeforeDebit: MeshAgentWalletDelegatedSpendBalance,
        balanceAfterDebit: MeshAgentWalletDelegatedSpendBalance,
        debitedAmount: Decimal,
        debitedAt: String
    ) throws {
        self.walletIdentity = walletIdentity
        self.executionRequest = executionRequest
        self.accounting = accounting
        self.balanceBeforeDebit = balanceBeforeDebit
        self.balanceAfterDebit = balanceAfterDebit
        self.debitedAmount = debitedAmount
        self.debitedAt = try MeshAgentWalletProviderMetadata.stableValue("debitedAt", debitedAt)
        try validate()
    }

    public func validate() throws {
        try walletIdentity.validate()
        try executionRequest.validate()
        try accounting.validate()
        try balanceBeforeDebit.validate()
        try balanceAfterDebit.validate()
        guard accounting.policy.policyId == executionRequest.policyId,
              accounting.policy.policyHash == executionRequest.policyHash,
              balanceBeforeDebit.policyId == accounting.policy.policyId,
              balanceAfterDebit.policyId == accounting.policy.policyId else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("policyId")
        }
        guard debitedAmount > 0,
              debitedAmount == executionRequest.amount else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("debitedAmount")
        }
        guard balanceAfterDebit.recordedSettledDebitAmount >= balanceBeforeDebit.recordedSettledDebitAmount,
              balanceAfterDebit.availableBalanceAmount <= balanceBeforeDebit.availableBalanceAmount else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("availableBalanceAmount")
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("debitedAt", debitedAt)
    }
}

public struct MeshAgentWalletDelegatedSpendReservationResult: Codable, Equatable, Sendable {
    public let walletIdentity: MeshAgentWalletIdentity
    public let executionRequest: MeshAgentWalletExecutionRequest
    public let accounting: MeshAgentWalletDelegatedSpendAccounting
    public let balanceBeforeReservation: MeshAgentWalletDelegatedSpendBalance
    public let balanceAfterReservation: MeshAgentWalletDelegatedSpendBalance
    public let reservedAmount: Decimal
    public let reservedAt: String

    public init(
        walletIdentity: MeshAgentWalletIdentity,
        executionRequest: MeshAgentWalletExecutionRequest,
        accounting: MeshAgentWalletDelegatedSpendAccounting,
        balanceBeforeReservation: MeshAgentWalletDelegatedSpendBalance,
        balanceAfterReservation: MeshAgentWalletDelegatedSpendBalance,
        reservedAmount: Decimal,
        reservedAt: String
    ) throws {
        self.walletIdentity = walletIdentity
        self.executionRequest = executionRequest
        self.accounting = accounting
        self.balanceBeforeReservation = balanceBeforeReservation
        self.balanceAfterReservation = balanceAfterReservation
        self.reservedAmount = reservedAmount
        self.reservedAt = try MeshAgentWalletProviderMetadata.stableValue("reservedAt", reservedAt)
        try validate()
    }

    public func validate() throws {
        try walletIdentity.validate()
        try executionRequest.validate()
        try accounting.validate()
        try balanceBeforeReservation.validate()
        try balanceAfterReservation.validate()
        guard accounting.policy.policyId == executionRequest.policyId,
              accounting.policy.policyHash == executionRequest.policyHash,
              balanceBeforeReservation.policyId == accounting.policy.policyId,
              balanceAfterReservation.policyId == accounting.policy.policyId else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("policyId")
        }
        guard reservedAmount > 0,
              reservedAmount == executionRequest.amount else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("reservedAmount")
        }
        guard balanceAfterReservation.pendingReservationAmount >= balanceBeforeReservation.pendingReservationAmount,
              balanceAfterReservation.recordedSettledDebitAmount == balanceBeforeReservation.recordedSettledDebitAmount,
              balanceAfterReservation.availableBalanceAmount <= balanceBeforeReservation.availableBalanceAmount else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("availableBalanceAmount")
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("reservedAt", reservedAt)
    }
}

public struct MeshAgentWalletFailedDelegatedSpendReservationReleaseResult: Codable, Equatable, Sendable {
    public let walletIdentity: MeshAgentWalletIdentity
    public let executionRequest: MeshAgentWalletExecutionRequest
    public let accounting: MeshAgentWalletDelegatedSpendAccounting
    public let balanceBeforeRelease: MeshAgentWalletDelegatedSpendBalance
    public let balanceAfterRelease: MeshAgentWalletDelegatedSpendBalance
    public let releasedAmount: Decimal
    public let releasedAt: String
    public let reason: String

    public init(
        walletIdentity: MeshAgentWalletIdentity,
        executionRequest: MeshAgentWalletExecutionRequest,
        accounting: MeshAgentWalletDelegatedSpendAccounting,
        balanceBeforeRelease: MeshAgentWalletDelegatedSpendBalance,
        balanceAfterRelease: MeshAgentWalletDelegatedSpendBalance,
        releasedAmount: Decimal,
        releasedAt: String,
        reason: String
    ) throws {
        self.walletIdentity = walletIdentity
        self.executionRequest = executionRequest
        self.accounting = accounting
        self.balanceBeforeRelease = balanceBeforeRelease
        self.balanceAfterRelease = balanceAfterRelease
        self.releasedAmount = releasedAmount
        self.releasedAt = try MeshAgentWalletProviderMetadata.stableValue("releasedAt", releasedAt)
        self.reason = try MeshAgentWalletProviderMetadata.stableValue("reason", reason)
        try validate()
    }

    public func validate() throws {
        try walletIdentity.validate()
        try executionRequest.validate()
        try accounting.validate()
        try balanceBeforeRelease.validate()
        try balanceAfterRelease.validate()
        guard accounting.policy.policyId == executionRequest.policyId,
              accounting.policy.policyHash == executionRequest.policyHash,
              balanceBeforeRelease.policyId == accounting.policy.policyId,
              balanceAfterRelease.policyId == accounting.policy.policyId else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("policyId")
        }
        guard releasedAmount > 0,
              releasedAmount == executionRequest.amount else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("releasedAmount")
        }
        guard balanceAfterRelease.pendingReservationAmount <= balanceBeforeRelease.pendingReservationAmount,
              balanceAfterRelease.recordedSettledDebitAmount == balanceBeforeRelease.recordedSettledDebitAmount,
              balanceAfterRelease.availableBalanceAmount >= balanceBeforeRelease.availableBalanceAmount else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("availableBalanceAmount")
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("releasedAt", releasedAt)
        try MeshAgentWalletProviderMetadata.validateIdentifier("reason", reason)
    }
}

public struct MeshAgentWalletAnchorSigningPayload: Codable, Equatable, Sendable {
    public static let signingPurpose = "meshkit-agent-wallet-request-anchor/v1"

    public let signingPurpose: String
    public let requestAnchorMetadata: MeshSignedRequestAnchorMetadata
    public let policyId: String
    public let policyHash: MeshPayloadHash
    public let walletAddress: String

    public init(
        requestAnchorMetadata: MeshSignedRequestAnchorMetadata,
        policyId: String,
        policyHash: MeshPayloadHash,
        walletAddress: String,
        signingPurpose: String = Self.signingPurpose
    ) throws {
        self.signingPurpose = try MeshAgentWalletProviderMetadata.stableValue("signingPurpose", signingPurpose)
        self.requestAnchorMetadata = requestAnchorMetadata
        self.policyId = try MeshAgentWalletProviderMetadata.stableValue("policyId", policyId)
        self.policyHash = policyHash
        self.walletAddress = try MeshAgentWalletProviderMetadata.stableValue("walletAddress", walletAddress)
        try validate()
    }

    public func validate() throws {
        try MeshAgentWalletProviderMetadata.validateIdentifier("signingPurpose", signingPurpose)
        try requestAnchorMetadata.validate()
        try MeshAgentWalletProviderMetadata.validateIdentifier("policyId", policyId)
        try validateAgentWalletHash("policyHash", policyHash)
        try MeshAgentWalletProviderMetadata.validateIdentifier("walletAddress", walletAddress)
    }

    public func signingInputData() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

public struct MeshAgentWalletAnchorSignature: Codable, Equatable, Sendable {
    public let walletIdentity: MeshAgentWalletIdentity
    public let payload: MeshAgentWalletAnchorSigningPayload
    public let signature: MeshSignature
    public let signedAt: String

    public init(
        walletIdentity: MeshAgentWalletIdentity,
        payload: MeshAgentWalletAnchorSigningPayload,
        signature: MeshSignature,
        signedAt: String
    ) throws {
        self.walletIdentity = walletIdentity
        self.payload = payload
        self.signature = signature
        self.signedAt = try MeshAgentWalletProviderMetadata.stableValue("signedAt", signedAt)
        try validate()
    }

    public func validate() throws {
        try walletIdentity.validate()
        try payload.validate()
        guard walletIdentity.walletAddress == payload.walletAddress else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("walletAddress")
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("signature.algorithm", signature.algorithm)
        try MeshAgentWalletProviderMetadata.validateIdentifier("signature.keyId", signature.keyId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("signature.value", signature.value)
        try MeshAgentWalletProviderMetadata.validateIdentifier("signedAt", signedAt)
    }
}

public struct MeshAgentWalletExecutionAuthorizationPayload: Codable, Equatable, Sendable {
    public static let signingPurpose = "meshkit-agent-wallet-execution-authorization/v1"

    public let signingPurpose: String
    public let executionRequest: MeshAgentWalletExecutionRequest
    public let policyId: String
    public let policyHash: MeshPayloadHash
    public let walletAddress: String

    public init(
        executionRequest: MeshAgentWalletExecutionRequest,
        policyId: String,
        policyHash: MeshPayloadHash,
        walletAddress: String,
        signingPurpose: String = Self.signingPurpose
    ) throws {
        self.signingPurpose = try MeshAgentWalletProviderMetadata.stableValue("signingPurpose", signingPurpose)
        self.executionRequest = executionRequest
        self.policyId = try MeshAgentWalletProviderMetadata.stableValue("policyId", policyId)
        self.policyHash = policyHash
        self.walletAddress = try MeshAgentWalletProviderMetadata.stableValue("walletAddress", walletAddress)
        try validate()
    }

    public func validate() throws {
        try MeshAgentWalletProviderMetadata.validateIdentifier("signingPurpose", signingPurpose)
        try executionRequest.validate()
        try MeshAgentWalletProviderMetadata.validateIdentifier("policyId", policyId)
        try validateAgentWalletHash("policyHash", policyHash)
        try MeshAgentWalletProviderMetadata.validateIdentifier("walletAddress", walletAddress)
    }

    public func signingInputData() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

public struct MeshAgentWalletExecutionAuthorization: Codable, Equatable, Sendable {
    public let walletIdentity: MeshAgentWalletIdentity
    public let payload: MeshAgentWalletExecutionAuthorizationPayload
    public let signature: MeshSignature
    public let signedAt: String

    public init(
        walletIdentity: MeshAgentWalletIdentity,
        payload: MeshAgentWalletExecutionAuthorizationPayload,
        signature: MeshSignature,
        signedAt: String
    ) throws {
        self.walletIdentity = walletIdentity
        self.payload = payload
        self.signature = signature
        self.signedAt = try MeshAgentWalletProviderMetadata.stableValue("signedAt", signedAt)
        try validate()
    }

    public func validate() throws {
        try walletIdentity.validate()
        try payload.validate()
        guard walletIdentity.walletAddress == payload.walletAddress else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("walletAddress")
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("signature.algorithm", signature.algorithm)
        try MeshAgentWalletProviderMetadata.validateIdentifier("signature.keyId", signature.keyId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("signature.value", signature.value)
        try MeshAgentWalletProviderMetadata.validateIdentifier("signedAt", signedAt)
    }

    public func validate(for decision: MeshAgentWalletAuthorizationDecision) throws {
        try validate()
        guard payload.signingPurpose == MeshAgentWalletExecutionAuthorizationPayload.signingPurpose else {
            throw MeshKitValidationError.invalidPaymentExecution("executionAuthorization.signingPurpose")
        }
        guard payload.signingPurpose != MeshAgentWalletAnchorSigningPayload.signingPurpose else {
            throw MeshKitValidationError.invalidPaymentExecution("executionAuthorization.signingPurpose")
        }
        guard walletIdentity == decision.walletIdentity else {
            throw MeshKitValidationError.invalidPaymentExecution("executionAuthorization.walletIdentity")
        }
        guard payload.executionRequest == decision.executionRequest else {
            throw MeshKitValidationError.invalidPaymentExecution("executionAuthorization.executionRequest")
        }
        guard payload.policyId == decision.executionRequest.policyId,
              payload.policyHash == decision.executionRequest.policyHash else {
            throw MeshKitValidationError.invalidPaymentExecution("executionAuthorization.policy")
        }
    }
}

public enum MeshAgentWalletExecutionKind: String, Codable, Hashable, Sendable {
    case payment
    case transfer
}

public struct MeshAgentWalletExecutionRequest: Codable, Equatable, Sendable {
    public let executionId: String
    public let kind: MeshAgentWalletExecutionKind
    public let requestAnchorMetadata: MeshSignedRequestAnchorMetadata
    public let scope: MeshAgentWalletSpendingScope
    public let amount: Decimal
    public let currencyCode: String?
    public let tokenSymbol: String?
    public let recipientAddress: String
    public let policyId: String
    public let policyHash: MeshPayloadHash

    public init(
        executionId: String,
        kind: MeshAgentWalletExecutionKind,
        requestAnchorMetadata: MeshSignedRequestAnchorMetadata,
        scope: MeshAgentWalletSpendingScope,
        amount: Decimal,
        currencyCode: String? = nil,
        tokenSymbol: String? = nil,
        recipientAddress: String,
        policyId: String,
        policyHash: MeshPayloadHash
    ) throws {
        self.executionId = try MeshAgentWalletProviderMetadata.stableValue("executionId", executionId)
        self.kind = kind
        self.requestAnchorMetadata = requestAnchorMetadata
        self.scope = scope
        self.amount = amount
        self.currencyCode = try currencyCode.map { try Self.normalizedAssetIdentifier("currencyCode", $0) }
        self.tokenSymbol = try tokenSymbol.map { try Self.normalizedAssetIdentifier("tokenSymbol", $0) }
        self.recipientAddress = try MeshAgentWalletProviderMetadata.stableValue("recipientAddress", recipientAddress)
        self.policyId = try MeshAgentWalletProviderMetadata.stableValue("policyId", policyId)
        self.policyHash = policyHash
        try validate()
    }

    public func validate() throws {
        try MeshAgentWalletProviderMetadata.validateIdentifier("executionId", executionId)
        try requestAnchorMetadata.validate()
        try scope.validate()
        guard amount > 0 else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("amount")
        }
        guard currencyCode != nil || tokenSymbol != nil else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("currencyCode")
        }
        if let currencyCode {
            try MeshAgentWalletProviderMetadata.validateIdentifier("currencyCode", currencyCode)
        }
        if let tokenSymbol {
            try MeshAgentWalletProviderMetadata.validateIdentifier("tokenSymbol", tokenSymbol)
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("recipientAddress", recipientAddress)
        try MeshAgentWalletProviderMetadata.validateIdentifier("policyId", policyId)
        try validateAgentWalletHash("policyHash", policyHash)
    }

    private static func normalizedAssetIdentifier(_ field: String, _ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(field)
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier(field, normalized)
        return normalized
    }
}

public extension MeshAgentWalletExecutionRequest {
    func signedMCPRequestAnchoringFields() throws -> MeshSignedMCPRequestAnchoringFields {
        try MeshSignedMCPRequestAnchoringFields(executionRequest: self)
    }
}

public enum MeshAgentWalletAuthorizationStatus: String, Codable, Equatable, Sendable {
    case approved
    case denied
}

public struct MeshAgentWalletAuthorizationDecision: Codable, Equatable, Sendable {
    public let authorizationId: String
    public let walletIdentity: MeshAgentWalletIdentity
    public let executionRequest: MeshAgentWalletExecutionRequest
    public let status: MeshAgentWalletAuthorizationStatus
    public let approvedAmount: Decimal?
    public let reason: String?
    public let decidedAt: String
    public let executionAuthorization: MeshAgentWalletExecutionAuthorization?

    public init(
        authorizationId: String,
        walletIdentity: MeshAgentWalletIdentity,
        executionRequest: MeshAgentWalletExecutionRequest,
        status: MeshAgentWalletAuthorizationStatus,
        approvedAmount: Decimal? = nil,
        reason: String? = nil,
        decidedAt: String,
        executionAuthorization: MeshAgentWalletExecutionAuthorization? = nil
    ) throws {
        self.authorizationId = try MeshAgentWalletProviderMetadata.stableValue("authorizationId", authorizationId)
        self.walletIdentity = walletIdentity
        self.executionRequest = executionRequest
        self.status = status
        self.approvedAmount = approvedAmount
        self.reason = try reason.map { try MeshAgentWalletProviderMetadata.stableValue("reason", $0) }
        self.decidedAt = try MeshAgentWalletProviderMetadata.stableValue("decidedAt", decidedAt)
        self.executionAuthorization = executionAuthorization
        try validate()
    }

    public func validate() throws {
        try MeshAgentWalletProviderMetadata.validateIdentifier("authorizationId", authorizationId)
        try walletIdentity.validate()
        try executionRequest.validate()
        switch status {
        case .approved:
            guard let approvedAmount, approvedAmount > 0, approvedAmount <= executionRequest.amount else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("approvedAmount")
            }
        case .denied:
            guard approvedAmount == nil else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("approvedAmount")
            }
            guard let reason, !reason.isEmpty else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("reason")
            }
        }
        if let reason {
            try MeshAgentWalletProviderMetadata.validateIdentifier("reason", reason)
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("decidedAt", decidedAt)
        try executionAuthorization?.validate()
    }

    public func validateExecutionAuthorizationBoundary() throws {
        try validate()
        try executionAuthorization?.validate(for: self)
    }
}

public struct MeshAgentWalletAuthorizationCheckResult: Codable, Equatable, Sendable {
    public let walletIdentity: MeshAgentWalletIdentity
    public let executionRequest: MeshAgentWalletExecutionRequest
    public let policyEvaluation: MeshAgentWalletPolicyEvaluationResult
    public let status: MeshAgentWalletAuthorizationStatus
    public let approvedAmount: Decimal?
    public let availableLimitBeforeAuthorization: Decimal
    public let reason: String?
    public let checkedAt: String

    public init(
        walletIdentity: MeshAgentWalletIdentity,
        executionRequest: MeshAgentWalletExecutionRequest,
        policyEvaluation: MeshAgentWalletPolicyEvaluationResult,
        status: MeshAgentWalletAuthorizationStatus,
        approvedAmount: Decimal? = nil,
        availableLimitBeforeAuthorization: Decimal,
        reason: String? = nil,
        checkedAt: String
    ) throws {
        self.walletIdentity = walletIdentity
        self.executionRequest = executionRequest
        self.policyEvaluation = policyEvaluation
        self.status = status
        self.approvedAmount = approvedAmount
        self.availableLimitBeforeAuthorization = availableLimitBeforeAuthorization
        self.reason = try reason.map { try MeshAgentWalletProviderMetadata.stableValue("reason", $0) }
        self.checkedAt = try MeshAgentWalletProviderMetadata.stableValue("checkedAt", checkedAt)
        try validate()
    }

    public func validate() throws {
        try walletIdentity.validate()
        try executionRequest.validate()
        try policyEvaluation.validate()
        guard policyEvaluation.executionId == executionRequest.executionId else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("executionId")
        }
        guard availableLimitBeforeAuthorization >= 0 else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("availableLimit")
        }
        switch status {
        case .approved:
            guard policyEvaluation.status == .allowed else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("policyEvaluation")
            }
            guard let approvedAmount, approvedAmount > 0, approvedAmount <= executionRequest.amount else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("approvedAmount")
            }
            guard approvedAmount <= availableLimitBeforeAuthorization else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("availableLimit")
            }
            guard reason == nil else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("reason")
            }
        case .denied:
            guard approvedAmount == nil else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("approvedAmount")
            }
            guard let reason, !reason.isEmpty else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("reason")
            }
        }
        if let reason {
            try MeshAgentWalletProviderMetadata.validateIdentifier("reason", reason)
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("checkedAt", checkedAt)
    }

    public func authorizationDecision(
        authorizationId: String,
        decidedAt: String? = nil,
        executionAuthorization: MeshAgentWalletExecutionAuthorization? = nil
    ) throws -> MeshAgentWalletAuthorizationDecision {
        try validate()
        return try MeshAgentWalletAuthorizationDecision(
            authorizationId: authorizationId,
            walletIdentity: walletIdentity,
            executionRequest: executionRequest,
            status: status,
            approvedAmount: approvedAmount,
            reason: reason,
            decidedAt: decidedAt ?? checkedAt,
            executionAuthorization: executionAuthorization
        )
    }
}

public struct MeshAgentWalletIdentity: Codable, Equatable, Sendable {
    public let walletId: String
    public let agentId: String
    public let walletAddress: String
    public let providerMetadata: MeshAgentWalletProviderMetadata
    public let signingBoundary: MeshAgentWalletSigningBoundary

    public init(
        walletId: String,
        agentId: String,
        walletAddress: String,
        providerMetadata: MeshAgentWalletProviderMetadata,
        signingBoundary: MeshAgentWalletSigningBoundary
    ) throws {
        self.walletId = try MeshAgentWalletProviderMetadata.stableValue("walletId", walletId)
        self.agentId = try MeshAgentWalletProviderMetadata.stableValue("agentId", agentId)
        self.walletAddress = try MeshAgentWalletProviderMetadata.stableValue("walletAddress", walletAddress)
        self.providerMetadata = providerMetadata
        self.signingBoundary = signingBoundary
        try validate()
    }

    public func validate() throws {
        try MeshAgentWalletProviderMetadata.validateIdentifier("walletId", walletId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("agentId", agentId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("walletAddress", walletAddress)
        try providerMetadata.validate()
    }
}

public struct MeshAgentWalletConfiguration: Codable, Equatable, Sendable {
    public let identity: MeshAgentWalletIdentity
    public let capabilities: [MeshAgentWalletCapability]

    public init(identity: MeshAgentWalletIdentity, capabilities: [MeshAgentWalletCapability]) throws {
        self.identity = identity
        self.capabilities = Array(Set(capabilities)).sorted()
        try validate()
    }

    public func supports(_ capability: MeshAgentWalletCapability) -> Bool {
        capabilities.contains(capability)
    }

    public func require(_ capability: MeshAgentWalletCapability) throws {
        guard supports(capability) else { throw MeshKitValidationError.unsupportedCapability }
    }

    public func validate() throws {
        try identity.validate()
        guard !capabilities.isEmpty else { throw MeshKitValidationError.unsupportedCapability }
    }
}

public struct MeshAgentWalletIdentityMetadata: Codable, Equatable, Sendable {
    public let walletId: String
    public let agentId: String
    public let walletAddress: String
    public let provider: String
    public let network: String
    public let chainId: String
    public let rpcEndpoint: URL?
    public let explorerBaseUrl: URL?
    public let adapterId: String?
    public let signingBoundary: MeshAgentWalletSigningBoundary
    public let capabilities: [MeshAgentWalletCapability]

    public init(configuration: MeshAgentWalletConfiguration) throws {
        try self.init(
            identity: configuration.identity,
            capabilities: configuration.capabilities
        )
    }

    public init(
        identity: MeshAgentWalletIdentity,
        capabilities: [MeshAgentWalletCapability]
    ) throws {
        self.walletId = identity.walletId
        self.agentId = identity.agentId
        self.walletAddress = identity.walletAddress
        self.provider = identity.providerMetadata.provider
        self.network = identity.providerMetadata.network
        self.chainId = identity.providerMetadata.chainId
        self.rpcEndpoint = identity.providerMetadata.rpcEndpoint
        self.explorerBaseUrl = identity.providerMetadata.explorerBaseUrl
        self.adapterId = identity.providerMetadata.adapterId
        self.signingBoundary = identity.signingBoundary
        self.capabilities = Array(Set(capabilities)).sorted()
        try validate()
    }

    public func validate() throws {
        try MeshAgentWalletProviderMetadata.validateIdentifier("walletId", walletId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("agentId", agentId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("walletAddress", walletAddress)
        try MeshAgentWalletProviderMetadata.validateIdentifier("provider", provider)
        try MeshAgentWalletProviderMetadata.validateIdentifier("network", network)
        try MeshAgentWalletProviderMetadata.validateIdentifier("chainId", chainId)
        if let rpcEndpoint {
            try MeshAgentWalletProviderMetadata.validateNetworkURL("rpcEndpoint", rpcEndpoint)
        }
        if let explorerBaseUrl {
            try MeshAgentWalletProviderMetadata.validateNetworkURL("explorerBaseUrl", explorerBaseUrl)
        }
        if let adapterId {
            try MeshAgentWalletProviderMetadata.validateIdentifier("adapterId", adapterId)
        }
        guard !capabilities.isEmpty else {
            throw MeshKitValidationError.unsupportedCapability
        }
    }
}

public struct MeshAgentWalletAddressReport: Codable, Equatable, Sendable {
    public let walletId: String
    public let agentId: String
    public let walletAddress: String
    public let provider: String
    public let network: String
    public let chainId: String
    public let adapterId: String?
    public let signingBoundary: MeshAgentWalletSigningBoundary

    public init(
        identity: MeshAgentWalletIdentity,
        reportedWalletAddress: String
    ) throws {
        self.walletId = identity.walletId
        self.agentId = identity.agentId
        self.walletAddress = try MeshAgentWalletProviderMetadata.stableValue(
            "walletAddress",
            reportedWalletAddress
        )
        self.provider = identity.providerMetadata.provider
        self.network = identity.providerMetadata.network
        self.chainId = identity.providerMetadata.chainId
        self.adapterId = identity.providerMetadata.adapterId
        self.signingBoundary = identity.signingBoundary
        try validate(expectedIdentity: identity)
    }

    public func validate(expectedIdentity identity: MeshAgentWalletIdentity) throws {
        try identity.validate()
        try MeshAgentWalletProviderMetadata.validateIdentifier("walletAddress", walletAddress)
        guard walletId == identity.walletId,
              agentId == identity.agentId,
              provider == identity.providerMetadata.provider,
              network == identity.providerMetadata.network,
              chainId == identity.providerMetadata.chainId,
              adapterId == identity.providerMetadata.adapterId,
              signingBoundary == identity.signingBoundary else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("identity")
        }
        guard walletAddress == identity.walletAddress else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("walletAddress")
        }
    }
}

public struct MeshAgentWalletAddressReportingModule: Sendable {
    public let wallet: any MeshAgentWallet

    public init(wallet: any MeshAgentWallet) {
        self.wallet = wallet
    }

    public func reportWalletAddress() throws -> MeshAgentWalletAddressReport {
        let configuration = try wallet.loadWalletConfiguration()
        try configuration.require(.reportWalletAddress)
        let reportedAddress = try wallet.reportWalletAddress()
        return try MeshAgentWalletAddressReport(
            identity: configuration.identity,
            reportedWalletAddress: reportedAddress
        )
    }
}

public struct MeshAgentWalletPolicyValidationModule: Sendable {
    public let wallet: any MeshAgentWallet

    public init(wallet: any MeshAgentWallet) {
        self.wallet = wallet
    }

    public func evaluateExecutionRequest(
        _ request: MeshAgentWalletExecutionRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        accounting: MeshAgentWalletDelegatedSpendAccounting? = nil,
        requestedAt: String
    ) throws -> MeshAgentWalletPolicyEvaluationResult {
        let configuration = try wallet.loadWalletConfiguration()
        try configuration.require(.validatePolicy)
        let normalizedRequestedAt = try MeshAgentWalletProviderMetadata.stableValue("requestedAt", requestedAt)
        let spendAccounting = try accounting ?? MeshAgentWalletDelegatedSpendAccounting(policy: policy)
        try spendAccounting.validate()

        let policyEvaluation: MeshAgentWalletPolicyEvaluationResult
        do {
            try policy.validateExecutionRequest(request, requestedAt: normalizedRequestedAt)
            policyEvaluation = try policy.evaluateExecutionRequest(request, requestedAt: normalizedRequestedAt)
        } catch MeshKitValidationError.invalidAgentWalletIdentity(let field) {
            policyEvaluation = try MeshAgentWalletPolicyEvaluationResult(
                policyId: policy.policyId,
                executionId: request.executionId,
                status: .denied,
                approvedAmount: nil,
                reason: MeshAgentWalletDelegatedSpendingPolicy.denialReason(forPolicyViolationField: field),
                evaluatedAt: normalizedRequestedAt
            )
        }

        guard policyEvaluation.status == .allowed else {
            return policyEvaluation
        }
        guard request.amount <= spendAccounting.availableLimit else {
            return try MeshAgentWalletPolicyEvaluationResult(
                policyId: policy.policyId,
                executionId: request.executionId,
                status: .denied,
                approvedAmount: nil,
                reason: MeshAgentWalletDelegatedSpendingPolicy.denialReason(forPolicyViolationField: "availableLimit"),
                evaluatedAt: normalizedRequestedAt
            )
        }
        return policyEvaluation
    }

    public func validateExecutionRequest(
        _ request: MeshAgentWalletExecutionRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        accounting: MeshAgentWalletDelegatedSpendAccounting? = nil,
        validatedAt: String
    ) throws -> MeshAgentWalletPolicyValidationResult {
        let configuration = try wallet.loadWalletConfiguration()
        try configuration.require(.validatePolicy)
        let normalizedValidatedAt = try MeshAgentWalletProviderMetadata.stableValue(
            "validatedAt",
            validatedAt
        )
        let spendAccounting = try accounting ?? MeshAgentWalletDelegatedSpendAccounting(policy: policy)
        try spendAccounting.validate()
        let evaluation = try evaluateExecutionRequest(
            request,
            policy: policy,
            accounting: spendAccounting,
            requestedAt: normalizedValidatedAt
        )

        switch evaluation.status {
        case .allowed:
            return try MeshAgentWalletPolicyValidationResult(
                walletIdentity: configuration.identity,
                executionRequest: request,
                policyEvaluation: evaluation,
                status: .allowed,
                approvedAmount: evaluation.approvedAmount,
                availableLimitBeforeValidation: spendAccounting.availableLimit,
                validatedAt: normalizedValidatedAt
            )
        case .denied:
            return try MeshAgentWalletPolicyValidationResult(
                walletIdentity: configuration.identity,
                executionRequest: request,
                policyEvaluation: evaluation,
                status: .policyDenied,
                approvedAmount: nil,
                availableLimitBeforeValidation: spendAccounting.availableLimit,
                reason: evaluation.reason ?? "policy-denied",
                validatedAt: normalizedValidatedAt
            )
        }
    }

    public func validateAllowedExecutionRequest(
        _ request: MeshAgentWalletExecutionRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        accounting: MeshAgentWalletDelegatedSpendAccounting? = nil,
        requestedAt: String
    ) throws -> MeshAgentWalletPolicyEvaluationResult {
        let evaluation = try evaluateExecutionRequest(
            request,
            policy: policy,
            accounting: accounting,
            requestedAt: requestedAt
        )
        guard evaluation.status == .allowed else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(evaluation.reason ?? "policy-denied")
        }
        return evaluation
    }
}

public struct MeshAgentWalletSignedRequestArtifact: Codable, Equatable, Sendable {
    public let walletIdentity: MeshAgentWalletIdentity
    public let signedRequest: MeshRequest
    public let anchorMetadata: MeshSignedRequestAnchorMetadata
    public let signedAt: String

    public init(
        walletIdentity: MeshAgentWalletIdentity,
        signedRequest: MeshRequest,
        anchorMetadata: MeshSignedRequestAnchorMetadata? = nil,
        signedAt: String
    ) throws {
        self.walletIdentity = walletIdentity
        self.signedRequest = signedRequest
        self.anchorMetadata = try anchorMetadata ?? MeshSignedRequestAnchorMetadata(request: signedRequest)
        self.signedAt = try MeshAgentWalletProviderMetadata.stableValue("signedAt", signedAt)
        try validate()
    }

    public func validate() throws {
        try walletIdentity.validate()
        try MeshTarget.validateRequestEnvelope(signedRequest)
        try anchorMetadata.validate()
        try MeshRequestAnchorCanonicalization.validate(metadata: anchorMetadata, boundTo: signedRequest)
        try MeshAgentWalletProviderMetadata.validateIdentifier("signedAt", signedAt)
        guard !signedRequest.signature.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeshKitValidationError.signatureRequired
        }
        guard signedRequest.signature.keyId == signedRequest.caller.publicKeyId else {
            throw MeshKitValidationError.signatureMismatch("request signature key must match caller publicKeyId")
        }
    }
}

public struct MeshAgentWalletRequestSigningModule: Sendable {
    public let wallet: any MeshAgentWallet

    public init(wallet: any MeshAgentWallet) {
        self.wallet = wallet
    }

    public func signRequestArtifact(
        caller: MeshIdentity,
        target: MeshCapability,
        signer: MeshRequestSigner,
        requestId: String,
        payload: [String: String],
        nonce: String,
        timestamp: String,
        signedAt: String
    ) throws -> MeshAgentWalletSignedRequestArtifact {
        let configuration = try wallet.loadWalletConfiguration()
        try configuration.require(.signMCPRequest)
        let normalizedSignedAt = try MeshAgentWalletProviderMetadata.stableValue("signedAt", signedAt)
        let request = try MeshSignedRequestBuilder(
            caller: caller,
            target: target,
            signer: signer
        ).makeRequest(
            requestId: requestId,
            payload: payload,
            nonce: nonce,
            timestamp: timestamp
        )
        return try MeshAgentWalletSignedRequestArtifact(
            walletIdentity: configuration.identity,
            signedRequest: request,
            signedAt: normalizedSignedAt
        )
    }
}

public protocol MeshAgentWallet: Sendable {
    var identity: MeshAgentWalletIdentity { get }
    var capabilities: [MeshAgentWalletCapability] { get }

    func loadWalletConfiguration() throws -> MeshAgentWalletConfiguration
    func reportWalletAddress() throws -> String
    func delegatedSpendingLimit() throws -> MeshAgentWalletDelegatedSpendingLimit
    func signingBoundary() throws -> MeshAgentWalletSigningBoundary
    func signRequestAnchorPayload(_ payload: MeshAgentWalletAnchorSigningPayload, signedAt: String) throws -> MeshAgentWalletAnchorSignature
    func signExecutionAuthorizationPayload(_ payload: MeshAgentWalletExecutionAuthorizationPayload, signedAt: String) throws -> MeshAgentWalletExecutionAuthorization
    func authorizeExecution(_ request: MeshAgentWalletExecutionRequest, decidedAt: String) throws -> MeshAgentWalletAuthorizationDecision
}

public extension MeshAgentWallet {
    func delegatedWalletIdentityMetadata() throws -> MeshAgentWalletIdentityMetadata {
        try MeshAgentWalletIdentityMetadata(configuration: loadWalletConfiguration())
    }

    func availableDelegatedSpendBalance(
        accounting: MeshAgentWalletDelegatedSpendAccounting
    ) throws -> MeshAgentWalletDelegatedSpendBalance {
        let configuration = try loadWalletConfiguration()
        try configuration.require(.reportDelegatedSpendingLimit)
        let reportedLimit = try delegatedSpendingLimit()
        try reportedLimit.validate()
        try accounting.validate()
        guard reportedLimit.limitAmount == accounting.policy.sessionTotalLimit else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("limitAmount")
        }
        guard reportedLimit.scope.merchantId == accounting.policy.merchantScope,
              reportedLimit.scope.capabilityId == accounting.policy.capabilityScope,
              reportedLimit.scope.consentGrantId == accounting.policy.consentGrantId else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("scope")
        }
        guard reportedLimit.tokenSymbol == accounting.policy.asset ||
              reportedLimit.currencyCode == accounting.policy.asset else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("asset")
        }
        return try accounting.balance
    }

    func reservePendingDelegatedSpend(
        _ request: MeshAgentWalletExecutionRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        accounting: MeshAgentWalletDelegatedSpendAccounting? = nil,
        reservedAt: String
    ) throws -> MeshAgentWalletDelegatedSpendReservationResult {
        let configuration = try loadWalletConfiguration()
        try configuration.require(.accountForPendingSpendReservation)
        let normalizedReservedAt = try MeshAgentWalletProviderMetadata.stableValue("reservedAt", reservedAt)
        let spendAccounting = try accounting ?? MeshAgentWalletDelegatedSpendAccounting(policy: policy)
        try spendAccounting.validate()
        guard spendAccounting.policy == policy else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("policy")
        }

        let balanceBeforeReservation = try MeshAgentWalletDelegatedSpendBalance(accounting: spendAccounting)
        let updatedAccounting = try spendAccounting.reservingPendingExecution(
            request,
            recordedAt: normalizedReservedAt
        )
        let balanceAfterReservation = try MeshAgentWalletDelegatedSpendBalance(accounting: updatedAccounting)

        return try MeshAgentWalletDelegatedSpendReservationResult(
            walletIdentity: configuration.identity,
            executionRequest: request,
            accounting: updatedAccounting,
            balanceBeforeReservation: balanceBeforeReservation,
            balanceAfterReservation: balanceAfterReservation,
            reservedAmount: request.amount,
            reservedAt: normalizedReservedAt
        )
    }

    func applySuccessfulDelegatedSpendDebit(
        _ request: MeshAgentWalletExecutionRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        accounting: MeshAgentWalletDelegatedSpendAccounting? = nil,
        debitedAt: String
    ) throws -> MeshAgentWalletDelegatedSpendDebitResult {
        let configuration = try loadWalletConfiguration()
        try configuration.require(.accountForConfirmedSpend)
        let normalizedDebitedAt = try MeshAgentWalletProviderMetadata.stableValue("debitedAt", debitedAt)
        let spendAccounting = try accounting ?? MeshAgentWalletDelegatedSpendAccounting(policy: policy)
        try spendAccounting.validate()
        guard spendAccounting.policy == policy else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("policy")
        }

        let balanceBeforeDebit = try MeshAgentWalletDelegatedSpendBalance(accounting: spendAccounting)
        let updatedAccounting = try spendAccounting.recordingConfirmedSpend(
            request,
            recordedAt: normalizedDebitedAt
        )
        let balanceAfterDebit = try MeshAgentWalletDelegatedSpendBalance(accounting: updatedAccounting)

        return try MeshAgentWalletDelegatedSpendDebitResult(
            walletIdentity: configuration.identity,
            executionRequest: request,
            accounting: updatedAccounting,
            balanceBeforeDebit: balanceBeforeDebit,
            balanceAfterDebit: balanceAfterDebit,
            debitedAmount: request.amount,
            debitedAt: normalizedDebitedAt
        )
    }

    func releaseFailedDelegatedSpendReservation(
        _ request: MeshAgentWalletExecutionRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        accounting: MeshAgentWalletDelegatedSpendAccounting? = nil,
        releasedAt: String,
        reason: String
    ) throws -> MeshAgentWalletFailedDelegatedSpendReservationReleaseResult {
        let configuration = try loadWalletConfiguration()
        try configuration.require(.accountForPendingSpendReservation)
        let normalizedReleasedAt = try MeshAgentWalletProviderMetadata.stableValue("releasedAt", releasedAt)
        let normalizedReason = try MeshAgentWalletProviderMetadata.stableValue("reason", reason)
        let spendAccounting = try accounting ?? MeshAgentWalletDelegatedSpendAccounting(policy: policy)
        try spendAccounting.validate()
        guard spendAccounting.policy == policy else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("policy")
        }

        let balanceBeforeRelease = try MeshAgentWalletDelegatedSpendBalance(accounting: spendAccounting)
        let updatedAccounting = try spendAccounting.recordingFailedExecution(
            request,
            recordedAt: normalizedReleasedAt,
            reason: normalizedReason
        )
        let balanceAfterRelease = try MeshAgentWalletDelegatedSpendBalance(accounting: updatedAccounting)

        return try MeshAgentWalletFailedDelegatedSpendReservationReleaseResult(
            walletIdentity: configuration.identity,
            executionRequest: request,
            accounting: updatedAccounting,
            balanceBeforeRelease: balanceBeforeRelease,
            balanceAfterRelease: balanceAfterRelease,
            releasedAmount: request.amount,
            releasedAt: normalizedReleasedAt,
            reason: normalizedReason
        )
    }

    func checkExecutionAuthorization(
        _ request: MeshAgentWalletExecutionRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        accounting: MeshAgentWalletDelegatedSpendAccounting? = nil,
        checkedAt: String
    ) throws -> MeshAgentWalletAuthorizationCheckResult {
        let configuration = try loadWalletConfiguration()
        try configuration.require(.checkExecutionAuthorization)
        let normalizedCheckedAt = try MeshAgentWalletProviderMetadata.stableValue("checkedAt", checkedAt)
        let spendAccounting = try accounting ?? MeshAgentWalletDelegatedSpendAccounting(policy: policy)
        try spendAccounting.validate()

        let policyEvaluation: MeshAgentWalletPolicyEvaluationResult
        do {
            try policy.validateExecutionRequest(request, requestedAt: normalizedCheckedAt)
            policyEvaluation = try policy.evaluateExecutionRequest(request, requestedAt: normalizedCheckedAt)
        } catch MeshKitValidationError.invalidAgentWalletIdentity(let field) {
            policyEvaluation = try MeshAgentWalletPolicyEvaluationResult(
                policyId: policy.policyId,
                executionId: request.executionId,
                status: .denied,
                approvedAmount: nil,
                reason: MeshAgentWalletDelegatedSpendingPolicy.denialReason(forPolicyViolationField: field),
                evaluatedAt: normalizedCheckedAt
            )
        }

        guard policyEvaluation.status == .allowed else {
            return try MeshAgentWalletAuthorizationCheckResult(
                walletIdentity: configuration.identity,
                executionRequest: request,
                policyEvaluation: policyEvaluation,
                status: .denied,
                approvedAmount: nil,
                availableLimitBeforeAuthorization: spendAccounting.availableLimit,
                reason: policyEvaluation.reason,
                checkedAt: normalizedCheckedAt
            )
        }

        guard request.amount <= spendAccounting.availableLimit else {
            let deniedEvaluation = try MeshAgentWalletPolicyEvaluationResult(
                policyId: policy.policyId,
                executionId: request.executionId,
                status: .denied,
                approvedAmount: nil,
                reason: MeshAgentWalletDelegatedSpendingPolicy.denialReason(forPolicyViolationField: "availableLimit"),
                evaluatedAt: normalizedCheckedAt
            )
            return try MeshAgentWalletAuthorizationCheckResult(
                walletIdentity: configuration.identity,
                executionRequest: request,
                policyEvaluation: deniedEvaluation,
                status: .denied,
                approvedAmount: nil,
                availableLimitBeforeAuthorization: spendAccounting.availableLimit,
                reason: deniedEvaluation.reason,
                checkedAt: normalizedCheckedAt
            )
        }

        return try MeshAgentWalletAuthorizationCheckResult(
            walletIdentity: configuration.identity,
            executionRequest: request,
            policyEvaluation: policyEvaluation,
            status: .approved,
            approvedAmount: policyEvaluation.approvedAmount,
            availableLimitBeforeAuthorization: spendAccounting.availableLimit,
            checkedAt: normalizedCheckedAt
        )
    }
}

public struct MeshAgentWalletRequestAnchorRecord: Codable, Equatable, Sendable {
    public let walletIdentity: MeshAgentWalletIdentity
    public let walletAnchorSignature: MeshAgentWalletAnchorSignature
    public let anchor: MeshRequestAnchor
    public let anchoringReference: MeshRequestAnchorIdentifier

    public var requestHash: MeshPayloadHash {
        anchor.metadata.signedRequestHash
    }

    public var requestNonce: String {
        anchor.metadata.nonce
    }

    public var policyId: String {
        walletAnchorSignature.payload.policyId
    }

    public var policyHash: MeshPayloadHash {
        walletAnchorSignature.payload.policyHash
    }

    public init(
        walletIdentity: MeshAgentWalletIdentity,
        walletAnchorSignature: MeshAgentWalletAnchorSignature,
        anchor: MeshRequestAnchor
    ) throws {
        self.walletIdentity = walletIdentity
        self.walletAnchorSignature = walletAnchorSignature
        self.anchor = anchor
        self.anchoringReference = anchor.identifier
        try validate()
    }

    public func validate() throws {
        try walletIdentity.validate()
        try walletAnchorSignature.validate()
        try anchor.validate()
        try anchoringReference.validate()
        guard walletIdentity == walletAnchorSignature.walletIdentity else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("walletIdentity")
        }
        guard anchoringReference == anchor.identifier else {
            throw MeshKitValidationError.signatureMismatch("agent wallet request anchor reference mismatch")
        }
        guard anchor.metadata == walletAnchorSignature.payload.requestAnchorMetadata else {
            throw MeshKitValidationError.signatureMismatch("agent wallet request anchor metadata mismatch")
        }
        guard anchor.payload?.policyId == walletAnchorSignature.payload.policyId,
              anchor.payload?.policyHash == walletAnchorSignature.payload.policyHash else {
            throw MeshKitValidationError.signatureMismatch("agent wallet request anchor policy mismatch")
        }
    }
}

public struct MeshAgentWalletRequestAnchorRecorder: Sendable {
    public let wallet: any MeshAgentWallet
    public let requestAnchorSubmissionModule: MeshRequestAnchorSubmissionModule

    public init(
        wallet: any MeshAgentWallet,
        requestAnchorProvider: any MeshRequestAnchorProvider
    ) {
        self.wallet = wallet
        self.requestAnchorSubmissionModule = MeshRequestAnchorSubmissionModule(provider: requestAnchorProvider)
    }

    public init(
        wallet: any MeshAgentWallet,
        requestAnchorSubmissionModule: MeshRequestAnchorSubmissionModule
    ) {
        self.wallet = wallet
        self.requestAnchorSubmissionModule = requestAnchorSubmissionModule
    }

    public func recordSignedRequestAnchor(
        request: MeshRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        submittedAt: String,
        signedAt: String
    ) async throws -> MeshAgentWalletRequestAnchorRecord {
        let configuration = try wallet.loadWalletConfiguration()
        try configuration.require(.signRequestAnchorPayload)

        let submission = try MeshRequestAnchorSubmission(
            request: request,
            policy: policy,
            providerIdentity: requestAnchorSubmissionModule.provider.identity,
            submittedAt: submittedAt
        )
        let signingPayload = try MeshAgentWalletAnchorSigningPayload(
            requestAnchorMetadata: submission.payload.metadata,
            policyId: submission.payload.policyId,
            policyHash: submission.payload.policyHash,
            walletAddress: configuration.identity.walletAddress
        )
        let walletSignature = try wallet.signRequestAnchorPayload(signingPayload, signedAt: signedAt)
        let anchor = try await requestAnchorSubmissionModule.submit(submission, boundTo: request, policy: policy)

        return try MeshAgentWalletRequestAnchorRecord(
            walletIdentity: configuration.identity,
            walletAnchorSignature: walletSignature,
            anchor: anchor
        )
    }
}

public struct MeshAgentWalletPaymentSubmission: Codable, Equatable, Sendable {
    public let anchorRecord: MeshAgentWalletRequestAnchorRecord
    public let authorizationDecision: MeshAgentWalletAuthorizationDecision
    public let paymentRequest: MeshPaymentExecutionRequest
    public let paymentResult: MeshPaymentExecutionResult

    public init(
        anchorRecord: MeshAgentWalletRequestAnchorRecord,
        authorizationDecision: MeshAgentWalletAuthorizationDecision,
        paymentRequest: MeshPaymentExecutionRequest,
        paymentResult: MeshPaymentExecutionResult
    ) throws {
        self.anchorRecord = anchorRecord
        self.authorizationDecision = authorizationDecision
        self.paymentRequest = paymentRequest
        self.paymentResult = paymentResult
        try validate()
    }

    public func validate() throws {
        try anchorRecord.validate()
        try authorizationDecision.validate()
        try paymentRequest.validate()
        try paymentResult.validate()
        guard authorizationDecision == paymentRequest.authorizationDecision else {
            throw MeshKitValidationError.invalidPaymentExecution("authorizationDecision")
        }
        guard anchorRecord.anchor == paymentRequest.requestAnchor else {
            throw MeshKitValidationError.invalidPaymentExecution("requestAnchor")
        }
        guard paymentResult.paymentId == paymentRequest.paymentId,
              paymentResult.authorizationId == authorizationDecision.authorizationId,
              paymentResult.requestAnchorIdentifier == anchorRecord.anchor.identifier,
              paymentResult.signedRequestHash == anchorRecord.requestHash else {
            throw MeshKitValidationError.invalidPaymentExecution("paymentResult")
        }
    }
}

public struct MeshAgentWalletPaymentSubmissionPath: Sendable {
    public let wallet: any MeshAgentWallet
    public let requestAnchorRecorder: MeshAgentWalletRequestAnchorRecorder
    public let paymentExecutor: any MeshPaymentExecutor

    public init(
        wallet: any MeshAgentWallet,
        requestAnchorProvider: any MeshRequestAnchorProvider,
        paymentExecutor: any MeshPaymentExecutor
    ) {
        self.wallet = wallet
        self.requestAnchorRecorder = MeshAgentWalletRequestAnchorRecorder(
            wallet: wallet,
            requestAnchorProvider: requestAnchorProvider
        )
        self.paymentExecutor = paymentExecutor
    }

    public init(
        wallet: any MeshAgentWallet,
        requestAnchorRecorder: MeshAgentWalletRequestAnchorRecorder,
        paymentExecutor: any MeshPaymentExecutor
    ) {
        self.wallet = wallet
        self.requestAnchorRecorder = requestAnchorRecorder
        self.paymentExecutor = paymentExecutor
    }

    public func submitPayment(
        request: MeshRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        executionId: String,
        amount: Decimal,
        currencyCode: String? = nil,
        tokenSymbol: String? = nil,
        recipientAddress: String,
        paymentId: String,
        anchorSubmittedAt: String,
        anchorSignedAt: String,
        authorizationDecidedAt: String,
        paymentRequestedAt: String,
        paymentSubmittedAt: String
    ) async throws -> MeshAgentWalletPaymentSubmission {
        try await submitExecution(
            kind: .payment,
            request: request,
            policy: policy,
            executionId: executionId,
            amount: amount,
            currencyCode: currencyCode,
            tokenSymbol: tokenSymbol,
            recipientAddress: recipientAddress,
            paymentId: paymentId,
            anchorSubmittedAt: anchorSubmittedAt,
            anchorSignedAt: anchorSignedAt,
            authorizationDecidedAt: authorizationDecidedAt,
            paymentRequestedAt: paymentRequestedAt,
            paymentSubmittedAt: paymentSubmittedAt
        )
    }

    public func submitPayment(
        artifact: MeshAgentWalletSignedRequestArtifact,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        executionId: String,
        amount: Decimal,
        currencyCode: String? = nil,
        tokenSymbol: String? = nil,
        recipientAddress: String,
        paymentId: String,
        anchorSubmittedAt: String,
        anchorSignedAt: String,
        authorizationDecidedAt: String,
        paymentRequestedAt: String,
        paymentSubmittedAt: String
    ) async throws -> MeshAgentWalletPaymentSubmission {
        try await submitExecution(
            kind: .payment,
            artifact: artifact,
            policy: policy,
            executionId: executionId,
            amount: amount,
            currencyCode: currencyCode,
            tokenSymbol: tokenSymbol,
            recipientAddress: recipientAddress,
            paymentId: paymentId,
            anchorSubmittedAt: anchorSubmittedAt,
            anchorSignedAt: anchorSignedAt,
            authorizationDecidedAt: authorizationDecidedAt,
            paymentRequestedAt: paymentRequestedAt,
            paymentSubmittedAt: paymentSubmittedAt
        )
    }

    public func submitTransfer(
        request: MeshRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        executionId: String,
        amount: Decimal,
        currencyCode: String? = nil,
        tokenSymbol: String? = nil,
        recipientAddress: String,
        paymentId: String,
        anchorSubmittedAt: String,
        anchorSignedAt: String,
        authorizationDecidedAt: String,
        paymentRequestedAt: String,
        paymentSubmittedAt: String
    ) async throws -> MeshAgentWalletPaymentSubmission {
        try await submitExecution(
            kind: .transfer,
            request: request,
            policy: policy,
            executionId: executionId,
            amount: amount,
            currencyCode: currencyCode,
            tokenSymbol: tokenSymbol,
            recipientAddress: recipientAddress,
            paymentId: paymentId,
            anchorSubmittedAt: anchorSubmittedAt,
            anchorSignedAt: anchorSignedAt,
            authorizationDecidedAt: authorizationDecidedAt,
            paymentRequestedAt: paymentRequestedAt,
            paymentSubmittedAt: paymentSubmittedAt
        )
    }

    public func submitTransfer(
        artifact: MeshAgentWalletSignedRequestArtifact,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        executionId: String,
        amount: Decimal,
        currencyCode: String? = nil,
        tokenSymbol: String? = nil,
        recipientAddress: String,
        paymentId: String,
        anchorSubmittedAt: String,
        anchorSignedAt: String,
        authorizationDecidedAt: String,
        paymentRequestedAt: String,
        paymentSubmittedAt: String
    ) async throws -> MeshAgentWalletPaymentSubmission {
        try await submitExecution(
            kind: .transfer,
            artifact: artifact,
            policy: policy,
            executionId: executionId,
            amount: amount,
            currencyCode: currencyCode,
            tokenSymbol: tokenSymbol,
            recipientAddress: recipientAddress,
            paymentId: paymentId,
            anchorSubmittedAt: anchorSubmittedAt,
            anchorSignedAt: anchorSignedAt,
            authorizationDecidedAt: authorizationDecidedAt,
            paymentRequestedAt: paymentRequestedAt,
            paymentSubmittedAt: paymentSubmittedAt
        )
    }

    private func submitExecution(
        kind: MeshAgentWalletExecutionKind,
        request: MeshRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        executionId: String,
        amount: Decimal,
        currencyCode: String?,
        tokenSymbol: String?,
        recipientAddress: String,
        paymentId: String,
        anchorSubmittedAt: String,
        anchorSignedAt: String,
        authorizationDecidedAt: String,
        paymentRequestedAt: String,
        paymentSubmittedAt: String
    ) async throws -> MeshAgentWalletPaymentSubmission {
        let artifact = try MeshAgentWalletSignedRequestArtifact(
            walletIdentity: try wallet.loadWalletConfiguration().identity,
            signedRequest: request,
            signedAt: anchorSignedAt
        )
        return try await submitExecution(
            kind: kind,
            artifact: artifact,
            policy: policy,
            executionId: executionId,
            amount: amount,
            currencyCode: currencyCode,
            tokenSymbol: tokenSymbol,
            recipientAddress: recipientAddress,
            paymentId: paymentId,
            anchorSubmittedAt: anchorSubmittedAt,
            anchorSignedAt: anchorSignedAt,
            authorizationDecidedAt: authorizationDecidedAt,
            paymentRequestedAt: paymentRequestedAt,
            paymentSubmittedAt: paymentSubmittedAt
        )
    }

    private func submitExecution(
        kind: MeshAgentWalletExecutionKind,
        artifact: MeshAgentWalletSignedRequestArtifact,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        executionId: String,
        amount: Decimal,
        currencyCode: String?,
        tokenSymbol: String?,
        recipientAddress: String,
        paymentId: String,
        anchorSubmittedAt: String,
        anchorSignedAt: String,
        authorizationDecidedAt: String,
        paymentRequestedAt: String,
        paymentSubmittedAt: String
    ) async throws -> MeshAgentWalletPaymentSubmission {
        try artifact.validate()
        let configuration = try wallet.loadWalletConfiguration()
        guard artifact.walletIdentity == configuration.identity else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("signedRequestArtifact.walletIdentity")
        }

        let request = artifact.signedRequest
        let metadata = artifact.anchorMetadata
        let executionRequest = try MeshAgentWalletExecutionRequest(
            executionId: executionId,
            kind: kind,
            requestAnchorMetadata: metadata,
            scope: MeshAgentWalletSpendingScope(
                merchantId: policy.merchantScope,
                targetBundleId: request.target.targetBundleId,
                capabilityId: policy.capabilityScope,
                consentGrantId: policy.consentGrantId
            ),
            amount: amount,
            currencyCode: currencyCode,
            tokenSymbol: tokenSymbol,
            recipientAddress: recipientAddress,
            policyId: policy.policyId,
            policyHash: policy.policyHash
        )
        try policy.validateExecutionRequest(executionRequest, requestedAt: authorizationDecidedAt)
        try policy.validateExecutionRequest(executionRequest, requestedAt: paymentRequestedAt)
        try validateExecutionBoundary(configuration)
        let authorizationDecision = try wallet.authorizeExecution(
            executionRequest,
            decidedAt: authorizationDecidedAt
        )
        guard authorizationDecision.status == .approved else {
            throw MeshKitValidationError.invalidPaymentExecution("authorizationDecision")
        }

        let anchorRecord = try await requestAnchorRecorder.recordSignedRequestAnchor(
            request: request,
            policy: policy,
            submittedAt: anchorSubmittedAt,
            signedAt: anchorSignedAt
        )
        guard anchorRecord.anchor.status != .failed else {
            throw MeshKitValidationError.invalidPaymentExecution("requestAnchor")
        }

        let paymentRequest = try MeshPaymentExecutionRequest(
            paymentId: paymentId,
            authorizationDecision: authorizationDecision,
            requestAnchor: anchorRecord.anchor,
            requestedAt: paymentRequestedAt
        )
        let paymentResult = try await paymentExecutor.executePayment(
            paymentRequest,
            originatingRequest: request,
            submittedAt: paymentSubmittedAt
        )

        return try MeshAgentWalletPaymentSubmission(
            anchorRecord: anchorRecord,
            authorizationDecision: authorizationDecision,
            paymentRequest: paymentRequest,
            paymentResult: paymentResult
        )
    }

    private func validateExecutionBoundary(_ configuration: MeshAgentWalletConfiguration) throws {
        try configuration.require(.authorizeExecution)
        guard configuration.identity.signingBoundary != .localSignature else {
            throw MeshKitValidationError.invalidPaymentExecution("signingBoundary")
        }
    }
}

public struct MeshMarooAgentWalletAdapter: MeshAgentWallet {
    public let identity: MeshAgentWalletIdentity
    public let capabilities: [MeshAgentWalletCapability]

    private static let supportedCapabilities: Set<MeshAgentWalletCapability> = [
        .reportWalletAddress,
        .validatePolicy,
        .exposeSigningBoundary,
        .checkExecutionAuthorization
    ]

    public init(
        chainProviderIdentity: MeshChainProviderIdentity,
        walletId: String,
        agentId: String,
        walletAddress: String,
        adapterId: String = "maroo-testnet-agent-wallet-adapter",
        signingBoundary: MeshAgentWalletSigningBoundary = .providerSubmission,
        capabilities: [MeshAgentWalletCapability] = [.reportWalletAddress, .exposeSigningBoundary]
    ) throws {
        let providerMetadata = try MeshAgentWalletProviderMetadata(
            chainProviderIdentity: chainProviderIdentity,
            adapterId: adapterId
        )
        self.identity = try MeshAgentWalletIdentity(
            walletId: walletId,
            agentId: agentId,
            walletAddress: walletAddress,
            providerMetadata: providerMetadata,
            signingBoundary: signingBoundary
        )
        self.capabilities = try Self.normalizedSupportedCapabilities(capabilities)
        try loadWalletConfiguration().validate()
    }

    public init(
        identity: MeshAgentWalletIdentity,
        capabilities: [MeshAgentWalletCapability] = [.reportWalletAddress, .exposeSigningBoundary]
    ) throws {
        self.identity = identity
        self.capabilities = try Self.normalizedSupportedCapabilities(capabilities)
        try loadWalletConfiguration().validate()
    }

    public func loadWalletConfiguration() throws -> MeshAgentWalletConfiguration {
        try MeshAgentWalletConfiguration(identity: identity, capabilities: capabilities)
    }

    public func reportWalletAddress() throws -> String {
        try loadWalletConfiguration().require(.reportWalletAddress)
        return identity.walletAddress
    }

    public func delegatedSpendingLimit() throws -> MeshAgentWalletDelegatedSpendingLimit {
        try loadWalletConfiguration().require(.reportDelegatedSpendingLimit)
        throw MeshKitValidationError.unsupportedCapability
    }

    public func signingBoundary() throws -> MeshAgentWalletSigningBoundary {
        try loadWalletConfiguration().require(.exposeSigningBoundary)
        return identity.signingBoundary
    }

    public func signRequestAnchorPayload(
        _ payload: MeshAgentWalletAnchorSigningPayload,
        signedAt: String
    ) throws -> MeshAgentWalletAnchorSignature {
        try loadWalletConfiguration().require(.signRequestAnchorPayload)
        try payload.validate()
        _ = try MeshAgentWalletProviderMetadata.stableValue("signedAt", signedAt)
        throw MeshKitValidationError.unsupportedCapability
    }

    public func authorizeExecution(
        _ request: MeshAgentWalletExecutionRequest,
        decidedAt: String
    ) throws -> MeshAgentWalletAuthorizationDecision {
        try loadWalletConfiguration().require(.authorizeExecution)
        try request.validate()
        _ = try MeshAgentWalletProviderMetadata.stableValue("decidedAt", decidedAt)
        throw MeshKitValidationError.unsupportedCapability
    }

    public func signExecutionAuthorizationPayload(
        _ payload: MeshAgentWalletExecutionAuthorizationPayload,
        signedAt: String
    ) throws -> MeshAgentWalletExecutionAuthorization {
        try loadWalletConfiguration().require(.signExecutionAuthorizationPayload)
        try payload.validate()
        _ = try MeshAgentWalletProviderMetadata.stableValue("signedAt", signedAt)
        throw MeshKitValidationError.unsupportedCapability
    }

    private static func normalizedSupportedCapabilities(
        _ capabilities: [MeshAgentWalletCapability]
    ) throws -> [MeshAgentWalletCapability] {
        let normalized = Array(Set(capabilities)).sorted()
        guard !normalized.isEmpty else {
            throw MeshKitValidationError.unsupportedCapability
        }
        guard normalized.allSatisfy({ supportedCapabilities.contains($0) }) else {
            throw MeshKitValidationError.unsupportedCapability
        }
        return normalized
    }
}

func validateAgentWalletHash(_ field: String, _ hash: MeshPayloadHash) throws {
    guard hash.algorithm.lowercased() == "sha256" else {
        throw MeshKitValidationError.unsupportedPayloadHashAlgorithm
    }
    guard hash.value.count == 64,
          hash.value.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdefABCDEF").inverted) == nil else {
        throw MeshKitValidationError.invalidAgentWalletIdentity("\(field).value")
    }
}
