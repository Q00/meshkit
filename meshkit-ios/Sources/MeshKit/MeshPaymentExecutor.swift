import CryptoKit
import Foundation
#if canImport(FoundationNetworking)
@preconcurrency import FoundationNetworking
#endif

public enum MeshPaymentExecutorCapability: String, Codable, CaseIterable, Comparable, Sendable {
    case executePayment
    case executeTransfer
    case lookupExecutionStatus

    public static func < (lhs: MeshPaymentExecutorCapability, rhs: MeshPaymentExecutorCapability) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum MeshPaymentExecutorFailureKind: String, Codable, Equatable, Sendable {
    case transport
    case rpc
    case network
    case contractUnavailable
    case policyDenied
}

public protocol MeshPaymentExecutorProviderFailure: Error {
    var paymentExecutorFailureKind: MeshPaymentExecutorFailureKind { get }
    var providerFailureCode: String { get }
    var providerFailureMessage: String { get }
}

public struct MeshPaymentExecutorChainError: Error, Codable, Equatable, Sendable, MeshPaymentExecutorProviderFailure {
    public let paymentExecutorFailureKind: MeshPaymentExecutorFailureKind
    public let providerFailureCode: String
    public let providerFailureMessage: String

    public init(
        failureKind: MeshPaymentExecutorFailureKind,
        code: String,
        message: String
    ) throws {
        self.paymentExecutorFailureKind = failureKind
        self.providerFailureCode = try normalizedPaymentField("chainError.code", code)
        self.providerFailureMessage = try normalizedPaymentField("chainError.message", message)
    }
}

public struct MeshPaymentExecutorCapabilityError: Error, Codable, Equatable, CustomStringConvertible, Sendable {
    public static let fallbackExecutionErrorCode = "provider_execution_error"
    public static let fallbackExecutionErrorMessage = "provider execution failed"

    public let capability: MeshPaymentExecutorCapability
    public let failureKind: MeshPaymentExecutorFailureKind
    public let code: String
    public let message: String

    public init(
        capability: MeshPaymentExecutorCapability,
        failureKind: MeshPaymentExecutorFailureKind,
        code: String,
        message: String
    ) throws {
        self.capability = capability
        self.failureKind = failureKind
        self.code = try Self.normalizedCapabilityErrorCode(code)
        self.message = try normalizedPaymentField("capabilityError.message", message)
    }

    public var description: String {
        "\(capability.rawValue) \(failureKind.rawValue) failure: \(message)"
    }

    public static func providerNeutral(
        _ error: Error,
        capability: MeshPaymentExecutorCapability
    ) throws -> MeshPaymentExecutorCapabilityError {
        if let capabilityError = error as? MeshPaymentExecutorCapabilityError {
            guard capabilityError.capability == capability else {
                return try MeshPaymentExecutorCapabilityError(
                    capability: capability,
                    failureKind: capabilityError.failureKind,
                    code: capabilityError.code,
                    message: capabilityError.message
                )
            }
            return capabilityError
        }

        if let providerFailure = error as? MeshPaymentExecutorProviderFailure {
            do {
                return try MeshPaymentExecutorCapabilityError(
                    capability: capability,
                    failureKind: providerFailure.paymentExecutorFailureKind,
                    code: providerFailure.providerFailureCode,
                    message: providerFailure.providerFailureMessage
                )
            } catch {
                return try fallback(capability: capability)
            }
        }

        if let urlError = error as? URLError,
           let kind = MeshPaymentExecutorFailureKind(urlError: urlError) {
            return try MeshPaymentExecutorCapabilityError(
                capability: capability,
                failureKind: kind,
                code: "url_error_\(urlError.code.rawValue)",
                message: Self.message(for: urlError)
            )
        }

        if let denialCode = Self.delegatedSpendingPolicyDenialCode(for: error) {
            return try MeshPaymentExecutorCapabilityError(
                capability: capability,
                failureKind: .policyDenied,
                code: denialCode,
                message: denialCode
            )
        }

        if let validationError = error as? MeshKitValidationError {
            switch validationError {
            case .invalidPaymentExecution:
                return try fallback(capability: capability)
            default:
                throw error
            }
        }

        return try fallback(capability: capability)
    }

    public static func fallback(
        capability: MeshPaymentExecutorCapability
    ) throws -> MeshPaymentExecutorCapabilityError {
        try MeshPaymentExecutorCapabilityError(
            capability: capability,
            failureKind: .rpc,
            code: fallbackExecutionErrorCode,
            message: fallbackExecutionErrorMessage
        )
    }

    private static func message(for urlError: URLError) -> String {
        switch urlError.code {
        case .badServerResponse, .cannotDecodeContentData, .cannotDecodeRawData, .cannotParseResponse:
            return "provider transport failure"
        default:
            return "provider network failure"
        }
    }

    private static func delegatedSpendingPolicyDenialCode(for error: Error) -> String? {
        guard case MeshKitValidationError.invalidAgentWalletIdentity(let field) = error else {
            return nil
        }
        switch field {
        case "amount":
            return "policy-amount-invalid"
        case "singlePaymentMax":
            return "policy-single-payment-max-exceeded"
        case "remainingLimit", "availableLimit":
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
        case "expiresAt":
            return "policy-expired"
        default:
            return nil
        }
    }

    private static func normalizedCapabilityErrorCode(_ code: String) throws -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: CharacterSet.newlines.union(.controlCharacters)) == nil else {
            throw MeshKitValidationError.invalidPaymentExecution("capabilityError.code")
        }

        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-")
        var scalars = String.UnicodeScalarView()
        var previousWasSeparator = false

        for scalar in trimmed.lowercased().unicodeScalars {
            if allowedCharacters.contains(scalar) {
                scalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                scalars.append("_")
                previousWasSeparator = true
            }
        }

        let normalized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        guard !normalized.isEmpty else {
            throw MeshKitValidationError.invalidPaymentExecution("capabilityError.code")
        }
        return normalized
    }
}

private extension MeshPaymentExecutorFailureKind {
    init?(urlError: URLError) {
        switch urlError.code {
        case .badServerResponse, .cannotDecodeContentData, .cannotDecodeRawData, .cannotParseResponse:
            self = .transport
        case .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .networkConnectionLost,
             .notConnectedToInternet,
             .timedOut:
            self = .network
        default:
            return nil
        }
    }
}

public enum MeshPaymentExecutionStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case pending
    case confirmed
    case failed
    case policyDenied

    public init(providerExecutionOutcome outcome: String) throws {
        let normalizedOutcome = outcome
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch normalizedOutcome {
        case "confirmed", "complete", "completed", "executed", "finalized", "finalised", "included", "mined", "success", "succeeded":
            self = .confirmed
        case "pending", "accepted", "awaiting_confirmation", "broadcast", "broadcasted", "in_flight", "in_mempool", "mempool", "processing", "queued", "submitted", "unconfirmed":
            self = .pending
        case "failed",
             "failure",
             "reverted",
             "execution_reverted",
             "contract_reverted",
             "rejected",
             "declined",
             "error",
             "execution_error",
             "provider_error",
             "rpc_error",
             "timeout",
             "timed_out",
             "dropped",
             "expired",
             "cancelled",
             "canceled",
             "insufficient_funds",
             "insufficient_balance":
            self = .failed
        case "denied",
             "policy_denied",
             "policydenied",
             "policy_rejected",
             "policy_rejection",
             "policy_declined",
             "authorization_denied",
             "auth_denied",
             "wallet_denied",
             "wallet_policy_denied",
             "spending_limit_denied",
             "spending_limit_exceeded",
             "delegated_limit_exceeded",
             "limit_exceeded":
            self = .policyDenied
        default:
            throw MeshKitValidationError.invalidPaymentExecution("providerExecutionOutcome")
        }
    }
}

public enum MeshMarooTestnetPaymentExecutionProviderOutcome: String, Codable, CaseIterable, Equatable, Sendable {
    case success
    case pending
    case failure
    case policyDenied = "policy_denied"

    public init(providerValue: String) throws {
        let normalized = providerValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        guard !normalized.isEmpty else {
            throw MeshKitValidationError.invalidPaymentExecution("providerOutcome")
        }

        switch normalized {
        case "success",
             "succeeded",
             "confirmed",
             "complete",
             "completed",
             "executed",
             "finalized",
             "finalised",
             "included",
             "mined":
            self = .success
        case "pending",
             "submitted",
             "accepted",
             "queued",
             "broadcast",
             "broadcasted",
             "processing",
             "in_flight",
             "in_mempool",
             "mempool",
             "awaiting_confirmation",
             "unconfirmed":
            self = .pending
        case "failure",
             "failed",
             "error",
             "execution_error",
             "provider_error",
             "rpc_error",
             "rejected",
             "declined",
             "reverted",
             "execution_reverted",
             "contract_reverted",
             "dropped",
             "expired",
             "timeout",
             "timed_out",
             "insufficient_funds",
             "insufficient_balance":
            self = .failure
        case "policy_denied",
             "policydenied",
             "policy_rejected",
             "policy_rejection",
             "policy_declined",
             "authorization_denied",
             "auth_denied",
             "wallet_denied",
             "wallet_policy_denied",
             "spending_limit_denied",
             "spending_limit_exceeded",
             "delegated_limit_exceeded",
             "limit_exceeded":
            self = .policyDenied
        default:
            throw MeshKitValidationError.invalidPaymentExecution("providerOutcome")
        }
    }

    public var executionStatus: MeshPaymentExecutionStatus {
        switch self {
        case .success:
            return .confirmed
        case .pending:
            return .pending
        case .failure:
            return .failed
        case .policyDenied:
            return .policyDenied
        }
    }

    public var isPolicyDenied: Bool {
        self == .policyDenied
    }
}

public struct MeshMarooTestnetPaymentExecutionResultMapping: Codable, Equatable, Sendable {
    public let providerOutcome: MeshMarooTestnetPaymentExecutionProviderOutcome
    public let executionStatus: MeshPaymentExecutionStatus
    public let isPolicyDenied: Bool
    public let errorCode: String?
    public let defaultMessage: String?

    public init(providerOutcome: MeshMarooTestnetPaymentExecutionProviderOutcome) {
        self.providerOutcome = providerOutcome
        self.executionStatus = providerOutcome.executionStatus
        self.isPolicyDenied = providerOutcome.isPolicyDenied

        switch providerOutcome {
        case .success:
            self.errorCode = nil
            self.defaultMessage = nil
        case .pending:
            self.errorCode = nil
            self.defaultMessage = "maroo testnet OKRW execution pending confirmation"
        case .failure:
            self.errorCode = "payment_execution_failed"
            self.defaultMessage = "maroo testnet OKRW execution failed"
        case .policyDenied:
            self.errorCode = "policy_denied"
            self.defaultMessage = "policy denied"
        }
    }

    public init(providerOutcome value: String) throws {
        self.init(providerOutcome: try MeshMarooTestnetPaymentExecutionProviderOutcome(providerValue: value))
    }
}

public enum MeshPaymentExecutionResultSource: String, Codable, CaseIterable, Equatable, Sendable {
    case live
    case fallback
    case mock
    case cached
    case simulated

    public init(providerValue value: String) throws {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        guard !normalized.isEmpty else {
            throw MeshKitValidationError.invalidPaymentExecution("resultSource")
        }

        switch normalized {
        case "live", "chain", "on_chain", "provider", "rpc", "network":
            self = .live
        case "fallback", "deterministic_fallback", "local_fallback":
            self = .fallback
        case "mock", "mocked", "test_mock":
            self = .mock
        case "cached", "cache", "replayed_cache":
            self = .cached
        case "simulated", "simulation", "dry_run":
            self = .simulated
        default:
            throw MeshKitValidationError.invalidPaymentExecution("resultSource")
        }
    }

    public var canConfirmPaymentExecution: Bool {
        self == .live
    }
}

public struct MeshPaymentExecutionResultSourceStateMapping: Codable, Equatable, Sendable {
    public let source: MeshPaymentExecutionResultSource
    public let providerOutcome: MeshMarooTestnetPaymentExecutionProviderOutcome
    public let explicitStatus: MeshPaymentExecutionStatus?
    public let executionStatus: MeshPaymentExecutionStatus
    public let errorCode: String?
    public let defaultMessage: String?

    public init(
        source: MeshPaymentExecutionResultSource,
        providerOutcome: MeshMarooTestnetPaymentExecutionProviderOutcome,
        explicitStatus: MeshPaymentExecutionStatus? = nil
    ) {
        self.source = source
        self.providerOutcome = providerOutcome
        self.explicitStatus = explicitStatus

        if source.canConfirmPaymentExecution {
            let mapping = MeshMarooTestnetPaymentExecutionResultMapping(providerOutcome: providerOutcome)
            self.executionStatus = mapping.executionStatus
            self.errorCode = mapping.errorCode
            self.defaultMessage = mapping.defaultMessage
        } else if explicitStatus == .policyDenied || providerOutcome == .policyDenied {
            self.executionStatus = .policyDenied
            self.errorCode = "policy_denied"
            self.defaultMessage = "policy denied"
        } else if explicitStatus == .failed || providerOutcome == .failure {
            self.executionStatus = .failed
            self.errorCode = "non_confirmed_execution_source"
            self.defaultMessage = "\(source.rawValue) execution result cannot confirm payment"
        } else {
            self.executionStatus = .pending
            self.errorCode = nil
            self.defaultMessage = "\(source.rawValue) execution awaiting live confirmation"
        }
    }

    public init(source value: String, providerOutcome: String) throws {
        self.init(
            source: try MeshPaymentExecutionResultSource(providerValue: value),
            providerOutcome: try MeshMarooTestnetPaymentExecutionProviderOutcome(providerValue: providerOutcome)
        )
    }

    public var isSourceBlockedFromConfirmation: Bool {
        !source.canConfirmPaymentExecution
    }
}

public struct MeshMarooTestnetTransactionStateMapping: Codable, Equatable, Sendable {
    public let providerTransactionState: String
    public let providerOutcome: MeshMarooTestnetPaymentExecutionProviderOutcome
    public let executionStatus: MeshPaymentExecutionStatus
    public let defaultMessage: String?

    public init(providerTransactionState value: String) throws {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        guard !normalized.isEmpty else {
            throw MeshKitValidationError.invalidPaymentExecution("providerTransactionState")
        }

        switch normalized {
        case "confirmed",
             "complete",
             "completed",
             "executed",
             "finalised",
             "finalized",
             "included",
             "mined",
             "receipt_confirmed",
             "receipt_success",
             "success",
             "succeeded",
             "tx_complete",
             "tx_completed",
             "tx_confirmed",
             "tx_executed",
             "tx_finalised",
             "tx_finalized",
             "tx_included",
             "tx_mined",
             "tx_success",
             "tx_succeeded":
            self.providerTransactionState = normalized
            self.providerOutcome = .success
            self.executionStatus = .confirmed
            self.defaultMessage = nil
        case "accepted",
             "awaiting_confirmation",
             "broadcast",
             "broadcasted",
             "in_flight",
             "in_mempool",
             "mempool",
             "pending",
             "processing",
             "queued",
             "submitted",
             "tx_accepted",
             "tx_broadcast",
             "tx_broadcasted",
             "tx_in_flight",
             "tx_in_mempool",
             "tx_pending",
             "tx_processing",
             "tx_queued",
             "tx_submitted",
             "unconfirmed":
            self.providerTransactionState = normalized
            self.providerOutcome = .pending
            self.executionStatus = .pending
            self.defaultMessage = "maroo testnet OKRW execution pending confirmation"
        case "contract_reverted",
             "declined",
             "dropped",
             "error",
             "execution_error",
             "execution_reverted",
             "expired",
             "failed",
             "failure",
             "insufficient_balance",
             "insufficient_funds",
             "provider_error",
             "receipt_failed",
             "receipt_reverted",
             "rejected",
             "reverted",
             "rpc_error",
             "timeout",
             "timed_out",
             "tx_contract_reverted",
             "tx_declined",
             "tx_dropped",
             "tx_error",
             "tx_execution_error",
             "tx_execution_reverted",
             "tx_expired",
             "tx_failed",
             "tx_failure",
             "tx_insufficient_balance",
             "tx_insufficient_funds",
             "tx_provider_error",
             "tx_rejected",
             "tx_reverted",
             "tx_rpc_error",
             "tx_timeout",
             "tx_timed_out":
            self.providerTransactionState = normalized
            self.providerOutcome = .failure
            self.executionStatus = .failed
            self.defaultMessage = "maroo testnet OKRW execution failed"
        default:
            throw MeshKitValidationError.invalidPaymentExecution("providerTransactionState")
        }
    }
}

public struct MeshPaymentExecutionErrorPayload: Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) throws {
        self.code = try normalizedPaymentField("errorPayload.code", code)
        self.message = try normalizedPaymentField("errorPayload.message", message)
    }

    public func validate() throws {
        try requirePaymentField("errorPayload.code", code)
        try requirePaymentField("errorPayload.message", message)
    }
}

public struct MeshPaymentExecutorConfiguration: Codable, Equatable, Sendable {
    public let identity: MeshChainProviderIdentity
    public let capabilities: [MeshPaymentExecutorCapability]

    public init(identity: MeshChainProviderIdentity, capabilities: [MeshPaymentExecutorCapability]) throws {
        self.identity = identity
        self.capabilities = Array(Set(capabilities)).sorted()
        try validate()
    }

    public func supports(_ capability: MeshPaymentExecutorCapability) -> Bool {
        capabilities.contains(capability)
    }

    public func require(_ capability: MeshPaymentExecutorCapability) throws {
        guard supports(capability) else { throw MeshKitValidationError.unsupportedCapability }
    }

    public func validate() throws {
        try identity.validate()
        guard !capabilities.isEmpty else { throw MeshKitValidationError.unsupportedCapability }
    }
}

public struct MeshPaymentExecutionCapabilityMetadata: Codable, Equatable, Sendable {
    public let identity: MeshChainProviderIdentity
    public let adapterId: String
    public let capabilities: [MeshPaymentExecutorCapability]
    public let supportedExecutionKinds: [MeshAgentWalletExecutionKind]
    public let supportedAssets: [String]
    public let paymentOperations: [MeshPaymentOperationCapability]
    public let requestHashLinkage: Bool
    public let policyBinding: Bool
    public let statusValues: [MeshPaymentExecutionStatus]

    public init(
        identity: MeshChainProviderIdentity,
        adapterId: String,
        capabilities: [MeshPaymentExecutorCapability],
        supportedExecutionKinds: [MeshAgentWalletExecutionKind],
        supportedAssets: [String],
        paymentOperations: [MeshPaymentOperationCapability]? = nil,
        requestHashLinkage: Bool,
        policyBinding: Bool,
        statusValues: [MeshPaymentExecutionStatus] = MeshPaymentExecutionStatus.allCases
    ) throws {
        self.identity = identity
        self.adapterId = try normalizedPaymentIdentifier("adapterId", adapterId)
        self.capabilities = Array(Set(capabilities)).sorted()
        self.supportedExecutionKinds = supportedExecutionKinds
        self.supportedAssets = try supportedAssets.map { try Self.normalizedAssetIdentifier($0) }
        if let paymentOperations {
            self.paymentOperations = try paymentOperations.map { try $0.normalized() }
        } else {
            self.paymentOperations = try Self.defaultPaymentOperations(
                supportedExecutionKinds: supportedExecutionKinds,
                supportedAssets: self.supportedAssets
            )
        }
        self.requestHashLinkage = requestHashLinkage
        self.policyBinding = policyBinding
        self.statusValues = statusValues
        try validate()
    }

    public func supportsAsset(_ asset: String) throws -> Bool {
        supportedAssets.contains(try Self.normalizedAssetIdentifier(asset))
    }

    public func validate() throws {
        try identity.validate()
        try requirePaymentField("adapterId", adapterId)
        guard !capabilities.isEmpty else {
            throw MeshKitValidationError.unsupportedCapability
        }
        guard !supportedExecutionKinds.isEmpty else {
            throw MeshKitValidationError.invalidPaymentExecution("supportedExecutionKinds")
        }
        guard !supportedAssets.isEmpty else {
            throw MeshKitValidationError.invalidPaymentExecution("supportedAssets")
        }
        guard !paymentOperations.isEmpty else {
            throw MeshKitValidationError.invalidPaymentExecution("paymentOperations")
        }
        for operation in paymentOperations {
            try operation.validate()
            guard supportedExecutionKinds.contains(operation.executionKind) else {
                throw MeshKitValidationError.invalidPaymentExecution("paymentOperations.executionKind")
            }
            guard supportedAssets.contains(operation.asset) else {
                throw MeshKitValidationError.invalidPaymentExecution("paymentOperations.asset")
            }
            guard capabilities.contains(operation.requiredCapability) else {
                throw MeshKitValidationError.invalidPaymentExecution("paymentOperations.requiredCapability")
            }
        }
        guard !statusValues.isEmpty else {
            throw MeshKitValidationError.invalidPaymentExecution("statusValues")
        }
    }

    private static func defaultPaymentOperations(
        supportedExecutionKinds: [MeshAgentWalletExecutionKind],
        supportedAssets: [String]
    ) throws -> [MeshPaymentOperationCapability] {
        try supportedExecutionKinds.flatMap { executionKind in
            try supportedAssets.map { asset in
                try MeshPaymentOperationCapability(
                    executionKind: executionKind,
                    asset: asset,
                    requiredCapability: paymentExecutionCapability(for: executionKind)
                )
            }
        }
    }

    private static func normalizedAssetIdentifier(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else {
            throw MeshKitValidationError.invalidPaymentExecution("supportedAssets")
        }
        try requirePaymentField("supportedAssets", normalized)
        return normalized
    }
}

public struct MeshPaymentOperationCapability: Codable, Equatable, Sendable {
    public let executionKind: MeshAgentWalletExecutionKind
    public let asset: String
    public let requiredCapability: MeshPaymentExecutorCapability
    public let amountRequired: Bool
    public let recipientRequired: Bool
    public let requestHashLinkageRequired: Bool
    public let anchoringReferenceRequired: Bool
    public let policyBindingRequired: Bool

    public init(
        executionKind: MeshAgentWalletExecutionKind,
        asset: String,
        requiredCapability: MeshPaymentExecutorCapability,
        amountRequired: Bool = true,
        recipientRequired: Bool = true,
        requestHashLinkageRequired: Bool = true,
        anchoringReferenceRequired: Bool = true,
        policyBindingRequired: Bool = true
    ) throws {
        self.executionKind = executionKind
        self.asset = try normalizedPaymentField("paymentOperation.asset", asset.uppercased())
        self.requiredCapability = requiredCapability
        self.amountRequired = amountRequired
        self.recipientRequired = recipientRequired
        self.requestHashLinkageRequired = requestHashLinkageRequired
        self.anchoringReferenceRequired = anchoringReferenceRequired
        self.policyBindingRequired = policyBindingRequired
        try validate()
    }

    public func validate() throws {
        try requirePaymentField("paymentOperation.asset", asset)
        guard requiredCapability == paymentExecutionCapability(for: executionKind) else {
            throw MeshKitValidationError.invalidPaymentExecution("paymentOperation.requiredCapability")
        }
        guard amountRequired else {
            throw MeshKitValidationError.invalidPaymentExecution("paymentOperation.amountRequired")
        }
        guard recipientRequired else {
            throw MeshKitValidationError.invalidPaymentExecution("paymentOperation.recipientRequired")
        }
        guard requestHashLinkageRequired else {
            throw MeshKitValidationError.invalidPaymentExecution("paymentOperation.requestHashLinkageRequired")
        }
        guard anchoringReferenceRequired else {
            throw MeshKitValidationError.invalidPaymentExecution("paymentOperation.anchoringReferenceRequired")
        }
        guard policyBindingRequired else {
            throw MeshKitValidationError.invalidPaymentExecution("paymentOperation.policyBindingRequired")
        }
    }

    fileprivate func normalized() throws -> MeshPaymentOperationCapability {
        try MeshPaymentOperationCapability(
            executionKind: executionKind,
            asset: asset,
            requiredCapability: requiredCapability,
            amountRequired: amountRequired,
            recipientRequired: recipientRequired,
            requestHashLinkageRequired: requestHashLinkageRequired,
            anchoringReferenceRequired: anchoringReferenceRequired,
            policyBindingRequired: policyBindingRequired
        )
    }
}

public struct MeshPaymentExecutorCapabilityInput: Codable, Equatable, Sendable {
    public let capability: MeshPaymentExecutorCapability
    public let asset: String
    public let amount: Decimal
    public let recipient: String
    public let requestHash: MeshPayloadHash
    public let requestHashLinkage: Bool

    public init(
        capability: MeshPaymentExecutorCapability,
        asset: String,
        amount: Decimal,
        recipient: String,
        requestHash: MeshPayloadHash,
        requestHashLinkage: Bool = true
    ) throws {
        self.capability = capability
        self.asset = try normalizedPaymentField("asset", asset.uppercased())
        self.amount = amount
        self.recipient = try normalizedPaymentField("recipient", recipient)
        self.requestHash = requestHash
        self.requestHashLinkage = requestHashLinkage
        try validate()
    }

    public init(intent: MeshPaymentExecutionIntent) throws {
        try self.init(
            capability: paymentExecutionCapability(for: intent.kind),
            asset: intent.asset,
            amount: intent.amount,
            recipient: intent.recipient,
            requestHash: intent.requestHash
        )
    }

    public init(paymentRequest: MeshPaymentExecutionRequest) throws {
        try self.init(intent: paymentRequest.executionIntent)
    }

    public func validate() throws {
        try requirePaymentField("asset", asset)
        guard amount > 0 else {
            throw MeshKitValidationError.invalidPaymentExecution("amount")
        }
        try requirePaymentField("recipient", recipient)
        try validatePaymentHash("requestHash", requestHash)
        guard requestHashLinkage else {
            throw MeshKitValidationError.invalidPaymentExecution("requestHashLinkage")
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            capability: try container.decode(MeshPaymentExecutorCapability.self, forKey: .capability),
            asset: try container.decode(String.self, forKey: .asset),
            amount: try container.decode(Decimal.self, forKey: .amount),
            recipient: try container.decode(String.self, forKey: .recipient),
            requestHash: try container.decode(MeshPayloadHash.self, forKey: .requestHash),
            requestHashLinkage: try container.decode(Bool.self, forKey: .requestHashLinkage)
        )
    }
}

public struct MeshPaymentExecutionIntent: Codable, Equatable, Sendable {
    public let kind: MeshAgentWalletExecutionKind
    public let asset: String
    public let amount: Decimal
    public let recipient: String
    public let requestHash: MeshPayloadHash
    public let requestNonce: String
    public let anchoringReference: MeshRequestAnchorIdentifier
    public let policyId: String
    public let policyHash: MeshPayloadHash
    public let paymentId: String?

    public init(
        kind: MeshAgentWalletExecutionKind,
        asset: String,
        amount: Decimal,
        recipient: String,
        requestHash: MeshPayloadHash,
        requestNonce: String,
        anchoringReference: MeshRequestAnchorIdentifier,
        policyId: String,
        policyHash: MeshPayloadHash,
        paymentId: String? = nil
    ) throws {
        self.kind = kind
        self.asset = try normalizedPaymentField("asset", asset.uppercased())
        self.amount = amount
        self.recipient = try normalizedPaymentField("recipient", recipient)
        self.requestHash = requestHash
        self.requestNonce = try normalizedPaymentField("requestNonce", requestNonce)
        self.anchoringReference = anchoringReference
        self.policyId = try normalizedPaymentField("policyId", policyId)
        self.policyHash = policyHash
        self.paymentId = try paymentId.map { try normalizedPaymentField("paymentId", $0) }
        try validate()
    }

    public init(paymentRequest: MeshPaymentExecutionRequest) throws {
        try self.init(
            kind: paymentRequest.executionRequest.kind,
            asset: paymentRequest.asset,
            amount: paymentRequest.amount,
            recipient: paymentRequest.recipient,
            requestHash: paymentRequest.requestHash,
            requestNonce: paymentRequest.executionRequest.requestAnchorMetadata.nonce,
            anchoringReference: paymentRequest.requestAnchor.identifier,
            policyId: paymentRequest.executionRequest.policyId,
            policyHash: paymentRequest.executionRequest.policyHash,
            paymentId: paymentRequest.paymentId
        )
    }

    public func validate() throws {
        try requirePaymentField("asset", asset)
        guard amount > 0 else {
            throw MeshKitValidationError.invalidPaymentExecution("amount")
        }
        try requirePaymentField("recipient", recipient)
        try validatePaymentHash("requestHash", requestHash)
        try requirePaymentField("requestNonce", requestNonce)
        try anchoringReference.validate()
        try requirePaymentField("policyId", policyId)
        try validatePaymentHash("policyHash", policyHash)
        if let paymentId {
            try requirePaymentField("paymentId", paymentId)
        }
    }
}

public struct MeshOKRWPaymentIntent: Codable, Equatable, Sendable {
    public static let asset = "OKRW"
    public let executionIntent: MeshPaymentExecutionIntent

    public init(executionIntent: MeshPaymentExecutionIntent) throws {
        guard executionIntent.kind == .payment else {
            throw MeshKitValidationError.invalidPaymentExecution("kind")
        }
        guard executionIntent.asset == Self.asset else {
            throw MeshKitValidationError.invalidPaymentExecution("asset")
        }
        self.executionIntent = executionIntent
        try validate()
    }

    public init(paymentRequest: MeshPaymentExecutionRequest) throws {
        try self.init(executionIntent: MeshPaymentExecutionIntent(paymentRequest: paymentRequest))
    }

    public func validate() throws {
        try executionIntent.validate()
        guard executionIntent.kind == .payment else {
            throw MeshKitValidationError.invalidPaymentExecution("kind")
        }
        guard executionIntent.asset == Self.asset else {
            throw MeshKitValidationError.invalidPaymentExecution("asset")
        }
    }
}

public struct MeshOKRWTransferIntent: Codable, Equatable, Sendable {
    public static let asset = "OKRW"
    public let executionIntent: MeshPaymentExecutionIntent

    public init(executionIntent: MeshPaymentExecutionIntent) throws {
        guard executionIntent.kind == .transfer else {
            throw MeshKitValidationError.invalidPaymentExecution("kind")
        }
        guard executionIntent.asset == Self.asset else {
            throw MeshKitValidationError.invalidPaymentExecution("asset")
        }
        self.executionIntent = executionIntent
        try validate()
    }

    public init(paymentRequest: MeshPaymentExecutionRequest) throws {
        try self.init(executionIntent: MeshPaymentExecutionIntent(paymentRequest: paymentRequest))
    }

    public func validate() throws {
        try executionIntent.validate()
        guard executionIntent.kind == .transfer else {
            throw MeshKitValidationError.invalidPaymentExecution("kind")
        }
        guard executionIntent.asset == Self.asset else {
            throw MeshKitValidationError.invalidPaymentExecution("asset")
        }
    }
}

public struct MeshPaymentExecutionRequest: Codable, Equatable, Sendable {
    public let paymentId: String
    public let authorizationDecision: MeshAgentWalletAuthorizationDecision
    public let requestAnchor: MeshRequestAnchor
    public let asset: String
    public let amount: Decimal
    public let recipient: String
    public let requestHash: MeshPayloadHash
    public let requestedAt: String

    public var executionRequest: MeshAgentWalletExecutionRequest {
        authorizationDecision.executionRequest
    }

    public var executionIntent: MeshPaymentExecutionIntent {
        get throws {
            try MeshPaymentExecutionIntent(paymentRequest: self)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case paymentId
        case authorizationDecision
        case requestAnchor
        case asset
        case amount
        case recipient
        case requestHash
        case requestedAt
    }

    public init(
        paymentId: String,
        authorizationDecision: MeshAgentWalletAuthorizationDecision,
        requestAnchor: MeshRequestAnchor,
        requestedAt: String
    ) throws {
        self.paymentId = try normalizedPaymentField("paymentId", paymentId)
        self.authorizationDecision = authorizationDecision
        self.requestAnchor = requestAnchor
        self.asset = try Self.assetIdentifier(from: authorizationDecision.executionRequest)
        self.amount = authorizationDecision.executionRequest.amount
        self.recipient = authorizationDecision.executionRequest.recipientAddress
        self.requestHash = authorizationDecision.executionRequest.requestAnchorMetadata.signedRequestHash
        self.requestedAt = try normalizedPaymentField("requestedAt", requestedAt)
        try validate()
    }

    public func validate() throws {
        try requirePaymentField("paymentId", paymentId)
        try authorizationDecision.validate()
        try authorizationDecision.validateExecutionAuthorizationBoundary()
        try requestAnchor.validate()
        try requirePaymentField("asset", asset)
        guard amount > 0 else {
            throw MeshKitValidationError.invalidPaymentExecution("amount")
        }
        try requirePaymentField("recipient", recipient)
        try validatePaymentHash("requestHash", requestHash)
        try requirePaymentField("requestedAt", requestedAt)
        guard requestAnchor.metadata == executionRequest.requestAnchorMetadata else {
            throw MeshKitValidationError.invalidPaymentExecution("requestAnchorMetadata")
        }
        guard asset == (try Self.assetIdentifier(from: executionRequest)) else {
            throw MeshKitValidationError.invalidPaymentExecution("asset")
        }
        guard amount == executionRequest.amount else {
            throw MeshKitValidationError.invalidPaymentExecution("amount")
        }
        guard recipient == executionRequest.recipientAddress else {
            throw MeshKitValidationError.invalidPaymentExecution("recipient")
        }
        guard requestHash == executionRequest.requestAnchorMetadata.signedRequestHash else {
            throw MeshKitValidationError.invalidPaymentExecution("requestHash")
        }
    }

    public func validate(originatingRequest: MeshRequest) throws {
        try validate()
        let expectedRequestHash = try MeshRequestAnchorCanonicalization.signedRequestHash(for: originatingRequest)
        guard requestHash == expectedRequestHash,
              executionRequest.requestAnchorMetadata.signedRequestHash == expectedRequestHash,
              requestAnchor.metadata.signedRequestHash == expectedRequestHash else {
            throw MeshKitValidationError.invalidPaymentExecution("requestHash")
        }
        try MeshRequestAnchorCanonicalization.validate(
            metadata: executionRequest.requestAnchorMetadata,
            boundTo: originatingRequest
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let paymentId = try container.decode(String.self, forKey: .paymentId)
        let authorizationDecision = try container.decode(MeshAgentWalletAuthorizationDecision.self, forKey: .authorizationDecision)
        let requestAnchor = try container.decode(MeshRequestAnchor.self, forKey: .requestAnchor)
        let executionRequest = authorizationDecision.executionRequest

        self.paymentId = try normalizedPaymentField("paymentId", paymentId)
        self.authorizationDecision = authorizationDecision
        self.requestAnchor = requestAnchor
        self.asset = try container.decodeIfPresent(String.self, forKey: .asset)
            ?? Self.assetIdentifier(from: executionRequest)
        self.amount = try container.decodeIfPresent(Decimal.self, forKey: .amount)
            ?? executionRequest.amount
        self.recipient = try container.decodeIfPresent(String.self, forKey: .recipient)
            ?? executionRequest.recipientAddress
        guard container.contains(.requestHash) else {
            throw MeshKitValidationError.invalidPaymentExecution("requestHash")
        }
        self.requestHash = try container.decode(MeshPayloadHash.self, forKey: .requestHash)
        self.requestedAt = try normalizedPaymentField("requestedAt", try container.decode(String.self, forKey: .requestedAt))
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(paymentId, forKey: .paymentId)
        try container.encode(authorizationDecision, forKey: .authorizationDecision)
        try container.encode(requestAnchor, forKey: .requestAnchor)
        try container.encode(asset, forKey: .asset)
        try container.encode(amount, forKey: .amount)
        try container.encode(recipient, forKey: .recipient)
        try container.encode(requestHash, forKey: .requestHash)
        try container.encode(requestedAt, forKey: .requestedAt)
    }

    private static func assetIdentifier(from executionRequest: MeshAgentWalletExecutionRequest) throws -> String {
        guard let asset = executionRequest.tokenSymbol ?? executionRequest.currencyCode else {
            throw MeshKitValidationError.invalidPaymentExecution("asset")
        }
        return try normalizedPaymentField("asset", asset)
    }
}

public extension MeshPaymentExecutionRequest {
    func signedMCPRequestAnchoringFields() throws -> MeshSignedMCPRequestAnchoringFields {
        try MeshSignedMCPRequestAnchoringFields(paymentRequest: self)
    }
}

public struct MeshPaymentExecutionResult: Codable, Equatable, Sendable {
    public let paymentId: String
    public let authorizationId: String
    public let identity: MeshChainProviderIdentity
    public let kind: MeshAgentWalletExecutionKind
    public let status: MeshPaymentExecutionStatus
    public let amount: Decimal
    public let currencyCode: String?
    public let tokenSymbol: String?
    public let recipientAddress: String
    public let requestAnchorIdentifier: MeshRequestAnchorIdentifier
    public let signedRequestHash: MeshPayloadHash
    public let transactionHash: String?
    public let explorerURL: URL?
    public let observedAt: String
    public let message: String?
    public let errorPayload: MeshPaymentExecutionErrorPayload?
    public let providerExtensions: [String: [String: String]]

    public var executionStatus: MeshPaymentExecutionStatus { status }
    public var requestHash: MeshPayloadHash { signedRequestHash }
    public var txHash: String? { transactionHash }

    private enum CodingKeys: String, CodingKey {
        case paymentId
        case authorizationId
        case identity
        case kind
        case status
        case executionStatus
        case amount
        case currencyCode
        case tokenSymbol
        case recipientAddress
        case requestAnchorIdentifier
        case requestHash
        case signedRequestHash
        case transactionHash
        case txHash
        case explorerURL
        case observedAt
        case message
        case errorPayload
        case providerExtensions
    }

    public init(
        request: MeshPaymentExecutionRequest,
        identity: MeshChainProviderIdentity,
        status: MeshPaymentExecutionStatus,
        transactionHash: String? = nil,
        explorerURL: URL? = nil,
        observedAt: String,
        message: String? = nil,
        errorPayload: MeshPaymentExecutionErrorPayload? = nil,
        providerExtensions: [String: [String: String]] = [:]
    ) throws {
        self.paymentId = request.paymentId
        self.authorizationId = request.authorizationDecision.authorizationId
        self.identity = identity
        self.kind = request.executionRequest.kind
        self.status = status
        self.amount = request.executionRequest.amount
        self.currencyCode = request.executionRequest.currencyCode
        self.tokenSymbol = request.executionRequest.tokenSymbol
        self.recipientAddress = request.executionRequest.recipientAddress
        self.requestAnchorIdentifier = request.requestAnchor.identifier
        self.signedRequestHash = request.executionRequest.requestAnchorMetadata.signedRequestHash
        self.transactionHash = try transactionHash.map { try normalizedPaymentField("transactionHash", $0) }
        if let explorerURL {
            self.explorerURL = explorerURL
        } else if let transactionHash = self.transactionHash {
            self.explorerURL = try? identity.explorerURL(transactionHash: transactionHash)
        } else {
            self.explorerURL = nil
        }
        self.observedAt = try normalizedPaymentField("observedAt", observedAt)
        self.message = try message.map { try normalizedPaymentField("message", $0) }
        self.errorPayload = try Self.normalizedErrorPayload(
            explicitPayload: errorPayload,
            status: status,
            message: self.message
        )
        self.providerExtensions = try Self.normalizedProviderExtensions(providerExtensions)
        try validate(authorizationStatus: request.authorizationDecision.status)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.paymentId = try normalizedPaymentField("paymentId", try container.decode(String.self, forKey: .paymentId))
        self.authorizationId = try normalizedPaymentField("authorizationId", try container.decode(String.self, forKey: .authorizationId))
        self.identity = try container.decode(MeshChainProviderIdentity.self, forKey: .identity)
        self.kind = try container.decode(MeshAgentWalletExecutionKind.self, forKey: .kind)

        let decodedStatus = try container.decode(MeshPaymentExecutionStatus.self, forKey: .status)
        if let executionStatus = try container.decodeIfPresent(MeshPaymentExecutionStatus.self, forKey: .executionStatus),
           executionStatus != decodedStatus {
            throw MeshKitValidationError.invalidPaymentExecution("executionStatus")
        }
        self.status = decodedStatus

        self.amount = try container.decode(Decimal.self, forKey: .amount)
        self.currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode)
        self.tokenSymbol = try container.decodeIfPresent(String.self, forKey: .tokenSymbol)
        self.recipientAddress = try normalizedPaymentField(
            "recipientAddress",
            try container.decode(String.self, forKey: .recipientAddress)
        )
        self.requestAnchorIdentifier = try container.decode(MeshRequestAnchorIdentifier.self, forKey: .requestAnchorIdentifier)
        let decodedRequestHash = try container.decodeIfPresent(MeshPayloadHash.self, forKey: .requestHash)
        let decodedSignedRequestHash = try container.decodeIfPresent(MeshPayloadHash.self, forKey: .signedRequestHash)
        guard let requestHash = decodedRequestHash ?? decodedSignedRequestHash else {
            throw MeshKitValidationError.invalidPaymentExecution("requestHash")
        }
        if let decodedRequestHash, let decodedSignedRequestHash, decodedRequestHash != decodedSignedRequestHash {
            throw MeshKitValidationError.invalidPaymentExecution("requestHash")
        }
        self.signedRequestHash = requestHash

        let decodedTransactionHash = try container.decodeIfPresent(String.self, forKey: .transactionHash)
        let decodedTxHash = try container.decodeIfPresent(String.self, forKey: .txHash)
        if let decodedTransactionHash, let decodedTxHash, decodedTransactionHash != decodedTxHash {
            throw MeshKitValidationError.invalidPaymentExecution("txHash")
        }
        self.transactionHash = try (decodedTransactionHash ?? decodedTxHash)
            .map { try normalizedPaymentField("transactionHash", $0) }

        if let explorerURL = try container.decodeIfPresent(URL.self, forKey: .explorerURL) {
            self.explorerURL = explorerURL
        } else if let transactionHash = self.transactionHash {
            self.explorerURL = try? identity.explorerURL(transactionHash: transactionHash)
        } else {
            self.explorerURL = nil
        }
        self.observedAt = try normalizedPaymentField("observedAt", try container.decode(String.self, forKey: .observedAt))
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
            .map { try normalizedPaymentField("message", $0) }
        self.errorPayload = try Self.normalizedErrorPayload(
            explicitPayload: try container.decodeIfPresent(MeshPaymentExecutionErrorPayload.self, forKey: .errorPayload),
            status: decodedStatus,
            message: self.message
        )
        self.providerExtensions = try Self.normalizedProviderExtensions(
            try container.decodeIfPresent([String: [String: String]].self, forKey: .providerExtensions) ?? [:]
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(paymentId, forKey: .paymentId)
        try container.encode(authorizationId, forKey: .authorizationId)
        try container.encode(identity, forKey: .identity)
        try container.encode(kind, forKey: .kind)
        try container.encode(status, forKey: .status)
        try container.encode(executionStatus, forKey: .executionStatus)
        try container.encode(amount, forKey: .amount)
        try container.encodeIfPresent(currencyCode, forKey: .currencyCode)
        try container.encodeIfPresent(tokenSymbol, forKey: .tokenSymbol)
        try container.encode(recipientAddress, forKey: .recipientAddress)
        try container.encode(requestAnchorIdentifier, forKey: .requestAnchorIdentifier)
        try container.encode(requestHash, forKey: .requestHash)
        try container.encode(signedRequestHash, forKey: .signedRequestHash)
        try container.encodeIfPresent(transactionHash, forKey: .transactionHash)
        try container.encodeIfPresent(txHash, forKey: .txHash)
        try container.encodeIfPresent(explorerURL, forKey: .explorerURL)
        try container.encode(observedAt, forKey: .observedAt)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(errorPayload, forKey: .errorPayload)
        if !providerExtensions.isEmpty {
            try container.encode(providerExtensions, forKey: .providerExtensions)
        }
    }

    public func validate() throws {
        try validate(authorizationStatus: nil)
    }

    public func validate(originatingSignedRequestHash: MeshPayloadHash) throws {
        try validate()
        try validatePaymentHash("requestHash", originatingSignedRequestHash)
        guard signedRequestHash == originatingSignedRequestHash else {
            throw MeshKitValidationError.invalidPaymentExecution("requestHash")
        }
    }

    private func validate(authorizationStatus: MeshAgentWalletAuthorizationStatus?) throws {
        try requirePaymentField("paymentId", paymentId)
        try requirePaymentField("authorizationId", authorizationId)
        try identity.validate()
        guard amount > 0 else {
            throw MeshKitValidationError.invalidPaymentExecution("amount")
        }
        guard currencyCode != nil || tokenSymbol != nil else {
            throw MeshKitValidationError.invalidPaymentExecution("currencyCode")
        }
        if let currencyCode {
            try requirePaymentField("currencyCode", currencyCode)
        }
        if let tokenSymbol {
            try requirePaymentField("tokenSymbol", tokenSymbol)
        }
        try requirePaymentField("recipientAddress", recipientAddress)
        try requestAnchorIdentifier.validate()
        try validatePaymentHash("signedRequestHash", signedRequestHash)
        if let transactionHash {
            try requirePaymentField("transactionHash", transactionHash)
        }
        if let explorerURL {
            try MeshChainProviderIdentity.validateNetworkURL("explorerURL", explorerURL)
        }
        try requirePaymentField("observedAt", observedAt)
        if let message {
            try requirePaymentField("message", message)
        }
        try errorPayload?.validate()
        try Self.validateProviderExtensions(providerExtensions)

        if status == .confirmed, transactionHash == nil {
            throw MeshKitValidationError.invalidPaymentExecution("transactionHash")
        }
        if status == .policyDenied, transactionHash != nil {
            throw MeshKitValidationError.invalidPaymentExecution("transactionHash")
        }
        switch status {
        case .failed, .policyDenied:
            guard errorPayload != nil else {
                throw MeshKitValidationError.invalidPaymentExecution("errorPayload")
            }
        case .pending, .confirmed:
            guard errorPayload == nil else {
                throw MeshKitValidationError.invalidPaymentExecution("errorPayload")
            }
        }
        if let authorizationStatus {
            switch (authorizationStatus, status) {
            case (.denied, .pending), (.denied, .confirmed):
                throw MeshKitValidationError.invalidPaymentExecution("status")
            default:
                break
            }
        }
    }

    private static func normalizedErrorPayload(
        explicitPayload: MeshPaymentExecutionErrorPayload?,
        status: MeshPaymentExecutionStatus,
        message: String?
    ) throws -> MeshPaymentExecutionErrorPayload? {
        if let explicitPayload {
            try explicitPayload.validate()
            return explicitPayload
        }
        switch status {
        case .failed:
            return try MeshPaymentExecutionErrorPayload(
                code: "payment_execution_failed",
                message: message ?? "payment execution failed"
            )
        case .policyDenied:
            return try MeshPaymentExecutionErrorPayload(
                code: "policy_denied",
                message: message ?? "policy denied"
            )
        case .pending, .confirmed:
            return nil
        }
    }

    private static func normalizedProviderExtensions(
        _ providerExtensions: [String: [String: String]]
    ) throws -> [String: [String: String]] {
        var normalized: [String: [String: String]] = [:]
        for (provider, fields) in providerExtensions {
            let normalizedProvider = try normalizedPaymentIdentifier("providerExtensions.provider", provider)
            guard !fields.isEmpty else {
                throw MeshKitValidationError.invalidPaymentExecution("providerExtensions.\(normalizedProvider)")
            }
            var normalizedFields: [String: String] = [:]
            for (key, value) in fields {
                let normalizedKey = try normalizedPaymentField("providerExtensions.\(normalizedProvider).key", key)
                normalizedFields[normalizedKey] = try normalizedPaymentField(
                    "providerExtensions.\(normalizedProvider).\(normalizedKey)",
                    value
                )
            }
            normalized[normalizedProvider] = normalizedFields
        }
        return normalized
    }

    private static func normalizedPaymentIdentifier(_ field: String, _ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { throw MeshKitValidationError.invalidPaymentExecution(field) }
        try requirePaymentField(field, normalized)
        return normalized
    }

    private static func validateProviderExtensions(
        _ providerExtensions: [String: [String: String]]
    ) throws {
        _ = try normalizedProviderExtensions(providerExtensions)
    }
}

public protocol MeshPaymentExecutor: Sendable {
    var identity: MeshChainProviderIdentity { get }
    var capabilities: [MeshPaymentExecutorCapability] { get }

    func loadPaymentExecutorConfiguration() throws -> MeshPaymentExecutorConfiguration
    func executePayment(_ request: MeshPaymentExecutionRequest, submittedAt: String) async throws -> MeshPaymentExecutionResult
    func paymentExecutionStatus(paymentId: String, checkedAt: String) async throws -> MeshPaymentExecutionResult
}

public extension MeshPaymentExecutor {
    func providerNeutralCapabilityError(
        for error: Error,
        capability: MeshPaymentExecutorCapability
    ) throws -> MeshPaymentExecutorCapabilityError {
        try MeshPaymentExecutorCapabilityError.providerNeutral(error, capability: capability)
    }

    func executePaymentWithProviderNeutralErrors(
        _ request: MeshPaymentExecutionRequest,
        submittedAt: String
    ) async throws -> MeshPaymentExecutionResult {
        do {
            return try await executePayment(request, submittedAt: submittedAt)
        } catch {
            let capability = paymentExecutionCapability(for: request.executionRequest.kind)
            throw try providerNeutralCapabilityError(for: error, capability: capability)
        }
    }

    func paymentExecutionStatusWithProviderNeutralErrors(
        paymentId: String,
        checkedAt: String
    ) async throws -> MeshPaymentExecutionResult {
        do {
            return try await paymentExecutionStatus(paymentId: paymentId, checkedAt: checkedAt)
        } catch {
            throw try providerNeutralCapabilityError(for: error, capability: .lookupExecutionStatus)
        }
    }

    func executePayment(
        _ request: MeshPaymentExecutionRequest,
        originatingRequest: MeshRequest,
        submittedAt: String
    ) async throws -> MeshPaymentExecutionResult {
        try request.validate(originatingRequest: originatingRequest)
        let result = try await executePaymentWithProviderNeutralErrors(request, submittedAt: submittedAt)
        try result.validate(originatingSignedRequestHash: request.requestHash)
        return result
    }

    func executeOKRWPaymentIntent(
        _ intent: MeshOKRWPaymentIntent,
        request: MeshPaymentExecutionRequest,
        submittedAt: String
    ) async throws -> MeshPaymentExecutionResult {
        try await executeOKRWIntent(intent.executionIntent, request: request, submittedAt: submittedAt)
    }

    func executeOKRWTransferIntent(
        _ intent: MeshOKRWTransferIntent,
        request: MeshPaymentExecutionRequest,
        submittedAt: String
    ) async throws -> MeshPaymentExecutionResult {
        try await executeOKRWIntent(intent.executionIntent, request: request, submittedAt: submittedAt)
    }

    private func executeOKRWIntent(
        _ intent: MeshPaymentExecutionIntent,
        request: MeshPaymentExecutionRequest,
        submittedAt: String
    ) async throws -> MeshPaymentExecutionResult {
        try intent.validate()
        try request.validate()
        guard intent == (try request.executionIntent) else {
            throw MeshKitValidationError.invalidPaymentExecution("executionIntent")
        }

        let result = try await executePaymentWithProviderNeutralErrors(request, submittedAt: submittedAt)
        try result.validate(originatingSignedRequestHash: request.requestHash)
        return result
    }
}

public struct MeshDemoPaymentExecutor: MeshPaymentExecutor {
    public let identity: MeshChainProviderIdentity
    public let capabilities: [MeshPaymentExecutorCapability]
    public let executionStatus: MeshPaymentExecutionStatus
    public let transactionHash: String?
    public let message: String?

    public init(
        identity: MeshChainProviderIdentity,
        capabilities: [MeshPaymentExecutorCapability] = [.executePayment, .executeTransfer],
        executionStatus: MeshPaymentExecutionStatus,
        transactionHash: String? = nil,
        message: String? = nil
    ) throws {
        self.identity = identity
        self.capabilities = Array(Set(capabilities)).sorted()
        self.executionStatus = executionStatus
        self.transactionHash = try transactionHash.map { try normalizedPaymentField("transactionHash", $0) }
        self.message = try message.map { try normalizedPaymentField("message", $0) }
        try loadPaymentExecutorConfiguration().validate()
    }

    public func loadPaymentExecutorConfiguration() throws -> MeshPaymentExecutorConfiguration {
        try MeshPaymentExecutorConfiguration(identity: identity, capabilities: capabilities)
    }

    public func executePayment(
        _ request: MeshPaymentExecutionRequest,
        submittedAt: String
    ) async throws -> MeshPaymentExecutionResult {
        try request.validate()
        let requiredCapability: MeshPaymentExecutorCapability = request.executionRequest.kind == .payment
            ? .executePayment
            : .executeTransfer
        try loadPaymentExecutorConfiguration().require(requiredCapability)

        guard request.authorizationDecision.status == .approved else {
            return try MeshPaymentExecutionResult(
                request: request,
                identity: identity,
                status: .policyDenied,
                observedAt: submittedAt,
                message: request.authorizationDecision.reason
            )
        }

        let normalizedTransactionHash = try transactionHashForApprovedExecution(request: request)
        return try MeshPaymentExecutionResult(
            request: request,
            identity: identity,
            status: executionStatus,
            transactionHash: normalizedTransactionHash,
            observedAt: submittedAt,
            message: messageForApprovedExecution
        )
    }

    public func paymentExecutionStatus(paymentId: String, checkedAt: String) async throws -> MeshPaymentExecutionResult {
        _ = try normalizedPaymentField("paymentId", paymentId)
        _ = try normalizedPaymentField("checkedAt", checkedAt)
        try loadPaymentExecutorConfiguration().require(.lookupExecutionStatus)
        throw MeshKitValidationError.invalidPaymentExecution("paymentId")
    }

    private func transactionHashForApprovedExecution(request: MeshPaymentExecutionRequest) throws -> String? {
        switch executionStatus {
        case .confirmed:
            return transactionHash ?? Self.deterministicTransactionHash(
                paymentId: request.paymentId,
                signedRequestHash: request.executionRequest.requestAnchorMetadata.signedRequestHash
            )
        case .pending, .failed:
            return transactionHash
        case .policyDenied:
            return nil
        }
    }

    private var messageForApprovedExecution: String? {
        if let message {
            return message
        }
        switch executionStatus {
        case .failed:
            return "demo payment execution failed"
        default:
            return nil
        }
    }

    private static func deterministicTransactionHash(
        paymentId: String,
        signedRequestHash: MeshPayloadHash
    ) -> String {
        let data = Data("\(paymentId):\(signedRequestHash.algorithm):\(signedRequestHash.value)".utf8)
        let digest = SHA256.hash(data: data)
        return "0x" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

public struct MeshMarooTestnetPaymentExecutionProviderInput: Codable, Equatable, Sendable {
    public static let version = "meshkit-maroo-okrw-payment-provider-input/v1"

    public let version: String
    public let providerMetadata: MeshChainProviderMetadata
    public let executionLinkPayload: MeshMarooTestnetExecutionLinkPayload
    public let paymentRequest: MeshPaymentExecutionRequest
    public let submittedAt: String
    public let canonicalString: String

    public init(
        paymentRequest: MeshPaymentExecutionRequest,
        providerIdentity: MeshChainProviderIdentity,
        submittedAt: String,
        version: String = MeshMarooTestnetPaymentExecutionProviderInput.version
    ) throws {
        self.version = try normalizedPaymentField("version", version)
        self.providerMetadata = providerIdentity.metadata
        self.executionLinkPayload = try MeshMarooTestnetExecutionLinkPayload(
            paymentRequest: paymentRequest,
            providerIdentity: providerIdentity,
            submittedAt: submittedAt
        )
        self.paymentRequest = paymentRequest
        self.submittedAt = try normalizedPaymentField("submittedAt", submittedAt)
        self.canonicalString = try Self.makeCanonicalString(
            version: self.version,
            providerMetadata: self.providerMetadata,
            executionLinkPayload: self.executionLinkPayload,
            paymentRequest: paymentRequest,
            submittedAt: self.submittedAt
        )
        try validate(providerIdentity: providerIdentity)
    }

    public func validate(providerIdentity: MeshChainProviderIdentity) throws {
        try validate()
        try providerIdentity.validate()
        guard providerMetadata == providerIdentity.metadata else {
            throw MeshKitValidationError.signatureMismatch("payment execution provider metadata mismatch")
        }
        try executionLinkPayload.validate(paymentRequest: paymentRequest, providerIdentity: providerIdentity)
    }

    public func validate() throws {
        guard version == Self.version else {
            throw MeshKitValidationError.invalidPaymentExecution("version")
        }
        try providerMetadata.validate()
        try executionLinkPayload.validate()
        try paymentRequest.validate()
        guard executionLinkPayload.providerMetadata == providerMetadata else {
            throw MeshKitValidationError.signatureMismatch("execution link provider metadata mismatch")
        }
        try executionLinkPayload.validate(paymentRequest: paymentRequest)
        try requirePaymentField("submittedAt", submittedAt)
        let expectedCanonicalString = try Self.makeCanonicalString(
            version: version,
            providerMetadata: providerMetadata,
            executionLinkPayload: executionLinkPayload,
            paymentRequest: paymentRequest,
            submittedAt: submittedAt
        )
        guard canonicalString == expectedCanonicalString else {
            throw MeshKitValidationError.signatureMismatch("payment execution provider canonical input mismatch")
        }
    }

    public var data: Data {
        Data(canonicalString.utf8)
    }

    public func sha256Hash() -> MeshPayloadHash {
        let digest = SHA256.hash(data: data)
        return MeshPayloadHash(value: digest.map { String(format: "%02x", $0) }.joined())
    }

    private static func makeCanonicalString(
        version: String,
        providerMetadata: MeshChainProviderMetadata,
        executionLinkPayload: MeshMarooTestnetExecutionLinkPayload,
        paymentRequest: MeshPaymentExecutionRequest,
        submittedAt: String
    ) throws -> String {
        try providerMetadata.validate()
        try executionLinkPayload.validate(paymentRequest: paymentRequest)
        try paymentRequest.validate()
        try requirePaymentField("submittedAt", submittedAt)

        return [
            version,
            "provider=\(providerMetadata.provider)",
            "network=\(providerMetadata.network)",
            "chainId=\(providerMetadata.chainId)",
            "executionLinkHashAlgorithm=\(executionLinkPayload.executionLinkHash.algorithm.lowercased())",
            "executionLinkHashValue=\(executionLinkPayload.executionLinkHash.value.lowercased())",
            "executionLinkPayload=\(executionLinkPayload.canonicalString)",
            "submittedAt=\(submittedAt)"
        ].joined(separator: "\n")
    }
}

public struct MeshMarooTestnetOKRWExecutionAnchorMetadata: Codable, Equatable, Sendable {
    public let signedMCPRequestHash: MeshPayloadHash
    public let requestNonce: String
    public let anchoringReference: String
    public let anchorTransactionHash: String?
    public let policyId: String
    public let policyHash: MeshPayloadHash

    private enum CodingKeys: String, CodingKey {
        case signedMCPRequestHash = "signed_mcp_request_hash"
        case requestNonce = "request_nonce"
        case anchoringReference = "anchoring_reference"
        case anchorTransactionHash = "anchor_tx_hash"
        case policyId = "policy_id"
        case policyHash = "policy_hash"
    }

    public init(
        signedMCPRequestHash: MeshPayloadHash,
        requestNonce: String,
        anchoringReference: String,
        anchorTransactionHash: String? = nil,
        policyId: String,
        policyHash: MeshPayloadHash
    ) throws {
        self.signedMCPRequestHash = signedMCPRequestHash
        self.requestNonce = try normalizedPaymentField("anchorMetadata.requestNonce", requestNonce)
        self.anchoringReference = try normalizedPaymentField("anchorMetadata.anchoringReference", anchoringReference)
        self.anchorTransactionHash = try anchorTransactionHash.map {
            try normalizedPaymentField("anchorMetadata.anchorTransactionHash", $0)
        }
        self.policyId = try normalizedPaymentField("anchorMetadata.policyId", policyId)
        self.policyHash = policyHash
        try validate()
    }

    public init(link: MeshMarooTestnetExecutionLinkPayload) throws {
        try self.init(
            signedMCPRequestHash: link.signedRequestHash,
            requestNonce: link.requestNonce,
            anchoringReference: link.anchoringReference.anchorId,
            anchorTransactionHash: link.anchoringReference.transactionHash,
            policyId: link.policyId,
            policyHash: link.policyHash
        )
    }

    public func validate() throws {
        try validatePaymentHash("anchorMetadata.signedMCPRequestHash", signedMCPRequestHash)
        try requirePaymentField("anchorMetadata.requestNonce", requestNonce)
        try requirePaymentField("anchorMetadata.anchoringReference", anchoringReference)
        if let anchorTransactionHash {
            try requirePaymentField("anchorMetadata.anchorTransactionHash", anchorTransactionHash)
        }
        try requirePaymentField("anchorMetadata.policyId", policyId)
        try validatePaymentHash("anchorMetadata.policyHash", policyHash)
    }
}

public struct MeshMarooTestnetOKRWExecutionTransactionRequest: Codable, Equatable, Sendable {
    public static let version = "maroo-testnet-okrw-execution/v1"
    public static let requestType = "meshkit_okrw_execution"

    public let version: String
    public let requestType: String
    public let provider: String
    public let network: String
    public let chainId: String
    public let adapterId: String
    public let executionLinkIdentity: String
    public let executionLinkHash: MeshPayloadHash
    public let paymentId: String
    public let authorizationId: String
    public let authorizationStatus: MeshAgentWalletAuthorizationStatus
    public let delegatedWalletAddress: String
    public let executionId: String
    public let executionKind: MeshAgentWalletExecutionKind
    public let asset: String
    public let amount: Decimal
    public let recipientAddress: String
    public let memo: String
    public let anchorMetadata: MeshMarooTestnetOKRWExecutionAnchorMetadata
    public let requestId: String
    public let requestNonce: String
    public let callerBundleId: String
    public let targetBundleId: String
    public let capabilityId: String
    public let payloadHash: MeshPayloadHash
    public let signedMCPRequestHash: MeshPayloadHash
    public let anchoringReference: String
    public let anchorTransactionHash: String?
    public let policyId: String
    public let policyHash: MeshPayloadHash
    public let submittedAt: String

    private enum CodingKeys: String, CodingKey {
        case version = "schema_version"
        case requestType = "request_type"
        case provider
        case network
        case chainId = "chain_id"
        case adapterId = "adapter_id"
        case executionLinkIdentity = "execution_link_identity"
        case executionLinkHash = "execution_link_hash"
        case paymentId = "payment_id"
        case authorizationId = "authorization_id"
        case authorizationStatus = "authorization_status"
        case delegatedWalletAddress = "delegated_wallet_address"
        case executionId = "execution_id"
        case executionKind = "execution_kind"
        case asset
        case amount
        case recipientAddress = "recipient_address"
        case memo
        case anchorMetadata = "anchor_metadata"
        case requestId = "request_id"
        case requestNonce = "request_nonce"
        case callerBundleId = "caller_bundle_id"
        case targetBundleId = "target_bundle_id"
        case capabilityId = "capability_id"
        case payloadHash = "payload_hash"
        case signedMCPRequestHash = "signed_mcp_request_hash"
        case anchoringReference = "anchoring_reference"
        case anchorTransactionHash = "anchor_tx_hash"
        case policyId = "policy_id"
        case policyHash = "policy_hash"
        case submittedAt = "submitted_at"
    }

    public init(
        providerMetadata: MeshChainProviderMetadata,
        adapterId: String,
        executionLinkIdentity: String,
        executionLinkHash: MeshPayloadHash,
        paymentId: String,
        authorizationId: String,
        authorizationStatus: MeshAgentWalletAuthorizationStatus,
        delegatedWalletAddress: String,
        executionId: String,
        executionKind: MeshAgentWalletExecutionKind,
        asset: String,
        amount: Decimal,
        recipientAddress: String,
        memo: String,
        anchorMetadata: MeshMarooTestnetOKRWExecutionAnchorMetadata,
        requestId: String,
        requestNonce: String,
        callerBundleId: String,
        targetBundleId: String,
        capabilityId: String,
        payloadHash: MeshPayloadHash,
        signedMCPRequestHash: MeshPayloadHash,
        anchoringReference: String,
        anchorTransactionHash: String? = nil,
        policyId: String,
        policyHash: MeshPayloadHash,
        submittedAt: String,
        version: String = MeshMarooTestnetOKRWExecutionTransactionRequest.version,
        requestType: String = MeshMarooTestnetOKRWExecutionTransactionRequest.requestType
    ) throws {
        self.version = try normalizedPaymentField("version", version)
        self.requestType = try normalizedPaymentField("requestType", requestType)
        self.provider = providerMetadata.provider
        self.network = providerMetadata.network
        self.chainId = providerMetadata.chainId
        self.adapterId = try normalizedPaymentIdentifier("adapterId", adapterId)
        self.executionLinkIdentity = try normalizedPaymentField("executionLinkIdentity", executionLinkIdentity)
        self.executionLinkHash = executionLinkHash
        self.paymentId = try normalizedPaymentField("paymentId", paymentId)
        self.authorizationId = try normalizedPaymentField("authorizationId", authorizationId)
        self.authorizationStatus = authorizationStatus
        self.delegatedWalletAddress = try normalizedPaymentField("delegatedWalletAddress", delegatedWalletAddress)
        self.executionId = try normalizedPaymentField("executionId", executionId)
        self.executionKind = executionKind
        self.asset = try normalizedPaymentField("asset", asset.uppercased())
        self.amount = amount
        self.recipientAddress = try normalizedPaymentField("recipientAddress", recipientAddress)
        self.memo = try normalizedPaymentField("memo", memo)
        self.anchorMetadata = anchorMetadata
        self.requestId = try normalizedPaymentField("requestId", requestId)
        self.requestNonce = try normalizedPaymentField("requestNonce", requestNonce)
        self.callerBundleId = try normalizedPaymentField("callerBundleId", callerBundleId)
        self.targetBundleId = try normalizedPaymentField("targetBundleId", targetBundleId)
        self.capabilityId = try normalizedPaymentField("capabilityId", capabilityId)
        self.payloadHash = payloadHash
        self.signedMCPRequestHash = signedMCPRequestHash
        self.anchoringReference = try normalizedPaymentField("anchoringReference", anchoringReference)
        self.anchorTransactionHash = try anchorTransactionHash.map { try normalizedPaymentField("anchorTransactionHash", $0) }
        self.policyId = try normalizedPaymentField("policyId", policyId)
        self.policyHash = policyHash
        self.submittedAt = try normalizedPaymentField("submittedAt", submittedAt)
        try validate(providerMetadata: providerMetadata)
    }

    public func validate(providerMetadata expectedProviderMetadata: MeshChainProviderMetadata? = nil) throws {
        guard version == Self.version else {
            throw MeshKitValidationError.invalidPaymentExecution("version")
        }
        guard requestType == Self.requestType else {
            throw MeshKitValidationError.invalidPaymentExecution("requestType")
        }
        let providerMetadata = try MeshChainProviderMetadata(provider: provider, network: network, chainId: chainId)
        if let expectedProviderMetadata, providerMetadata != expectedProviderMetadata {
            throw MeshKitValidationError.signatureMismatch("maroo OKRW execution provider metadata mismatch")
        }
        try requirePaymentField("adapterId", adapterId)
        try requirePaymentField("executionLinkIdentity", executionLinkIdentity)
        try validatePaymentHash("executionLinkHash", executionLinkHash)
        try requirePaymentField("paymentId", paymentId)
        try requirePaymentField("authorizationId", authorizationId)
        try requirePaymentField("delegatedWalletAddress", delegatedWalletAddress)
        try requirePaymentField("executionId", executionId)
        guard amount > 0 else {
            throw MeshKitValidationError.invalidPaymentExecution("amount")
        }
        try requirePaymentField("asset", asset)
        try requirePaymentField("recipientAddress", recipientAddress)
        try requirePaymentField("memo", memo)
        try anchorMetadata.validate()
        try requirePaymentField("requestId", requestId)
        try requirePaymentField("requestNonce", requestNonce)
        try requirePaymentField("callerBundleId", callerBundleId)
        try requirePaymentField("targetBundleId", targetBundleId)
        try requirePaymentField("capabilityId", capabilityId)
        try validatePaymentHash("payloadHash", payloadHash)
        try validatePaymentHash("signedMCPRequestHash", signedMCPRequestHash)
        try requirePaymentField("anchoringReference", anchoringReference)
        if let anchorTransactionHash {
            try requirePaymentField("anchorTransactionHash", anchorTransactionHash)
        }
        try requirePaymentField("policyId", policyId)
        try validatePaymentHash("policyHash", policyHash)
        try requirePaymentField("submittedAt", submittedAt)
        guard anchorMetadata.signedMCPRequestHash == signedMCPRequestHash,
              anchorMetadata.requestNonce == requestNonce,
              anchorMetadata.anchoringReference == anchoringReference,
              anchorMetadata.anchorTransactionHash == anchorTransactionHash,
              anchorMetadata.policyId == policyId,
              anchorMetadata.policyHash == policyHash else {
            throw MeshKitValidationError.signatureMismatch("maroo OKRW execution anchor metadata mismatch")
        }
    }
}

public enum MeshMarooTestnetOKRWExecutionSerializer {
    public static func transactionRequest(
        from input: MeshMarooTestnetPaymentExecutionProviderInput
    ) throws -> MeshMarooTestnetOKRWExecutionTransactionRequest {
        try input.validate()
        let link = input.executionLinkPayload
        let executionRequest = input.paymentRequest.executionRequest
        return try MeshMarooTestnetOKRWExecutionTransactionRequest(
            providerMetadata: input.providerMetadata,
            adapterId: link.adapterId,
            executionLinkIdentity: executionLinkIdentity(for: link),
            executionLinkHash: link.executionLinkHash,
            paymentId: link.paymentId,
            authorizationId: link.authorizationId,
            authorizationStatus: link.authorizationStatus,
            delegatedWalletAddress: input.paymentRequest.authorizationDecision.walletIdentity.walletAddress,
            executionId: link.executionId,
            executionKind: link.executionKind,
            asset: link.asset,
            amount: link.amount,
            recipientAddress: link.recipient,
            memo: try memo(for: link),
            anchorMetadata: try MeshMarooTestnetOKRWExecutionAnchorMetadata(link: link),
            requestId: link.requestId,
            requestNonce: link.requestNonce,
            callerBundleId: link.callerBundleId,
            targetBundleId: link.targetBundleId,
            capabilityId: link.capabilityId,
            payloadHash: link.payloadHash,
            signedMCPRequestHash: link.signedRequestHash,
            anchoringReference: link.anchoringReference.anchorId,
            anchorTransactionHash: link.anchoringReference.transactionHash,
            policyId: executionRequest.policyId,
            policyHash: executionRequest.policyHash,
            submittedAt: input.submittedAt
        )
    }

    public static func executionLinkIdentity(
        for payload: MeshMarooTestnetExecutionLinkPayload
    ) throws -> String {
        try payload.validate()
        return [
            payload.version,
            payload.paymentId,
            payload.executionId,
            payload.executionKind.rawValue,
            payload.requestNonce,
            payload.policyId
        ].joined(separator: ":")
    }

    public static func memo(
        for payload: MeshMarooTestnetExecutionLinkPayload
    ) throws -> String {
        try payload.validate()
        return [
            "MeshKit",
            "MCP",
            payload.executionKind.rawValue,
            payload.asset,
            payload.requestNonce,
            payload.anchoringReference.anchorId
        ].joined(separator: "|")
    }
}

public struct MeshMarooTestnetExecutionLinkPayload: Codable, Equatable, Sendable {
    public static let version = "meshkit-maroo-execution-link/v1"

    public let version: String
    public let providerMetadata: MeshChainProviderMetadata
    public let adapterId: String
    public let paymentId: String
    public let authorizationId: String
    public let authorizationStatus: MeshAgentWalletAuthorizationStatus
    public let executionId: String
    public let executionKind: MeshAgentWalletExecutionKind
    public let asset: String
    public let amount: Decimal
    public let recipient: String
    public let requestId: String
    public let requestNonce: String
    public let callerBundleId: String
    public let targetBundleId: String
    public let capabilityId: String
    public let payloadHash: MeshPayloadHash
    public let signedRequestHash: MeshPayloadHash
    public let anchoringReference: MeshRequestAnchorIdentifier
    public let policyId: String
    public let policyHash: MeshPayloadHash
    public let submittedAt: String
    public let canonicalString: String

    public var executionLinkHash: MeshPayloadHash {
        let digest = SHA256.hash(data: Data(canonicalString.utf8))
        return MeshPayloadHash(value: digest.map { String(format: "%02x", $0) }.joined())
    }

    public init(
        paymentRequest: MeshPaymentExecutionRequest,
        providerIdentity: MeshChainProviderIdentity,
        adapterId: String = MeshMarooTestnetPaymentExecutorAdapter.adapterId,
        submittedAt: String,
        version: String = MeshMarooTestnetExecutionLinkPayload.version
    ) throws {
        try paymentRequest.validate()
        try providerIdentity.validate()
        let anchorMetadata = paymentRequest.requestAnchor.metadata
        let executionRequest = paymentRequest.executionRequest

        self.version = try normalizedPaymentField("version", version)
        self.providerMetadata = providerIdentity.metadata
        self.adapterId = try normalizedPaymentIdentifier("adapterId", adapterId)
        self.paymentId = paymentRequest.paymentId
        self.authorizationId = paymentRequest.authorizationDecision.authorizationId
        self.authorizationStatus = paymentRequest.authorizationDecision.status
        self.executionId = executionRequest.executionId
        self.executionKind = executionRequest.kind
        self.asset = try normalizedPaymentField("asset", paymentRequest.asset.uppercased())
        self.amount = paymentRequest.amount
        self.recipient = paymentRequest.recipient
        self.requestId = anchorMetadata.requestId
        self.requestNonce = anchorMetadata.nonce
        self.callerBundleId = anchorMetadata.callerBundleId
        self.targetBundleId = anchorMetadata.targetBundleId
        self.capabilityId = anchorMetadata.capabilityId
        self.payloadHash = anchorMetadata.payloadHash
        self.signedRequestHash = anchorMetadata.signedRequestHash
        self.anchoringReference = paymentRequest.requestAnchor.identifier
        self.policyId = executionRequest.policyId
        self.policyHash = executionRequest.policyHash
        self.submittedAt = try normalizedPaymentField("submittedAt", submittedAt)
        self.canonicalString = try Self.makeCanonicalString(
            version: self.version,
            providerMetadata: self.providerMetadata,
            adapterId: self.adapterId,
            paymentId: self.paymentId,
            authorizationId: self.authorizationId,
            authorizationStatus: self.authorizationStatus,
            executionId: self.executionId,
            executionKind: self.executionKind,
            asset: self.asset,
            amount: self.amount,
            recipient: self.recipient,
            requestId: self.requestId,
            requestNonce: self.requestNonce,
            callerBundleId: self.callerBundleId,
            targetBundleId: self.targetBundleId,
            capabilityId: self.capabilityId,
            payloadHash: self.payloadHash,
            signedRequestHash: self.signedRequestHash,
            anchoringReference: self.anchoringReference,
            policyId: self.policyId,
            policyHash: self.policyHash,
            submittedAt: self.submittedAt
        )
        try validate(paymentRequest: paymentRequest, providerIdentity: providerIdentity)
    }

    public func validate(providerIdentity: MeshChainProviderIdentity) throws {
        try validate()
        try providerIdentity.validate()
        guard providerMetadata == providerIdentity.metadata,
              anchoringReference.identity.metadata == providerIdentity.metadata else {
            throw MeshKitValidationError.signatureMismatch("execution link provider metadata mismatch")
        }
    }

    public func validate(paymentRequest: MeshPaymentExecutionRequest) throws {
        try validate()
        try paymentRequest.validate()
        let metadata = paymentRequest.requestAnchor.metadata
        let executionRequest = paymentRequest.executionRequest
        guard paymentId == paymentRequest.paymentId,
              authorizationId == paymentRequest.authorizationDecision.authorizationId,
              authorizationStatus == paymentRequest.authorizationDecision.status,
              executionId == executionRequest.executionId,
              executionKind == executionRequest.kind,
              asset == paymentRequest.asset.uppercased(),
              amount == paymentRequest.amount,
              recipient == paymentRequest.recipient else {
            throw MeshKitValidationError.signatureMismatch("execution link payment request mismatch")
        }
        guard requestId == metadata.requestId,
              requestNonce == metadata.nonce,
              callerBundleId == metadata.callerBundleId,
              targetBundleId == metadata.targetBundleId,
              capabilityId == metadata.capabilityId,
              payloadHash == metadata.payloadHash,
              signedRequestHash == metadata.signedRequestHash else {
            throw MeshKitValidationError.signatureMismatch("execution link anchored request metadata mismatch")
        }
        guard signedRequestHash == paymentRequest.requestHash,
              signedRequestHash == executionRequest.requestAnchorMetadata.signedRequestHash else {
            throw MeshKitValidationError.signatureMismatch("execution link request hash mismatch")
        }
        guard anchoringReference == paymentRequest.requestAnchor.identifier else {
            throw MeshKitValidationError.signatureMismatch("execution link anchor reference mismatch")
        }
        guard policyId == executionRequest.policyId,
              policyHash == executionRequest.policyHash else {
            throw MeshKitValidationError.signatureMismatch("execution link policy binding mismatch")
        }
    }

    public func validate(
        paymentRequest: MeshPaymentExecutionRequest,
        providerIdentity: MeshChainProviderIdentity
    ) throws {
        try validate(providerIdentity: providerIdentity)
        try validate(paymentRequest: paymentRequest)
    }

    public func validate() throws {
        guard version == Self.version else {
            throw MeshKitValidationError.invalidPaymentExecution("version")
        }
        try providerMetadata.validate()
        try requirePaymentField("adapterId", adapterId)
        try requirePaymentField("paymentId", paymentId)
        try requirePaymentField("authorizationId", authorizationId)
        try requirePaymentField("executionId", executionId)
        guard amount > 0 else {
            throw MeshKitValidationError.invalidPaymentExecution("amount")
        }
        try requirePaymentField("asset", asset)
        try requirePaymentField("recipient", recipient)
        try requirePaymentField("requestId", requestId)
        try requirePaymentField("requestNonce", requestNonce)
        try requirePaymentField("callerBundleId", callerBundleId)
        try requirePaymentField("targetBundleId", targetBundleId)
        try requirePaymentField("capabilityId", capabilityId)
        try validatePaymentHash("payloadHash", payloadHash)
        try validatePaymentHash("signedRequestHash", signedRequestHash)
        try anchoringReference.validate()
        try requirePaymentField("policyId", policyId)
        try validatePaymentHash("policyHash", policyHash)
        try requirePaymentField("submittedAt", submittedAt)
        let expectedCanonicalString = try Self.makeCanonicalString(
            version: version,
            providerMetadata: providerMetadata,
            adapterId: adapterId,
            paymentId: paymentId,
            authorizationId: authorizationId,
            authorizationStatus: authorizationStatus,
            executionId: executionId,
            executionKind: executionKind,
            asset: asset,
            amount: amount,
            recipient: recipient,
            requestId: requestId,
            requestNonce: requestNonce,
            callerBundleId: callerBundleId,
            targetBundleId: targetBundleId,
            capabilityId: capabilityId,
            payloadHash: payloadHash,
            signedRequestHash: signedRequestHash,
            anchoringReference: anchoringReference,
            policyId: policyId,
            policyHash: policyHash,
            submittedAt: submittedAt
        )
        guard canonicalString == expectedCanonicalString else {
            throw MeshKitValidationError.signatureMismatch("execution link canonical payload mismatch")
        }
    }

    private static func makeCanonicalString(
        version: String,
        providerMetadata: MeshChainProviderMetadata,
        adapterId: String,
        paymentId: String,
        authorizationId: String,
        authorizationStatus: MeshAgentWalletAuthorizationStatus,
        executionId: String,
        executionKind: MeshAgentWalletExecutionKind,
        asset: String,
        amount: Decimal,
        recipient: String,
        requestId: String,
        requestNonce: String,
        callerBundleId: String,
        targetBundleId: String,
        capabilityId: String,
        payloadHash: MeshPayloadHash,
        signedRequestHash: MeshPayloadHash,
        anchoringReference: MeshRequestAnchorIdentifier,
        policyId: String,
        policyHash: MeshPayloadHash,
        submittedAt: String
    ) throws -> String {
        try providerMetadata.validate()
        try anchoringReference.validate()
        try validatePaymentHash("payloadHash", payloadHash)
        try validatePaymentHash("signedRequestHash", signedRequestHash)
        try validatePaymentHash("policyHash", policyHash)

        return [
            version,
            "provider=\(providerMetadata.provider)",
            "network=\(providerMetadata.network)",
            "chainId=\(providerMetadata.chainId)",
            "adapterId=\(adapterId)",
            "paymentId=\(paymentId)",
            "authorizationId=\(authorizationId)",
            "authorizationStatus=\(authorizationStatus.rawValue)",
            "executionId=\(executionId)",
            "executionKind=\(executionKind.rawValue)",
            "asset=\(asset.uppercased())",
            "amount=\(amount)",
            "recipient=\(recipient)",
            "requestId=\(requestId)",
            "requestNonce=\(requestNonce)",
            "callerBundleId=\(callerBundleId)",
            "targetBundleId=\(targetBundleId)",
            "capabilityId=\(capabilityId)",
            "payloadHashAlgorithm=\(payloadHash.algorithm.lowercased())",
            "payloadHashValue=\(payloadHash.value.lowercased())",
            "signedRequestHashAlgorithm=\(signedRequestHash.algorithm.lowercased())",
            "signedRequestHashValue=\(signedRequestHash.value.lowercased())",
            "anchoringReference=\(anchoringReference.anchorId)",
            "anchoringTxHash=\(anchoringReference.transactionHash ?? "")",
            "policyId=\(policyId)",
            "policyHashAlgorithm=\(policyHash.algorithm.lowercased())",
            "policyHashValue=\(policyHash.value.lowercased())",
            "submittedAt=\(submittedAt)"
        ].joined(separator: "\n")
    }
}

public struct MeshMarooTestnetPaymentExecutionSubmissionResponse: Codable, Equatable, Sendable {
    public static let version = "meshkit-maroo-okrw-payment-response/v1"

    public let version: String
    public let providerMetadata: MeshChainProviderMetadata
    public let transactionHash: String?
    public let status: MeshPaymentExecutionStatus
    public let observedAt: String?
    public let message: String?
    public let providerOutcome: MeshMarooTestnetPaymentExecutionProviderOutcome?
    public let resultSource: MeshPaymentExecutionResultSource
    public let confirmationPayload: MeshMarooTestnetPaymentConfirmationPayload?

    public var resultMapping: MeshMarooTestnetPaymentExecutionResultMapping? {
        providerOutcome.map { MeshMarooTestnetPaymentExecutionResultMapping(providerOutcome: $0) }
    }

    public var sourceStateMapping: MeshPaymentExecutionResultSourceStateMapping? {
        providerOutcome.map {
            MeshPaymentExecutionResultSourceStateMapping(
                source: resultSource,
                providerOutcome: $0,
                explicitStatus: status
            )
        }
    }

    public init(
        providerMetadata: MeshChainProviderMetadata,
        transactionHash: String? = nil,
        status: MeshPaymentExecutionStatus,
        observedAt: String? = nil,
        message: String? = nil,
        providerOutcome: MeshMarooTestnetPaymentExecutionProviderOutcome? = nil,
        resultSource: MeshPaymentExecutionResultSource = .live,
        confirmationPayload: MeshMarooTestnetPaymentConfirmationPayload? = nil,
        version: String = MeshMarooTestnetPaymentExecutionSubmissionResponse.version
    ) throws {
        let sourceMapping = providerOutcome.map {
            MeshPaymentExecutionResultSourceStateMapping(
                source: resultSource,
                providerOutcome: $0,
                explicitStatus: status
            )
        }
        let normalizedStatus = sourceMapping?.executionStatus ?? Self.statusBlockedFromConfirmation(
            status,
            resultSource: resultSource
        )
        self.version = try normalizedPaymentField("version", version)
        self.providerMetadata = providerMetadata
        self.transactionHash = try transactionHash.map { try normalizedPaymentField("transactionHash", $0) }
        self.status = normalizedStatus
        self.observedAt = try observedAt.map { try normalizedPaymentField("observedAt", $0) }
        self.message = try (message ?? sourceMapping?.defaultMessage ?? Self.defaultMessage(
            explicitStatus: status,
            normalizedStatus: normalizedStatus,
            resultSource: resultSource
        )).map { try normalizedPaymentField("message", $0) }
        self.providerOutcome = providerOutcome
        self.resultSource = resultSource
        self.confirmationPayload = self.status == .confirmed ? confirmationPayload : nil
        try validate()
    }

    public init(
        providerMetadata: MeshChainProviderMetadata,
        transactionHash: String? = nil,
        providerOutcome: String,
        resultSource: MeshPaymentExecutionResultSource = .live,
        observedAt: String? = nil,
        message: String? = nil,
        confirmationPayload: MeshMarooTestnetPaymentConfirmationPayload? = nil,
        version: String = MeshMarooTestnetPaymentExecutionSubmissionResponse.version
    ) throws {
        let mapping = try MeshMarooTestnetPaymentExecutionResultMapping(providerOutcome: providerOutcome)
        let sourceMapping = MeshPaymentExecutionResultSourceStateMapping(
            source: resultSource,
            providerOutcome: mapping.providerOutcome
        )
        try self.init(
            providerMetadata: providerMetadata,
            transactionHash: transactionHash,
            status: sourceMapping.executionStatus,
            observedAt: observedAt,
            message: message ?? sourceMapping.defaultMessage,
            providerOutcome: mapping.providerOutcome,
            resultSource: resultSource,
            confirmationPayload: confirmationPayload,
            version: version
        )
    }

    public init(
        providerMetadata: MeshChainProviderMetadata,
        transactionHash: String? = nil,
        providerTransactionState: String,
        resultSource: MeshPaymentExecutionResultSource = .live,
        observedAt: String? = nil,
        message: String? = nil,
        confirmationPayload: MeshMarooTestnetPaymentConfirmationPayload? = nil,
        version: String = MeshMarooTestnetPaymentExecutionSubmissionResponse.version
    ) throws {
        let mapping = try MeshMarooTestnetTransactionStateMapping(
            providerTransactionState: providerTransactionState
        )
        let sourceMapping = MeshPaymentExecutionResultSourceStateMapping(
            source: resultSource,
            providerOutcome: mapping.providerOutcome
        )
        try self.init(
            providerMetadata: providerMetadata,
            transactionHash: transactionHash,
            status: sourceMapping.executionStatus,
            observedAt: observedAt,
            message: message ?? sourceMapping.defaultMessage,
            providerOutcome: mapping.providerOutcome,
            resultSource: resultSource,
            confirmationPayload: confirmationPayload,
            version: version
        )
    }

    public func validate(providerIdentity: MeshChainProviderIdentity, submittedAt: String) throws {
        try validate()
        try providerIdentity.validate()
        try requirePaymentField("submittedAt", submittedAt)
        guard providerMetadata == providerIdentity.metadata else {
            throw MeshKitValidationError.signatureMismatch("payment execution provider metadata mismatch")
        }
    }

    public func normalizedExecutionResult(
        request: MeshPaymentExecutionRequest,
        identity: MeshChainProviderIdentity,
        submittedAt: String,
        providerExtensions: [String: [String: String]] = [:]
    ) throws -> MeshPaymentExecutionResult {
        try request.validate()
        try validate(providerIdentity: identity, submittedAt: submittedAt)
        return try MeshPaymentExecutionResult(
            request: request,
            identity: identity,
            status: status,
            transactionHash: transactionHash,
            observedAt: observedAt ?? submittedAt,
            message: message,
            providerExtensions: providerExtensions
        )
    }

    public func validate() throws {
        guard version == Self.version else {
            throw MeshKitValidationError.invalidPaymentExecution("version")
        }
        try providerMetadata.validate()
        _ = resultSource
        if let transactionHash {
            try requirePaymentField("transactionHash", transactionHash)
        }
        if let observedAt {
            try requirePaymentField("observedAt", observedAt)
        }
        if let message {
            try requirePaymentField("message", message)
        }
        if let confirmationPayload {
            try confirmationPayload.validate(
                providerMetadata: providerMetadata,
                transactionHash: transactionHash,
                observedAt: observedAt
            )
        }
        try validateResultMapping()
        try validateSourceStateMapping()
        if status == .confirmed, transactionHash == nil {
            throw MeshKitValidationError.invalidPaymentExecution("transactionHash")
        }
        if status == .confirmed, confirmationPayload == nil {
            throw MeshKitValidationError.invalidPaymentExecution("confirmationPayload")
        }
        if status != .confirmed, confirmationPayload != nil {
            throw MeshKitValidationError.invalidPaymentExecution("confirmationPayload")
        }
        if status == .policyDenied, transactionHash != nil {
            throw MeshKitValidationError.invalidPaymentExecution("transactionHash")
        }
    }

    private func validateResultMapping() throws {
        guard let mapping = resultMapping else { return }
        let expectedStatus = sourceStateMapping?.executionStatus ?? mapping.executionStatus
        guard expectedStatus == status else {
            throw MeshKitValidationError.invalidPaymentExecution("providerOutcome")
        }
        if resultSource.canConfirmPaymentExecution, mapping.providerOutcome == .success, transactionHash == nil {
            throw MeshKitValidationError.invalidPaymentExecution("transactionHash")
        }
        if resultSource.canConfirmPaymentExecution, mapping.providerOutcome == .success, confirmationPayload == nil {
            throw MeshKitValidationError.invalidPaymentExecution("confirmationPayload")
        }
        if mapping.providerOutcome == .policyDenied, transactionHash != nil {
            throw MeshKitValidationError.invalidPaymentExecution("transactionHash")
        }
    }

    private func validateSourceStateMapping() throws {
        if let sourceStateMapping {
            guard sourceStateMapping.executionStatus == status else {
                throw MeshKitValidationError.invalidPaymentExecution("resultSource")
            }
        }
        guard resultSource.canConfirmPaymentExecution || status != .confirmed else {
            throw MeshKitValidationError.invalidPaymentExecution("resultSource")
        }
    }

    private static func statusBlockedFromConfirmation(
        _ status: MeshPaymentExecutionStatus,
        resultSource: MeshPaymentExecutionResultSource
    ) -> MeshPaymentExecutionStatus {
        guard !resultSource.canConfirmPaymentExecution, status == .confirmed else {
            return status
        }
        return .pending
    }

    private static func defaultMessage(
        explicitStatus: MeshPaymentExecutionStatus,
        normalizedStatus: MeshPaymentExecutionStatus,
        resultSource: MeshPaymentExecutionResultSource
    ) -> String? {
        guard !resultSource.canConfirmPaymentExecution,
              explicitStatus == .confirmed,
              normalizedStatus == .pending else {
            return nil
        }
        return "\(resultSource.rawValue) execution awaiting live confirmation"
    }
}

public struct MeshMarooTestnetPaymentConfirmationPayload: Codable, Equatable, Sendable {
    public static let version = "meshkit-maroo-confirmation/v1"

    public let version: String
    public let providerMetadata: MeshChainProviderMetadata
    public let transactionHash: String
    public let blockHash: String
    public let blockNumber: UInt64
    public let confirmationCount: UInt64
    public let confirmedAt: String

    public init(
        providerMetadata: MeshChainProviderMetadata,
        transactionHash: String,
        blockHash: String,
        blockNumber: UInt64,
        confirmationCount: UInt64,
        confirmedAt: String,
        version: String = MeshMarooTestnetPaymentConfirmationPayload.version
    ) throws {
        self.version = try normalizedPaymentField("confirmationPayload.version", version)
        self.providerMetadata = providerMetadata
        self.transactionHash = try normalizedPaymentField("confirmationPayload.transactionHash", transactionHash)
        self.blockHash = try normalizedPaymentField("confirmationPayload.blockHash", blockHash)
        self.blockNumber = blockNumber
        self.confirmationCount = confirmationCount
        self.confirmedAt = try normalizedPaymentField("confirmationPayload.confirmedAt", confirmedAt)
        try validate()
    }

    public func validate(
        providerMetadata expectedProviderMetadata: MeshChainProviderMetadata? = nil,
        transactionHash expectedTransactionHash: String? = nil,
        observedAt expectedObservedAt: String? = nil
    ) throws {
        guard version == Self.version else {
            throw MeshKitValidationError.invalidPaymentExecution("confirmationPayload.version")
        }
        try providerMetadata.validate()
        try requirePaymentField("confirmationPayload.transactionHash", transactionHash)
        try requirePaymentField("confirmationPayload.blockHash", blockHash)
        guard blockNumber > 0 else {
            throw MeshKitValidationError.invalidPaymentExecution("confirmationPayload.blockNumber")
        }
        guard confirmationCount > 0 else {
            throw MeshKitValidationError.invalidPaymentExecution("confirmationPayload.confirmationCount")
        }
        try requirePaymentField("confirmationPayload.confirmedAt", confirmedAt)
        if let expectedProviderMetadata, providerMetadata != expectedProviderMetadata {
            throw MeshKitValidationError.signatureMismatch("maroo confirmation provider metadata mismatch")
        }
        if let expectedTransactionHash {
            let normalizedExpectedTransactionHash = try normalizedPaymentField("transactionHash", expectedTransactionHash)
            guard transactionHash == normalizedExpectedTransactionHash else {
                throw MeshKitValidationError.invalidPaymentExecution("confirmationPayload.transactionHash")
            }
        }
        if let expectedObservedAt {
            let normalizedExpectedObservedAt = try normalizedPaymentField("observedAt", expectedObservedAt)
            guard confirmedAt == normalizedExpectedObservedAt else {
                throw MeshKitValidationError.invalidPaymentExecution("confirmationPayload.confirmedAt")
            }
        }
    }
}

public protocol MeshMarooTestnetPaymentExecutionSubmissionClient: Sendable {
    func submitOKRWExecution(
        _ transactionRequest: MeshMarooTestnetOKRWExecutionTransactionRequest,
        providerInput input: MeshMarooTestnetPaymentExecutionProviderInput
    ) async throws -> MeshMarooTestnetPaymentExecutionSubmissionResponse
}

public protocol MeshOKRWTransferBridgeHTTPTransport: Sendable {
    func sendOKRWTransferBridgeRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct MeshURLSessionOKRWTransferBridgeHTTPTransport: MeshOKRWTransferBridgeHTTPTransport {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func sendOKRWTransferBridgeRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MeshKitValidationError.invalidPaymentExecution("mawsResponse")
        }
        return (data, httpResponse)
    }
}

public struct MeshMAWSTransferSendBridgeClient: MeshMarooTestnetPaymentExecutionSubmissionClient {
    public static let toolName = "transfer.send"
    public static let bridgeSchemaVersion = "meshkit-maws-transfer-send-bridge/v1"

    public let bridgeEndpoint: URL
    public let agentId: String
    public let authorizationHeader: String?
    public let transport: any MeshOKRWTransferBridgeHTTPTransport

    public init(
        bridgeEndpoint: URL,
        agentId: String,
        authorizationHeader: String? = nil,
        transport: any MeshOKRWTransferBridgeHTTPTransport = MeshURLSessionOKRWTransferBridgeHTTPTransport()
    ) throws {
        try MeshChainProviderIdentity.validateNetworkURL("bridgeEndpoint", bridgeEndpoint)
        self.bridgeEndpoint = bridgeEndpoint
        self.agentId = try normalizedPaymentField("agentId", agentId)
        self.authorizationHeader = try authorizationHeader.map { try normalizedPaymentField("authorizationHeader", $0) }
        self.transport = transport
    }

    public func submitOKRWExecution(
        _ transactionRequest: MeshMarooTestnetOKRWExecutionTransactionRequest,
        providerInput input: MeshMarooTestnetPaymentExecutionProviderInput
    ) async throws -> MeshMarooTestnetPaymentExecutionSubmissionResponse {
        try input.validate()
        try transactionRequest.validate(providerMetadata: input.providerMetadata)
        let request = try httpRequest(transactionRequest: transactionRequest, input: input)
        let (data, response) = try await transport.sendOKRWTransferBridgeRequest(request)
        return try decodeBridgeResponse(
            data,
            response: response,
            providerMetadata: input.providerMetadata,
            submittedAt: input.submittedAt
        )
    }

    public func httpRequest(
        transactionRequest: MeshMarooTestnetOKRWExecutionTransactionRequest,
        input: MeshMarooTestnetPaymentExecutionProviderInput
    ) throws -> URLRequest {
        try input.validate()
        try transactionRequest.validate(providerMetadata: input.providerMetadata)
        var request = URLRequest(url: bridgeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        if let authorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "authorization")
        }
        let payload = try MeshMAWSTransferSendBridgeRequest(
            agentId: agentId,
            transactionRequest: transactionRequest
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        request.httpBody = try encoder.encode(payload)
        return request
    }

    private func decodeBridgeResponse(
        _ data: Data,
        response: HTTPURLResponse,
        providerMetadata: MeshChainProviderMetadata,
        submittedAt: String
    ) throws -> MeshMarooTestnetPaymentExecutionSubmissionResponse {
        guard (200..<300).contains(response.statusCode) else {
            return try MeshMarooTestnetPaymentExecutionSubmissionResponse(
                providerMetadata: providerMetadata,
                status: .failed,
                observedAt: submittedAt,
                message: "MAWS bridge HTTP \(response.statusCode)",
                providerOutcome: .failure,
                resultSource: .live
            )
        }

        let decoded = try JSONDecoder().decode(MeshMAWSTransferSendBridgeResponse.self, from: data)
        if let error = decoded.error, decoded.ok == false {
            return try MeshMarooTestnetPaymentExecutionSubmissionResponse(
                providerMetadata: providerMetadata,
                status: error.isPolicyRejection ? .policyDenied : .failed,
                observedAt: decoded.data?.observedAt ?? submittedAt,
                message: error.normalizedMessage,
                providerOutcome: error.isPolicyRejection ? .policyDenied : .failure,
                resultSource: .live
            )
        }

        guard decoded.ok != false, let data = decoded.data else {
            return try MeshMarooTestnetPaymentExecutionSubmissionResponse(
                providerMetadata: providerMetadata,
                status: .failed,
                observedAt: submittedAt,
                message: "MAWS bridge response missing data",
                providerOutcome: .failure,
                resultSource: .live
            )
        }

        var outcome = try data.providerOutcome
        let txHash = data.transactionHash
        let fallbackObservedAt = data.observedAt ?? submittedAt
        let confirmationPayload = try data.confirmationPayload(
            providerMetadata: providerMetadata,
            transactionHash: txHash,
            fallbackConfirmedAt: fallbackObservedAt
        )
        let observedAt = confirmationPayload?.confirmedAt ?? fallbackObservedAt
        var message = data.message
        if outcome == .success, confirmationPayload == nil {
            outcome = .pending
            message = message ?? "MAWS transfer.send returned txHash without maroo confirmation proof"
        }

        return try MeshMarooTestnetPaymentExecutionSubmissionResponse(
            providerMetadata: providerMetadata,
            transactionHash: txHash,
            providerOutcome: outcome.rawValue,
            resultSource: .live,
            observedAt: observedAt,
            message: message,
            confirmationPayload: confirmationPayload
        )
    }
}

public struct MeshMarooNativeOKRWTransferBridgeClient: MeshMarooTestnetPaymentExecutionSubmissionClient {
    public static let toolName = "maroo.native_transfer"
    public static let bridgeSchemaVersion = "meshkit-maroo-native-okrw-transfer-bridge/v1"

    public let bridgeEndpoint: URL
    public let authorizationHeader: String?
    public let transport: any MeshOKRWTransferBridgeHTTPTransport

    public init(
        bridgeEndpoint: URL,
        authorizationHeader: String? = nil,
        transport: any MeshOKRWTransferBridgeHTTPTransport = MeshURLSessionOKRWTransferBridgeHTTPTransport()
    ) throws {
        try MeshChainProviderIdentity.validateNetworkURL("bridgeEndpoint", bridgeEndpoint)
        self.bridgeEndpoint = bridgeEndpoint
        self.authorizationHeader = try authorizationHeader.map { try normalizedPaymentField("authorizationHeader", $0) }
        self.transport = transport
    }

    public func submitOKRWExecution(
        _ transactionRequest: MeshMarooTestnetOKRWExecutionTransactionRequest,
        providerInput input: MeshMarooTestnetPaymentExecutionProviderInput
    ) async throws -> MeshMarooTestnetPaymentExecutionSubmissionResponse {
        try input.validate()
        try transactionRequest.validate(providerMetadata: input.providerMetadata)
        var request = URLRequest(url: bridgeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        if let authorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "authorization")
        }
        let payload = try MeshMarooNativeOKRWTransferBridgeRequest(transactionRequest: transactionRequest)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        request.httpBody = try encoder.encode(payload)
        let (data, response) = try await transport.sendOKRWTransferBridgeRequest(request)
        return try decodeBridgeResponse(
            data,
            response: response,
            providerMetadata: input.providerMetadata,
            submittedAt: input.submittedAt
        )
    }

    private func decodeBridgeResponse(
        _ data: Data,
        response: HTTPURLResponse,
        providerMetadata: MeshChainProviderMetadata,
        submittedAt: String
    ) throws -> MeshMarooTestnetPaymentExecutionSubmissionResponse {
        guard (200..<300).contains(response.statusCode) else {
            return try MeshMarooTestnetPaymentExecutionSubmissionResponse(
                providerMetadata: providerMetadata,
                status: .failed,
                observedAt: submittedAt,
                message: "maroo native OKRW bridge HTTP \(response.statusCode)",
                providerOutcome: .failure,
                resultSource: .live
            )
        }

        let decoded = try JSONDecoder().decode(MeshMAWSTransferSendBridgeResponse.self, from: data)
        if let error = decoded.error, decoded.ok == false {
            return try MeshMarooTestnetPaymentExecutionSubmissionResponse(
                providerMetadata: providerMetadata,
                status: error.isPolicyRejection ? .policyDenied : .failed,
                observedAt: decoded.data?.observedAt ?? submittedAt,
                message: error.normalizedMessage,
                providerOutcome: error.isPolicyRejection ? .policyDenied : .failure,
                resultSource: .live
            )
        }

        guard decoded.ok != false, let data = decoded.data else {
            return try MeshMarooTestnetPaymentExecutionSubmissionResponse(
                providerMetadata: providerMetadata,
                status: .failed,
                observedAt: submittedAt,
                message: "maroo native OKRW bridge response missing data",
                providerOutcome: .failure,
                resultSource: .live
            )
        }

        var outcome = try data.providerOutcome
        let txHash = data.transactionHash
        let fallbackObservedAt = data.observedAt ?? submittedAt
        let confirmationPayload = try data.confirmationPayload(
            providerMetadata: providerMetadata,
            transactionHash: txHash,
            fallbackConfirmedAt: fallbackObservedAt
        )
        let observedAt = confirmationPayload?.confirmedAt ?? fallbackObservedAt
        var message = data.message
        if outcome == .success, confirmationPayload == nil {
            outcome = .pending
            message = message ?? "maroo native OKRW bridge returned txHash without maroo confirmation proof"
        }

        return try MeshMarooTestnetPaymentExecutionSubmissionResponse(
            providerMetadata: providerMetadata,
            transactionHash: txHash,
            providerOutcome: outcome.rawValue,
            resultSource: .live,
            observedAt: observedAt,
            message: message,
            confirmationPayload: confirmationPayload
        )
    }
}

public struct MeshMarooOKRWSubmissionClientEnvironmentFactory {
    public static let nativeBridgeURLKey = "MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_URL"
    public static let nativeBridgeAuthorizationKey = "MESHKIT_MAROO_OKRW_TRANSFER_AUTHORIZATION"
    public static let mawsBridgeURLKey = "MESHKIT_MAWS_BRIDGE_URL"
    public static let mawsAgentIdKey = "MESHKIT_MAWS_AGENT_ID"
    public static let mawsAuthorizationKey = "MESHKIT_MAWS_AUTHORIZATION"
    public static let waasAuthTokenKey = "WAAS_AUTH_TOKEN"
    public static let fallbackMessage = "MAWS bridge not configured; maroo OKRW live transfer not attempted"

    public let environment: [String: String]

    public init(environment: [String: String]) {
        self.environment = environment
    }

    public func makeSubmissionClient() throws -> any MeshMarooTestnetPaymentExecutionSubmissionClient {
        if let nativeBridgeURL = urlValue(for: Self.nativeBridgeURLKey) {
            return try MeshMarooNativeOKRWTransferBridgeClient(
                bridgeEndpoint: nativeBridgeURL,
                authorizationHeader: environment[Self.nativeBridgeAuthorizationKey]
            )
        }
        guard let bridgeURL = urlValue(for: Self.mawsBridgeURLKey),
              let agentId = stringValue(for: Self.mawsAgentIdKey) else {
            return try MeshMarooTestnetDeterministicPaymentExecutionSubmissionClient(
                message: Self.fallbackMessage
            )
        }
        let authorizationHeader = environment[Self.mawsAuthorizationKey]
            ?? environment[Self.waasAuthTokenKey].map { "Bearer \($0)" }
        return try MeshMAWSTransferSendBridgeClient(
            bridgeEndpoint: bridgeURL,
            agentId: agentId,
            authorizationHeader: authorizationHeader
        )
    }

    private func urlValue(for key: String) -> URL? {
        guard let value = stringValue(for: key) else {
            return nil
        }
        return URL(string: value)
    }

    private func stringValue(for key: String) -> String? {
        guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

private struct MeshMAWSTransferSendBridgeRequest: Encodable {
    let schemaVersion: String
    let tool: String
    let arguments: MeshMAWSTransferSendArguments
    let meshkit: MeshMarooTestnetOKRWExecutionTransactionRequest

    init(
        agentId: String,
        transactionRequest: MeshMarooTestnetOKRWExecutionTransactionRequest
    ) throws {
        self.schemaVersion = MeshMAWSTransferSendBridgeClient.bridgeSchemaVersion
        self.tool = MeshMAWSTransferSendBridgeClient.toolName
        self.arguments = try MeshMAWSTransferSendArguments(
            agentId: agentId,
            transactionRequest: transactionRequest
        )
        self.meshkit = transactionRequest
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case tool
        case arguments
        case meshkit
    }
}

private struct MeshMarooNativeOKRWTransferBridgeRequest: Encodable {
    let schemaVersion: String
    let tool: String
    let arguments: MeshMarooNativeOKRWTransferArguments
    let meshkit: MeshMarooTestnetOKRWExecutionTransactionRequest

    init(transactionRequest: MeshMarooTestnetOKRWExecutionTransactionRequest) throws {
        self.schemaVersion = MeshMarooNativeOKRWTransferBridgeClient.bridgeSchemaVersion
        self.tool = MeshMarooNativeOKRWTransferBridgeClient.toolName
        self.arguments = try MeshMarooNativeOKRWTransferArguments(transactionRequest: transactionRequest)
        self.meshkit = transactionRequest
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case tool
        case arguments
        case meshkit
    }
}

private struct MeshMarooNativeOKRWTransferArguments: Encodable {
    let to: String
    let amount: String
    let clientToken: String
    let memo: String

    init(transactionRequest: MeshMarooTestnetOKRWExecutionTransactionRequest) throws {
        self.to = transactionRequest.recipientAddress
        self.amount = NSDecimalNumber(decimal: transactionRequest.amount).stringValue
        self.clientToken = transactionRequest.paymentId
        self.memo = transactionRequest.memo
    }
}

private struct MeshMAWSTransferSendArguments: Encodable {
    let agentId: String
    let to: String
    let amount: String
    let clientToken: String
    let memo: String

    init(
        agentId: String,
        transactionRequest: MeshMarooTestnetOKRWExecutionTransactionRequest
    ) throws {
        self.agentId = try normalizedPaymentField("agentId", agentId)
        self.to = transactionRequest.recipientAddress
        self.amount = NSDecimalNumber(decimal: transactionRequest.amount).stringValue
        self.clientToken = transactionRequest.paymentId
        self.memo = transactionRequest.memo
    }
}

private struct MeshMAWSTransferSendBridgeResponse: Decodable {
    let ok: Bool?
    let data: MeshMAWSTransferSendBridgeResponseData?
    let error: MeshMAWSTransferSendBridgeError?
}

private struct MeshMAWSTransferSendBridgeResponseData: Decodable {
    let txHash: String?
    let transactionHashAlias: String?
    let status: String?
    let providerOutcomeValue: String?
    let message: String?
    let observedAt: String?
    let blockHash: String?
    let blockNumber: UInt64?
    let confirmationCount: UInt64?
    let confirmedAt: String?

    var transactionHash: String? {
        txHash ?? transactionHashAlias
    }

    var providerOutcome: MeshMarooTestnetPaymentExecutionProviderOutcome {
        get throws {
            try MeshMarooTestnetPaymentExecutionProviderOutcome(
                providerValue: providerOutcomeValue ?? status ?? (transactionHash == nil ? "pending" : "success")
            )
        }
    }

    func confirmationPayload(
        providerMetadata: MeshChainProviderMetadata,
        transactionHash: String?,
        fallbackConfirmedAt: String
    ) throws -> MeshMarooTestnetPaymentConfirmationPayload? {
        guard let transactionHash,
              let blockHash,
              let blockNumber,
              let confirmationCount else {
            return nil
        }
        return try MeshMarooTestnetPaymentConfirmationPayload(
            providerMetadata: providerMetadata,
            transactionHash: transactionHash,
            blockHash: blockHash,
            blockNumber: blockNumber,
            confirmationCount: confirmationCount,
            confirmedAt: confirmedAt ?? observedAt ?? fallbackConfirmedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case txHash
        case transactionHashAlias = "transactionHash"
        case status
        case providerOutcomeValue = "providerOutcome"
        case message
        case observedAt
        case blockHash
        case blockNumber
        case confirmationCount
        case confirmedAt
    }
}

private struct MeshMAWSTransferSendBridgeError: Decodable {
    let code: String?
    let message: String?
    let suggestion: String?

    var normalizedMessage: String {
        message ?? suggestion ?? code ?? "MAWS transfer.send failed"
    }

    var isPolicyRejection: Bool {
        let normalized = (code ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        return normalized == "policy_rejected" ||
            normalized == "policy_denied" ||
            normalized == "wallet_policy_denied"
    }
}

public struct MeshMarooTestnetDeterministicPaymentExecutionSubmissionClient: MeshMarooTestnetPaymentExecutionSubmissionClient {
    public let executionStatus: MeshPaymentExecutionStatus
    public let transactionHash: String?
    public let message: String?

    public init(
        executionStatus: MeshPaymentExecutionStatus = .pending,
        transactionHash: String? = nil,
        message: String? = nil
    ) throws {
        self.executionStatus = executionStatus
        self.transactionHash = try transactionHash.map { try normalizedPaymentField("transactionHash", $0) }
        self.message = try message.map { try normalizedPaymentField("message", $0) }
    }

    public func submitOKRWExecution(
        _ transactionRequest: MeshMarooTestnetOKRWExecutionTransactionRequest,
        providerInput input: MeshMarooTestnetPaymentExecutionProviderInput
    ) async throws -> MeshMarooTestnetPaymentExecutionSubmissionResponse {
        try input.validate()
        try transactionRequest.validate(providerMetadata: input.providerMetadata)
        return try MeshMarooTestnetPaymentExecutionSubmissionResponse(
            providerMetadata: input.providerMetadata,
            transactionHash: transactionHashForApprovedExecution(input: input),
            status: executionStatus,
            observedAt: input.submittedAt,
            message: messageForStatus,
            confirmationPayload: confirmationPayloadForApprovedExecution(input: input)
        )
    }

    private func transactionHashForApprovedExecution(input: MeshMarooTestnetPaymentExecutionProviderInput) -> String? {
        switch executionStatus {
        case .confirmed:
            return transactionHash ?? Self.deterministicTransactionHash(input: input)
        case .pending, .failed:
            return transactionHash
        case .policyDenied:
            return nil
        }
    }

    private var messageForStatus: String? {
        if let message {
            return message
        }
        switch executionStatus {
        case .pending:
            return "maroo testnet OKRW execution pending confirmation"
        case .failed:
            return "maroo testnet OKRW execution failed"
        default:
            return nil
        }
    }

    private func confirmationPayloadForApprovedExecution(
        input: MeshMarooTestnetPaymentExecutionProviderInput
    ) throws -> MeshMarooTestnetPaymentConfirmationPayload? {
        guard executionStatus == .confirmed else { return nil }
        let hash = transactionHashForApprovedExecution(input: input) ?? Self.deterministicTransactionHash(input: input)
        return try Self.deterministicConfirmationPayload(
            providerMetadata: input.providerMetadata,
            transactionHash: hash,
            confirmedAt: input.submittedAt
        )
    }

    public static func deterministicConfirmationPayload(
        providerMetadata: MeshChainProviderMetadata,
        transactionHash: String,
        confirmedAt: String
    ) throws -> MeshMarooTestnetPaymentConfirmationPayload {
        let normalizedHash = try normalizedPaymentField("transactionHash", transactionHash)
        let data = Data("\(providerMetadata.provider):\(providerMetadata.network):\(normalizedHash):\(confirmedAt)".utf8)
        let digest = SHA256.hash(data: data)
        let digestBytes = Array(digest)
        let blockHash = "0x" + digestBytes.map { String(format: "%02x", $0) }.joined()
        return try MeshMarooTestnetPaymentConfirmationPayload(
            providerMetadata: providerMetadata,
            transactionHash: normalizedHash,
            blockHash: blockHash,
            blockNumber: UInt64(digestBytes.first ?? 0) + 1,
            confirmationCount: 1,
            confirmedAt: confirmedAt
        )
    }

    private static func deterministicTransactionHash(input: MeshMarooTestnetPaymentExecutionProviderInput) -> String {
        let data = Data("\(MeshMarooTestnetPaymentExecutorAdapter.adapterId):\(input.sha256Hash().value)".utf8)
        let digest = SHA256.hash(data: data)
        return "0x" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

public struct MeshMarooTestnetPaymentExecutorAdapter: MeshPaymentExecutor {
    public static let adapterId = "maroo-testnet-payment-executor-demo-adapter"
    public static let okrwAssetSymbol = "OKRW"
    public static let defaultCapabilities: [MeshPaymentExecutorCapability] = [
        .executePayment,
        .executeTransfer
    ]

    public let chainProvider: MeshMarooTestnetChainProvider
    public let capabilities: [MeshPaymentExecutorCapability]
    public let executionStatus: MeshPaymentExecutionStatus
    public let transactionHash: String?
    public let message: String?
    public let submissionClient: any MeshMarooTestnetPaymentExecutionSubmissionClient

    public var identity: MeshChainProviderIdentity { chainProvider.identity }
    public var capabilityMetadata: MeshPaymentExecutionCapabilityMetadata {
        try! loadCapabilityMetadata()
    }

    public init(
        chainProvider: MeshMarooTestnetChainProvider = try! MeshMarooTestnetChainProvider(),
        capabilities: [MeshPaymentExecutorCapability] = MeshMarooTestnetPaymentExecutorAdapter.defaultCapabilities,
        executionStatus: MeshPaymentExecutionStatus = .pending,
        transactionHash: String? = nil,
        message: String? = nil,
        submissionClient: (any MeshMarooTestnetPaymentExecutionSubmissionClient)? = nil
    ) throws {
        self.chainProvider = chainProvider
        self.capabilities = Array(Set(capabilities)).sorted()
        self.executionStatus = executionStatus
        self.transactionHash = try transactionHash.map { try normalizedPaymentField("transactionHash", $0) }
        self.message = try message.map { try normalizedPaymentField("message", $0) }
        self.submissionClient = try submissionClient ?? MeshMarooTestnetDeterministicPaymentExecutionSubmissionClient(
            executionStatus: executionStatus,
            transactionHash: transactionHash,
            message: message
        )
        try loadPaymentExecutorConfiguration().validate()
        try loadCapabilityMetadata().validate()
    }

    public func loadPaymentExecutorConfiguration() throws -> MeshPaymentExecutorConfiguration {
        try MeshPaymentExecutorConfiguration(identity: identity, capabilities: capabilities)
    }

    public func loadCapabilityMetadata() throws -> MeshPaymentExecutionCapabilityMetadata {
        try MeshPaymentExecutionCapabilityMetadata(
            identity: identity,
            adapterId: Self.adapterId,
            capabilities: capabilities,
            supportedExecutionKinds: [.payment, .transfer],
            supportedAssets: [Self.okrwAssetSymbol],
            paymentOperations: [
                MeshPaymentOperationCapability(
                    executionKind: .payment,
                    asset: Self.okrwAssetSymbol,
                    requiredCapability: .executePayment
                ),
                MeshPaymentOperationCapability(
                    executionKind: .transfer,
                    asset: Self.okrwAssetSymbol,
                    requiredCapability: .executeTransfer
                )
            ],
            requestHashLinkage: true,
            policyBinding: true
        )
    }

    public func executePayment(
        _ request: MeshPaymentExecutionRequest,
        submittedAt: String
    ) async throws -> MeshPaymentExecutionResult {
        try request.validate()
        let configuration = try loadPaymentExecutorConfiguration()
        try configuration.require(paymentExecutionCapability(for: request.executionRequest.kind))
        guard try loadCapabilityMetadata().supportsAsset(request.asset) else {
            throw MeshKitValidationError.invalidPaymentExecution("asset")
        }

        guard request.authorizationDecision.status == .approved else {
            return try MeshPaymentExecutionResult(
                request: request,
                identity: identity,
                status: .policyDenied,
                observedAt: submittedAt,
                message: request.authorizationDecision.reason,
                providerExtensions: providerExtensions(request: request)
            )
        }

        let input = try MeshMarooTestnetPaymentExecutionProviderInput(
            paymentRequest: request,
            providerIdentity: identity,
            submittedAt: submittedAt
        )
        try input.validate(providerIdentity: identity)
        let transactionRequest = try MeshMarooTestnetOKRWExecutionSerializer.transactionRequest(from: input)
        try transactionRequest.validate(providerMetadata: input.providerMetadata)
        let response: MeshMarooTestnetPaymentExecutionSubmissionResponse
        do {
            response = try await submissionClient.submitOKRWExecution(
                transactionRequest,
                providerInput: input
            )
        } catch {
            return try failedExecutionResult(
                request: request,
                input: input,
                error: error
            )
        }
        try response.validate(providerIdentity: identity, submittedAt: input.submittedAt)

        return try response.normalizedExecutionResult(
            request: request,
            identity: identity,
            submittedAt: input.submittedAt,
            providerExtensions: providerExtensions(
                request: request,
                sourceStateMapping: response.sourceStateMapping
            )
        )
    }

    public func paymentExecutionStatus(paymentId: String, checkedAt: String) async throws -> MeshPaymentExecutionResult {
        _ = try normalizedPaymentField("paymentId", paymentId)
        _ = try normalizedPaymentField("checkedAt", checkedAt)
        try loadPaymentExecutorConfiguration().require(.lookupExecutionStatus)
        throw MeshKitValidationError.invalidPaymentExecution("paymentId")
    }

    private func providerExtensions(
        request: MeshPaymentExecutionRequest,
        resultMapping: MeshMarooTestnetPaymentExecutionResultMapping? = nil,
        sourceStateMapping: MeshPaymentExecutionResultSourceStateMapping? = nil
    ) throws -> [String: [String: String]] {
        var marooFields = [
            "adapterId": Self.adapterId,
            "asset": Self.okrwAssetSymbol,
            "executionKind": request.executionRequest.kind.rawValue,
            "requestHash": request.requestHash.value,
            "anchoringReference": request.requestAnchor.identifier.anchorId,
            "policyId": request.executionRequest.policyId,
            "policyHash": request.executionRequest.policyHash.value
        ]
        if let anchorTxHash = request.requestAnchor.identifier.transactionHash {
            marooFields["anchorTxHash"] = anchorTxHash
        }
        if let resultMapping {
            marooFields["providerOutcome"] = resultMapping.providerOutcome.rawValue
            marooFields["normalizedStatus"] = resultMapping.executionStatus.rawValue
            if let errorCode = resultMapping.errorCode {
                marooFields["errorCode"] = errorCode
            }
        }
        if let sourceStateMapping {
            marooFields["providerOutcome"] = sourceStateMapping.providerOutcome.rawValue
            marooFields["resultSource"] = sourceStateMapping.source.rawValue
            marooFields["normalizedStatus"] = sourceStateMapping.executionStatus.rawValue
            marooFields["sourceConfirmationBlocked"] = String(sourceStateMapping.isSourceBlockedFromConfirmation)
            if let errorCode = sourceStateMapping.errorCode {
                marooFields["errorCode"] = errorCode
            }
        }
        return [identity.provider: marooFields]
    }

    private func failedExecutionResult(
        request: MeshPaymentExecutionRequest,
        input: MeshMarooTestnetPaymentExecutionProviderInput,
        error: Error
    ) throws -> MeshPaymentExecutionResult {
        let capability = paymentExecutionCapability(for: request.executionRequest.kind)
        let capabilityError = try MeshPaymentExecutorCapabilityError.providerNeutral(error, capability: capability)
        let message = capabilityError.message
        let providerOutcome: MeshMarooTestnetPaymentExecutionProviderOutcome = capabilityError.failureKind == .policyDenied
            ? .policyDenied
            : .failure
        let status = providerOutcome.executionStatus
        var extensions = try providerExtensions(
            request: request,
            resultMapping: MeshMarooTestnetPaymentExecutionResultMapping(providerOutcome: providerOutcome)
        )
        extensions[identity.provider]?["failureKind"] = capabilityError.failureKind.rawValue
        extensions[identity.provider]?["errorCode"] = capabilityError.code
        extensions[identity.provider]?["providerOutcome"] = providerOutcome.rawValue
        extensions[identity.provider]?["normalizedStatus"] = status.rawValue
        if let blockerType = externalChainBlockerType(for: capabilityError.failureKind) {
            let evidence = try MeshExternalChainBlockerEvidence(
                blockerType: blockerType,
                identity: identity,
                endpoint: identity.rpcEndpoint,
                operation: request.executionRequest.kind == .payment ? "executePayment" : "executeTransfer",
                observedAt: input.submittedAt,
                message: message,
                requestHash: request.requestHash,
                requestNonce: request.executionRequest.requestAnchorMetadata.nonce,
                anchoringReference: request.requestAnchor.identifier.anchorId,
                txHash: request.requestAnchor.identifier.transactionHash
            )
            for (key, value) in evidence.providerExtensionFields {
                extensions[identity.provider]?[key] = value
            }
        }

        return try MeshPaymentExecutionResult(
            request: request,
            identity: identity,
            status: status,
            observedAt: input.submittedAt,
            message: message,
            errorPayload: MeshPaymentExecutionErrorPayload(
                code: capabilityError.code,
                message: message
            ),
            providerExtensions: extensions
        )
    }
}

private func externalChainBlockerType(
    for failureKind: MeshPaymentExecutorFailureKind
) -> MeshExternalChainBlockerType? {
    switch failureKind {
    case .network, .rpc, .transport:
        return .paymentConfirmationUnavailable
    case .contractUnavailable:
        return .okrwContractUnavailable
    case .policyDenied:
        return nil
    }
}

private func requirePaymentField(_ field: String, _ value: String) throws {
    _ = try normalizedPaymentField(field, value)
}

private func paymentExecutionCapability(
    for kind: MeshAgentWalletExecutionKind
) -> MeshPaymentExecutorCapability {
    kind == .payment ? .executePayment : .executeTransfer
}

private func normalizedPaymentIdentifier(_ field: String, _ value: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { throw MeshKitValidationError.invalidPaymentExecution(field) }
    try requirePaymentField(field, normalized)
    return normalized
}

private func normalizedPaymentField(_ field: String, _ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed == value else {
        throw MeshKitValidationError.invalidPaymentExecution(field)
    }
    guard trimmed.rangeOfCharacter(from: CharacterSet.newlines.union(.controlCharacters)) == nil else {
        throw MeshKitValidationError.invalidPaymentExecution(field)
    }
    return trimmed
}

private func validatePaymentHash(_ field: String, _ hash: MeshPayloadHash) throws {
    guard hash.algorithm.lowercased() == "sha256" else {
        throw MeshKitValidationError.unsupportedPayloadHashAlgorithm
    }
    guard hash.value.count == 64,
          hash.value.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdefABCDEF").inverted) == nil else {
        throw MeshKitValidationError.invalidPaymentExecution("\(field).value")
    }
}
