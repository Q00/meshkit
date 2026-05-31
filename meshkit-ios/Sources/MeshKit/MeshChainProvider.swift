import CryptoKit
import Foundation

public struct MeshChainProviderMetadata: Codable, Equatable, Sendable {
    public let provider: String
    public let network: String
    public let chainId: String
    public var providerName: String { provider }
    public var networkIdentity: String { network }

    public init(provider: String, network: String, chainId: String) throws {
        self.provider = try MeshChainProviderIdentity.normalizedIdentifier("provider", provider)
        self.network = try MeshChainProviderIdentity.normalizedIdentifier("network", network)
        self.chainId = try MeshChainProviderIdentity.normalizedIdentifier("chainId", chainId)
        try validate()
    }

    public init(identity: MeshChainProviderIdentity) {
        self.provider = identity.provider
        self.network = identity.network
        self.chainId = identity.chainId
    }

    public func validate() throws {
        try MeshChainProviderIdentity.validateIdentifier("provider", provider)
        try MeshChainProviderIdentity.validateIdentifier("network", network)
        try MeshChainProviderIdentity.validateIdentifier("chainId", chainId)
    }
}

public struct MeshChainProviderEndpointConfiguration: Codable, Equatable, Sendable {
    public let rpcEndpoint: URL
    public let explorerBaseURL: URL?

    public var explorerBaseUrl: URL? { explorerBaseURL }

    public init(rpcEndpoint: URL, explorerBaseURL: URL? = nil) throws {
        self.rpcEndpoint = try MeshChainProviderIdentity.normalizedNetworkURL("rpcEndpoint", rpcEndpoint)
        self.explorerBaseURL = try explorerBaseURL.map {
            try MeshChainProviderIdentity.normalizedNetworkURL("explorerBaseURL", $0)
        }
        try validate()
    }

    public static func resolved(
        defaults: MeshChainProviderEndpointConfiguration,
        rpcEndpoint configuredRPCEndpoint: URL? = nil,
        explorerBaseURL configuredExplorerBaseURL: URL? = nil
    ) throws -> MeshChainProviderEndpointConfiguration {
        try MeshChainProviderEndpointConfiguration(
            rpcEndpoint: configuredRPCEndpoint ?? defaults.rpcEndpoint,
            explorerBaseURL: configuredExplorerBaseURL ?? defaults.explorerBaseURL
        )
    }

    public static func configured(
        rpcEndpoint configuredRPCEndpoint: URL?,
        explorerBaseURL configuredExplorerBaseURL: URL? = nil
    ) throws -> MeshChainProviderEndpointConfiguration {
        guard let configuredRPCEndpoint else {
            throw MeshKitValidationError.invalidChainProviderIdentity("rpcEndpoint")
        }
        return try MeshChainProviderEndpointConfiguration(
            rpcEndpoint: configuredRPCEndpoint,
            explorerBaseURL: configuredExplorerBaseURL
        )
    }

    public func validate() throws {
        try MeshChainProviderIdentity.validateNetworkURL("rpcEndpoint", rpcEndpoint)
        if let explorerBaseURL {
            try MeshChainProviderIdentity.validateNetworkURL("explorerBaseURL", explorerBaseURL)
        }
    }

    fileprivate init(validatedRPCEndpoint: URL, validatedExplorerBaseURL: URL?) {
        self.rpcEndpoint = validatedRPCEndpoint
        self.explorerBaseURL = validatedExplorerBaseURL
    }
}

public struct MeshChainProviderIdentity: Codable, Equatable, Sendable {
    public let providerName: String
    public let networkIdentity: String
    public let chainId: String
    public let rpcEndpoint: URL
    public let explorerBaseURL: URL?

    public var provider: String { providerName }
    public var network: String { networkIdentity }
    public var explorerBaseUrl: URL? { explorerBaseURL }
    public var metadata: MeshChainProviderMetadata { MeshChainProviderMetadata(identity: self) }
    public var endpointConfiguration: MeshChainProviderEndpointConfiguration {
        MeshChainProviderEndpointConfiguration(
            validatedRPCEndpoint: rpcEndpoint,
            validatedExplorerBaseURL: explorerBaseURL
        )
    }

    public init(
        providerName: String,
        networkIdentity: String,
        chainId: String,
        rpcEndpoint: URL,
        explorerBaseURL: URL? = nil
    ) throws {
        self.providerName = try Self.normalizedIdentifier("providerName", providerName)
        self.networkIdentity = try Self.normalizedIdentifier("networkIdentity", networkIdentity)
        self.chainId = try Self.normalizedIdentifier("chainId", chainId)
        self.rpcEndpoint = try Self.normalizedNetworkURL("rpcEndpoint", rpcEndpoint)
        self.explorerBaseURL = try explorerBaseURL.map { try Self.normalizedNetworkURL("explorerBaseURL", $0) }
        try validate()
    }

    public init(
        providerName: String,
        networkIdentity: String,
        chainId: String,
        endpointConfiguration: MeshChainProviderEndpointConfiguration
    ) throws {
        try self.init(
            providerName: providerName,
            networkIdentity: networkIdentity,
            chainId: chainId,
            rpcEndpoint: endpointConfiguration.rpcEndpoint,
            explorerBaseURL: endpointConfiguration.explorerBaseURL
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let providerName = try container.decodeString(preferred: .provider, fallback: .providerName)
        let networkIdentity = try container.decodeString(preferred: .network, fallback: .networkIdentity)
        let chainId = try container.decode(String.self, forKey: .chainId)
        let rpcEndpoint = try container.decode(URL.self, forKey: .rpcEndpoint)
        let explorerBaseURL = try container.decodeIfPresent(URL.self, forKey: .explorerBaseUrl)
            ?? container.decodeIfPresent(URL.self, forKey: .explorerBaseURL)
        try self.init(
            providerName: providerName,
            networkIdentity: networkIdentity,
            chainId: chainId,
            rpcEndpoint: rpcEndpoint,
            explorerBaseURL: explorerBaseURL
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(providerName, forKey: .provider)
        try container.encode(networkIdentity, forKey: .network)
        try container.encode(chainId, forKey: .chainId)
        try container.encode(rpcEndpoint, forKey: .rpcEndpoint)
        try container.encodeIfPresent(explorerBaseURL, forKey: .explorerBaseUrl)
    }

    public func validate() throws {
        try Self.validateIdentifier("providerName", providerName)
        try Self.validateIdentifier("networkIdentity", networkIdentity)
        try Self.validateIdentifier("chainId", chainId)
        try Self.validateNetworkURL("rpcEndpoint", rpcEndpoint)
        if let explorerBaseURL {
            try Self.validateNetworkURL("explorerBaseURL", explorerBaseURL)
        }
    }

    public func explorerURL(transactionHash: String) throws -> URL {
        try explorerURL(for: .transaction(hash: transactionHash))
    }

    public func explorerURL(accountAddress: String) throws -> URL {
        try explorerURL(for: .account(address: accountAddress))
    }

    public func explorerURL(address: String) throws -> URL {
        try explorerURL(for: .address(value: address))
    }

    public func explorerURL(block: String) throws -> URL {
        try explorerURL(for: .block(value: block))
    }

    public func explorerURL(for entity: MeshChainExplorerEntity) throws -> URL {
        guard let explorerBaseURL else { throw MeshKitValidationError.chainProviderExplorerUnavailable }
        try entity.validate()
        return explorerBaseURL
            .appendingPathComponent(entity.pathComponent)
            .appendingPathComponent(entity.value)
    }

    static func validateIdentifier(_ field: String, _ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == value else {
            throw MeshKitValidationError.invalidChainProviderIdentity(field)
        }
        guard value.rangeOfCharacter(from: CharacterSet.newlines.union(.controlCharacters)) == nil else {
            throw MeshKitValidationError.invalidChainProviderIdentity(field)
        }
    }

    static func validateExplorerIdentifier(_ field: String, _ value: String) throws {
        try validateIdentifier(field, value)
        guard value.rangeOfCharacter(from: CharacterSet(charactersIn: "/?#")) == nil else {
            throw MeshKitValidationError.invalidChainProviderIdentity(field)
        }
    }

    private func validateNetworkURL(_ field: String, _ url: URL) throws {
        try Self.validateNetworkURL(field, url)
    }

    static func validateNetworkURL(_ field: String, _ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw MeshKitValidationError.invalidChainProviderIdentity(field)
        }
        guard let host = url.host, !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeshKitValidationError.invalidChainProviderIdentity(field)
        }
        guard url.fragment == nil else {
            throw MeshKitValidationError.invalidChainProviderIdentity(field)
        }
    }

    fileprivate static func normalizedIdentifier(_ field: String, _ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            throw MeshKitValidationError.invalidChainProviderIdentity(field)
        }
        guard normalized.rangeOfCharacter(from: CharacterSet.newlines.union(.controlCharacters)) == nil else {
            throw MeshKitValidationError.invalidChainProviderIdentity(field)
        }
        return normalized
    }

    fileprivate static func normalizedNetworkURL(_ field: String, _ url: URL) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw MeshKitValidationError.invalidChainProviderIdentity(field)
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.path == "/" {
            components.path = ""
        }
        guard let normalized = components.url else {
            throw MeshKitValidationError.invalidChainProviderIdentity(field)
        }
        return normalized
    }

    fileprivate enum CodingKeys: String, CodingKey {
        case provider
        case network
        case chainId
        case rpcEndpoint
        case explorerBaseUrl
        case providerName
        case networkIdentity
        case explorerBaseURL
    }
}

public enum MeshChainExplorerEntity: Equatable, Sendable {
    case transaction(hash: String)
    case account(address: String)
    case address(value: String)
    case block(value: String)

    fileprivate var pathComponent: String {
        switch self {
        case .transaction:
            return "tx"
        case .account:
            return "account"
        case .address:
            return "address"
        case .block:
            return "block"
        }
    }

    fileprivate var value: String {
        switch self {
        case .transaction(let hash):
            return hash
        case .account(let address):
            return address
        case .address(let value):
            return value
        case .block(let value):
            return value
        }
    }

    fileprivate func validate() throws {
        switch self {
        case .transaction(let hash):
            try MeshChainProviderIdentity.validateExplorerIdentifier("transactionHash", hash)
        case .account(let address):
            try MeshChainProviderIdentity.validateExplorerIdentifier("accountAddress", address)
        case .address(let value):
            try MeshChainProviderIdentity.validateExplorerIdentifier("address", value)
        case .block(let value):
            try MeshChainProviderIdentity.validateExplorerIdentifier("block", value)
        }
    }
}

public enum MeshChainProviderCapability: String, Codable, CaseIterable, Comparable, Sendable {
    case anchorSignedRequest
    case constructExplorerURL
    case createRequestAnchorReference
    case identifyNetwork
    case loadProviderConfiguration
    case checkHealth
    case lookupRequestAnchorStatus
    case resolveRequestAnchorHash
    case signRequestAnchorReference
    case lookupTransaction
    case lookupProof

    public static func < (lhs: MeshChainProviderCapability, rhs: MeshChainProviderCapability) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum MeshChainProviderConnectionStatus: String, Codable, Equatable, Sendable {
    case configured
    case connected
    case unavailable
}

public enum MeshChainProviderHealthStatus: String, Codable, Equatable, Sendable {
    case healthy
    case degraded
    case unavailable
}

public enum MeshExternalChainBlockerType: String, Codable, CaseIterable, Equatable, Sendable {
    case rpcUnavailable = "rpc_unavailable"
    case explorerUnavailable = "explorer_unavailable"
    case faucetUnavailable = "faucet_unavailable"
    case okrwContractUnavailable = "okrw_contract_unavailable"
    case fundedWalletUnavailable = "funded_wallet_unavailable"
    case paymentConfirmationUnavailable = "payment_confirmation_unavailable"
    case requestAnchorUnavailable = "request_anchor_unavailable"
}

public struct MeshExternalChainBlockerEvidence: Codable, Equatable, Sendable {
    public static let exitCondition = "BlockedByExternalChain"

    public let exitCondition: String
    public let blockerType: MeshExternalChainBlockerType
    public let identity: MeshChainProviderIdentity
    public let endpoint: URL?
    public let operation: String
    public let observedAt: String
    public let message: String
    public let requestHash: MeshPayloadHash?
    public let requestNonce: String?
    public let anchoringReference: String?
    public let txHash: String?

    public init(
        blockerType: MeshExternalChainBlockerType,
        identity: MeshChainProviderIdentity,
        endpoint: URL? = nil,
        operation: String,
        observedAt: String,
        message: String,
        requestHash: MeshPayloadHash? = nil,
        requestNonce: String? = nil,
        anchoringReference: String? = nil,
        txHash: String? = nil
    ) throws {
        self.exitCondition = Self.exitCondition
        self.blockerType = blockerType
        self.identity = identity
        self.endpoint = endpoint
        self.operation = try Self.normalizedEvidenceField("operation", operation)
        self.observedAt = try MeshChainProviderConnection.normalizedTimestamp(observedAt)
        self.message = try Self.normalizedEvidenceField("message", message)
        self.requestHash = requestHash
        self.requestNonce = try requestNonce.map { try Self.normalizedEvidenceField("requestNonce", $0) }
        self.anchoringReference = try anchoringReference.map { try Self.normalizedEvidenceField("anchoringReference", $0) }
        self.txHash = try txHash.map { try Self.normalizedEvidenceField("txHash", $0) }
        try validate()
    }

    public init(
        health: MeshChainProviderHealth,
        blockerType: MeshExternalChainBlockerType = .rpcUnavailable,
        operation: String = "checkHealth"
    ) throws {
        try self.init(
            blockerType: blockerType,
            identity: health.identity,
            endpoint: health.rpcEndpoint,
            operation: operation,
            observedAt: health.checkedAt,
            message: health.message ?? "chain provider unavailable"
        )
    }

    public func validate() throws {
        guard exitCondition == Self.exitCondition else {
            throw MeshKitValidationError.invalidChainProviderIdentity("exitCondition")
        }
        try identity.validate()
        if let endpoint {
            try MeshChainProviderIdentity.validateNetworkURL("endpoint", endpoint)
        }
        try Self.requireEvidenceField("operation", operation)
        try Self.requireEvidenceField("message", message)
        try requestHash.map { try Self.validateHash("requestHash", $0) }
        try requestNonce.map { try Self.requireEvidenceField("requestNonce", $0) }
        try anchoringReference.map { try Self.requireEvidenceField("anchoringReference", $0) }
        try txHash.map { try Self.requireEvidenceField("txHash", $0) }
    }

    public var providerExtensionFields: [String: String] {
        var fields = [
            "exitCondition": exitCondition,
            "blockerType": blockerType.rawValue,
            "operation": operation,
            "observedAt": observedAt,
            "message": message
        ]
        if let endpoint {
            fields["endpoint"] = endpoint.absoluteString
        }
        if let requestHash {
            fields["requestHash"] = requestHash.value
        }
        if let requestNonce {
            fields["requestNonce"] = requestNonce
        }
        if let anchoringReference {
            fields["anchoringReference"] = anchoringReference
        }
        if let txHash {
            fields["txHash"] = txHash
        }
        return fields
    }

    fileprivate static func normalizedEvidenceField(_ field: String, _ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MeshKitValidationError.invalidChainProviderIdentity(field)
        }
        let normalized = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw MeshKitValidationError.invalidChainProviderIdentity(field)
        }
        return normalized
    }

    fileprivate static func requireEvidenceField(_ field: String, _ value: String) throws {
        _ = try normalizedEvidenceField(field, value)
    }

    private static func validateHash(_ field: String, _ hash: MeshPayloadHash) throws {
        guard hash.algorithm.lowercased() == "sha256" else {
            throw MeshKitValidationError.invalidChainProviderIdentity(field)
        }
        guard hash.value.count == 64,
              hash.value.allSatisfy({ $0.isHexDigit }) else {
            throw MeshKitValidationError.invalidChainProviderIdentity("\(field).value")
        }
    }
}

public struct MeshExternalChainEndpointAvailabilityCheck: Codable, Equatable, Sendable {
    public let blockerType: MeshExternalChainBlockerType
    public let identity: MeshChainProviderIdentity
    public let endpoint: URL
    public let operation: String

    public init(
        blockerType: MeshExternalChainBlockerType,
        identity: MeshChainProviderIdentity,
        endpoint: URL,
        operation: String
    ) throws {
        self.blockerType = blockerType
        self.identity = identity
        self.endpoint = endpoint
        self.operation = try MeshExternalChainBlockerEvidence.normalizedEvidenceField("operation", operation)
        try validate()
    }

    public func validate() throws {
        try identity.validate()
        try MeshChainProviderIdentity.validateNetworkURL("endpoint", endpoint)
        try MeshExternalChainBlockerEvidence.requireEvidenceField("operation", operation)
    }

    public func blockerEvidence(
        observedAt: String,
        message: String,
        requestHash: MeshPayloadHash? = nil,
        requestNonce: String? = nil,
        anchoringReference: String? = nil,
        txHash: String? = nil
    ) throws -> MeshExternalChainBlockerEvidence {
        try MeshExternalChainBlockerEvidence(
            blockerType: blockerType,
            identity: identity,
            endpoint: endpoint,
            operation: operation,
            observedAt: observedAt,
            message: message,
            requestHash: requestHash,
            requestNonce: requestNonce,
            anchoringReference: anchoringReference,
            txHash: txHash
        )
    }

    public func evaluateHTTPStatus(
        _ httpStatus: Int?,
        observedAt: String,
        errorMessage: String? = nil
    ) throws -> MeshExternalChainBlockerEvidence? {
        if let httpStatus, (200..<400).contains(httpStatus) {
            return nil
        }

        let message: String
        if let errorMessage {
            message = errorMessage
        } else if let httpStatus {
            message = "\(operation) unavailable with http status \(httpStatus)"
        } else {
            message = "\(operation) unavailable"
        }

        return try blockerEvidence(
            observedAt: observedAt,
            message: message
        )
    }
}

public struct MeshChainProviderConfiguration: Codable, Equatable, Sendable {
    public let identity: MeshChainProviderIdentity
    public let capabilities: [MeshChainProviderCapability]
    public var endpointConfiguration: MeshChainProviderEndpointConfiguration {
        identity.endpointConfiguration
    }

    public init(identity: MeshChainProviderIdentity, capabilities: [MeshChainProviderCapability]) throws {
        self.identity = identity
        self.capabilities = Self.normalizedCapabilities(capabilities)
        try validate()
    }

    public func supports(_ capability: MeshChainProviderCapability) -> Bool {
        capabilities.contains(capability)
    }

    public func require(_ capability: MeshChainProviderCapability) throws {
        guard supports(capability) else { throw MeshKitValidationError.unsupportedCapability }
    }

    public func validate() throws {
        try identity.validate()
        guard !capabilities.isEmpty else { throw MeshKitValidationError.unsupportedCapability }
    }

    private static func normalizedCapabilities(_ capabilities: [MeshChainProviderCapability]) -> [MeshChainProviderCapability] {
        Array(Set(capabilities)).sorted()
    }
}

public struct MeshChainProviderConnection: Codable, Equatable, Sendable {
    public let identity: MeshChainProviderIdentity
    public let status: MeshChainProviderConnectionStatus
    public let capabilities: [MeshChainProviderCapability]
    public let rpcEndpoint: URL
    public let observedNetwork: String?
    public let checkedAt: String

    public init(
        identity: MeshChainProviderIdentity,
        status: MeshChainProviderConnectionStatus,
        capabilities: [MeshChainProviderCapability],
        rpcEndpoint: URL? = nil,
        observedNetwork: String? = nil,
        checkedAt: String
    ) throws {
        self.identity = identity
        self.status = status
        self.capabilities = Array(Set(capabilities)).sorted()
        self.rpcEndpoint = rpcEndpoint ?? identity.rpcEndpoint
        self.observedNetwork = try observedNetwork.map { try Self.normalizedOptionalIdentifier("observedNetwork", $0) }
        self.checkedAt = try Self.normalizedTimestamp(checkedAt)
        try validate()
    }

    public func validate() throws {
        try identity.validate()
        try MeshChainProviderIdentity.validateNetworkURL("rpcEndpoint", rpcEndpoint)
        guard !capabilities.isEmpty else { throw MeshKitValidationError.unsupportedCapability }
        if status == .connected {
            guard observedNetwork == nil || observedNetwork == identity.network else {
                throw MeshKitValidationError.invalidChainProviderIdentity("observedNetwork")
            }
        }
    }

    private static func normalizedOptionalIdentifier(_ field: String, _ value: String) throws -> String {
        try MeshChainProviderIdentity.normalizedIdentifier(field, value)
    }

    fileprivate static func normalizedTimestamp(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == value else {
            throw MeshKitValidationError.invalidChainProviderIdentity("checkedAt")
        }
        guard trimmed.rangeOfCharacter(from: CharacterSet.newlines.union(.controlCharacters)) == nil else {
            throw MeshKitValidationError.invalidChainProviderIdentity("checkedAt")
        }
        return trimmed
    }
}

public struct MeshChainProviderHealth: Codable, Equatable, Sendable {
    public let identity: MeshChainProviderIdentity
    public let status: MeshChainProviderHealthStatus
    public let capabilities: [MeshChainProviderCapability]
    public let rpcEndpoint: URL
    public let checkedAt: String
    public let latencyMilliseconds: Int?
    public let latestBlockHeight: Int?
    public let message: String?

    public init(
        identity: MeshChainProviderIdentity,
        status: MeshChainProviderHealthStatus,
        capabilities: [MeshChainProviderCapability],
        rpcEndpoint: URL? = nil,
        checkedAt: String,
        latencyMilliseconds: Int? = nil,
        latestBlockHeight: Int? = nil,
        message: String? = nil
    ) throws {
        self.identity = identity
        self.status = status
        self.capabilities = Array(Set(capabilities)).sorted()
        self.rpcEndpoint = rpcEndpoint ?? identity.rpcEndpoint
        self.checkedAt = try MeshChainProviderConnection.normalizedTimestamp(checkedAt)
        self.latencyMilliseconds = latencyMilliseconds
        self.latestBlockHeight = latestBlockHeight
        self.message = try message.map { try Self.normalizedMessage($0) }
        try validate()
    }

    public func validate() throws {
        try identity.validate()
        try MeshChainProviderIdentity.validateNetworkURL("rpcEndpoint", rpcEndpoint)
        guard !capabilities.isEmpty else { throw MeshKitValidationError.unsupportedCapability }
        if let latencyMilliseconds, latencyMilliseconds < 0 {
            throw MeshKitValidationError.invalidChainProviderIdentity("latencyMilliseconds")
        }
        if let latestBlockHeight, latestBlockHeight < 0 {
            throw MeshKitValidationError.invalidChainProviderIdentity("latestBlockHeight")
        }
        if status == .healthy {
            guard latencyMilliseconds != nil else {
                throw MeshKitValidationError.invalidChainProviderIdentity("latencyMilliseconds")
            }
            guard latestBlockHeight != nil else {
                throw MeshKitValidationError.invalidChainProviderIdentity("latestBlockHeight")
            }
        }
    }

    private static func normalizedMessage(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == value else {
            throw MeshKitValidationError.invalidChainProviderIdentity("message")
        }
        guard trimmed.rangeOfCharacter(from: CharacterSet.newlines.union(.controlCharacters)) == nil else {
            throw MeshKitValidationError.invalidChainProviderIdentity("message")
        }
        return trimmed
    }
}

public struct MeshChainProviderStatusInspection: Codable, Equatable, Sendable {
    public let configuration: MeshChainProviderConfiguration
    public let connection: MeshChainProviderConnection
    public let health: MeshChainProviderHealth

    public init(
        configuration: MeshChainProviderConfiguration,
        connection: MeshChainProviderConnection,
        health: MeshChainProviderHealth
    ) throws {
        self.configuration = configuration
        self.connection = connection
        self.health = health
        try validate()
    }

    public func validate() throws {
        try configuration.validate()
        try connection.validate()
        try health.validate()
        guard configuration.identity == connection.identity,
              configuration.identity == health.identity else {
            throw MeshKitValidationError.invalidChainProviderIdentity("statusInspection.identity")
        }
        guard configuration.endpointConfiguration.rpcEndpoint == connection.rpcEndpoint,
              configuration.endpointConfiguration.rpcEndpoint == health.rpcEndpoint else {
            throw MeshKitValidationError.invalidChainProviderIdentity("statusInspection.rpcEndpoint")
        }
        guard configuration.capabilities == connection.capabilities,
              configuration.capabilities == health.capabilities else {
            throw MeshKitValidationError.invalidChainProviderIdentity("statusInspection.capabilities")
        }
    }
}

public struct MeshChainTransactionLookup: Codable, Equatable, Sendable {
    public let identity: MeshChainProviderIdentity
    public let reference: MeshChainProofReference
    public let status: MeshChainProofStatus
    public let transactionHash: String
    public let explorerURL: URL?
    public let blockHeight: Int?
    public let confirmations: Int?
    public let checkedAt: String
    public let providerExtensions: [String: [String: String]]

    public init(
        identity: MeshChainProviderIdentity,
        reference: MeshChainProofReference,
        status: MeshChainProofStatus,
        transactionHash: String? = nil,
        explorerURL: URL? = nil,
        blockHeight: Int? = nil,
        confirmations: Int? = nil,
        checkedAt: String,
        providerExtensions: [String: [String: String]] = [:]
    ) throws {
        self.identity = identity
        self.reference = reference
        self.status = status
        self.transactionHash = try Self.normalizedLookupField("transactionHash", transactionHash ?? reference.value)
        self.explorerURL = explorerURL ?? reference.explorerUrl
        self.blockHeight = blockHeight
        self.confirmations = confirmations
        self.checkedAt = try MeshChainProviderConnection.normalizedTimestamp(checkedAt)
        self.providerExtensions = try Self.normalizedProviderExtensions(providerExtensions)
        try validate()
    }

    public func validate() throws {
        try identity.validate()
        try reference.validate()
        guard reference.referenceType == .transaction else {
            throw MeshKitValidationError.invalidChainProof("referenceType")
        }
        guard reference.provider == identity.provider,
              reference.network == identity.network,
              reference.chainId == identity.chainId else {
            throw MeshKitValidationError.signatureMismatch("chain transaction lookup provider mismatch")
        }
        try Self.requireLookupField("transactionHash", transactionHash)
        if let explorerURL {
            try MeshChainProviderIdentity.validateNetworkURL("explorerURL", explorerURL)
        }
        if let blockHeight, blockHeight < 0 {
            throw MeshKitValidationError.invalidChainProviderIdentity("blockHeight")
        }
        if let confirmations, confirmations < 0 {
            throw MeshKitValidationError.invalidChainProviderIdentity("confirmations")
        }
        _ = try Self.normalizedProviderExtensions(providerExtensions)
    }

    fileprivate static func normalizedProviderExtensions(
        _ providerExtensions: [String: [String: String]]
    ) throws -> [String: [String: String]] {
        var normalized: [String: [String: String]] = [:]
        for (provider, fields) in providerExtensions {
            let normalizedProvider = try normalizedLookupComponent("providerExtensions.provider", provider)
            var normalizedFields: [String: String] = [:]
            for (key, value) in fields {
                let normalizedKey = try normalizedLookupField("providerExtensions.key", key)
                normalizedFields[normalizedKey] = try normalizedLookupField(
                    "providerExtensions.\(normalizedKey)",
                    value
                )
            }
            normalized[normalizedProvider] = normalizedFields
        }
        return normalized
    }

    fileprivate static func normalizedLookupComponent(_ field: String, _ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { throw MeshKitValidationError.invalidChainProof(field) }
        try requireLookupField(field, normalized)
        return normalized
    }

    fileprivate static func normalizedLookupField(_ field: String, _ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == value else {
            throw MeshKitValidationError.invalidChainProof(field)
        }
        try requireLookupField(field, trimmed)
        if trimmed.hasPrefix("0X") {
            return "0x" + String(trimmed.dropFirst(2)).lowercased()
        }
        return trimmed
    }

    fileprivate static func requireLookupField(_ field: String, _ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeshKitValidationError.invalidChainProof(field)
        }
        guard value.rangeOfCharacter(from: CharacterSet.newlines.union(.controlCharacters)) == nil,
              value.rangeOfCharacter(from: CharacterSet(charactersIn: "/?#")) == nil else {
            throw MeshKitValidationError.invalidChainProof(field)
        }
    }
}

public struct MeshChainProofLookup: Codable, Equatable, Sendable {
    public let identity: MeshChainProviderIdentity
    public let reference: MeshChainProofReference
    public let status: MeshChainProofStatus
    public let proofType: MeshChainProofType?
    public let transactionReference: MeshChainProofReference?
    public let checkedAt: String
    public let providerExtensions: [String: [String: String]]

    public init(
        identity: MeshChainProviderIdentity,
        reference: MeshChainProofReference,
        status: MeshChainProofStatus,
        proofType: MeshChainProofType? = nil,
        transactionReference: MeshChainProofReference? = nil,
        checkedAt: String,
        providerExtensions: [String: [String: String]] = [:]
    ) throws {
        self.identity = identity
        self.reference = reference
        self.status = status
        self.proofType = proofType
        self.transactionReference = transactionReference
        self.checkedAt = try MeshChainProviderConnection.normalizedTimestamp(checkedAt)
        self.providerExtensions = try MeshChainTransactionLookup.normalizedProviderExtensions(providerExtensions)
        try validate()
    }

    public func validate() throws {
        try identity.validate()
        try reference.validate()
        guard reference.referenceType == .proof else {
            throw MeshKitValidationError.invalidChainProof("referenceType")
        }
        guard reference.provider == identity.provider,
              reference.network == identity.network,
              reference.chainId == identity.chainId else {
            throw MeshKitValidationError.signatureMismatch("chain proof lookup provider mismatch")
        }
        if let transactionReference {
            try transactionReference.validate()
            guard transactionReference.referenceType == .transaction else {
                throw MeshKitValidationError.invalidChainProof("transactionReference")
            }
            guard transactionReference.provider == identity.provider,
                  transactionReference.network == identity.network,
                  transactionReference.chainId == identity.chainId else {
                throw MeshKitValidationError.signatureMismatch("chain proof transaction provider mismatch")
            }
        }
        _ = try MeshChainTransactionLookup.normalizedProviderExtensions(providerExtensions)
    }
}

public struct MeshChainProviderStatusInspectionModule<Provider: MeshChainProvider>: Sendable {
    public let provider: Provider

    public init(provider: Provider) {
        self.provider = provider
    }

    public func inspectStatus(checkedAt: String) async throws -> MeshChainProviderStatusInspection {
        let configuration = try provider.loadProviderConfiguration()
        try configuration.require(.loadProviderConfiguration)
        try configuration.require(.checkHealth)
        let connection = try await provider.connect(checkedAt: checkedAt)
        let health = try await provider.checkHealth(checkedAt: checkedAt)
        return try MeshChainProviderStatusInspection(
            configuration: configuration,
            connection: connection,
            health: health
        )
    }
}

public protocol MeshChainProvider: Sendable {
    var identity: MeshChainProviderIdentity { get }
    var metadata: MeshChainProviderMetadata { get }
    var capabilities: [MeshChainProviderCapability] { get }

    func loadProviderConfiguration() throws -> MeshChainProviderConfiguration
    func identifyNetwork() throws -> MeshChainProviderIdentity
    func connect(checkedAt: String) async throws -> MeshChainProviderConnection
    func checkHealth(checkedAt: String) async throws -> MeshChainProviderHealth
    func lookupTransaction(
        reference: MeshChainProofReference,
        checkedAt: String
    ) async throws -> MeshChainTransactionLookup
    func lookupProof(
        reference: MeshChainProofReference,
        checkedAt: String
    ) async throws -> MeshChainProofLookup
}

public extension MeshChainProvider {
    var metadata: MeshChainProviderMetadata { identity.metadata }

    func explorerURL(for entity: MeshChainExplorerEntity) throws -> URL {
        let configuration = try loadProviderConfiguration()
        try configuration.require(.constructExplorerURL)
        return try configuration.identity.explorerURL(for: entity)
    }

    func explorerURL(transactionHash: String) throws -> URL {
        try explorerURL(for: .transaction(hash: transactionHash))
    }

    func explorerURL(accountAddress: String) throws -> URL {
        try explorerURL(for: .account(address: accountAddress))
    }

    func explorerURL(address: String) throws -> URL {
        try explorerURL(for: .address(value: address))
    }

    func explorerURL(block: String) throws -> URL {
        try explorerURL(for: .block(value: block))
    }

    func lookupTransaction(
        reference: MeshChainProofReference,
        checkedAt: String
    ) async throws -> MeshChainTransactionLookup {
        let configuration = try loadProviderConfiguration()
        try configuration.require(.lookupTransaction)
        try reference.validate()
        _ = try MeshChainProviderConnection.normalizedTimestamp(checkedAt)
        throw MeshKitValidationError.invalidChainProviderIdentity("transactionLookup")
    }

    func lookupProof(
        reference: MeshChainProofReference,
        checkedAt: String
    ) async throws -> MeshChainProofLookup {
        let configuration = try loadProviderConfiguration()
        try configuration.require(.lookupProof)
        try reference.validate()
        _ = try MeshChainProviderConnection.normalizedTimestamp(checkedAt)
        throw MeshKitValidationError.invalidChainProviderIdentity("proofLookup")
    }
}

public struct MeshMarooTestnetChainProvider: MeshChainProvider {
    public static let providerName = "maroo"
    public static let networkIdentity = "maroo-testnet"
    public static let chainId = "maroo-testnet-1"
    public static let defaultRPCEndpoint = URL(string: "https://rpc-testnet.maroo.io")!
    public static let defaultExplorerBaseURL = URL(string: "https://explorer-testnet.maroo.io")!
    public static let defaultFaucetURL = URL(string: "https://faucet.maroo.io")!
    public static let defaultEndpointConfiguration = try! MeshChainProviderEndpointConfiguration(
        rpcEndpoint: defaultRPCEndpoint,
        explorerBaseURL: defaultExplorerBaseURL
    )

    public let identity: MeshChainProviderIdentity
    public let capabilities: [MeshChainProviderCapability]
    public let observedNetwork: String?
    public let healthStatus: MeshChainProviderHealthStatus
    public let latestBlockHeight: Int?
    public let latencyMilliseconds: Int?
    public let healthMessage: String?

    public init(
        rpcEndpoint: URL = MeshMarooTestnetChainProvider.defaultRPCEndpoint,
        explorerBaseURL: URL = MeshMarooTestnetChainProvider.defaultExplorerBaseURL,
        capabilities: [MeshChainProviderCapability] = MeshMarooTestnetChainProvider.defaultCapabilities,
        observedNetwork: String? = nil,
        healthStatus: MeshChainProviderHealthStatus = .unavailable,
        latestBlockHeight: Int? = nil,
        latencyMilliseconds: Int? = nil,
        healthMessage: String? = "maroo testnet rpc not checked"
    ) throws {
        try self.init(
            endpointConfiguration: MeshChainProviderEndpointConfiguration.resolved(
                defaults: Self.defaultEndpointConfiguration,
                rpcEndpoint: rpcEndpoint,
                explorerBaseURL: explorerBaseURL
            ),
            capabilities: capabilities,
            observedNetwork: observedNetwork,
            healthStatus: healthStatus,
            latestBlockHeight: latestBlockHeight,
            latencyMilliseconds: latencyMilliseconds,
            healthMessage: healthMessage
        )
    }

    public init(
        configuredRPCEndpoint: URL?,
        configuredExplorerBaseURL: URL? = MeshMarooTestnetChainProvider.defaultExplorerBaseURL,
        capabilities: [MeshChainProviderCapability] = MeshMarooTestnetChainProvider.defaultCapabilities,
        observedNetwork: String? = nil,
        healthStatus: MeshChainProviderHealthStatus = .unavailable,
        latestBlockHeight: Int? = nil,
        latencyMilliseconds: Int? = nil,
        healthMessage: String? = "maroo testnet rpc not checked"
    ) throws {
        try self.init(
            endpointConfiguration: MeshChainProviderEndpointConfiguration.configured(
                rpcEndpoint: configuredRPCEndpoint,
                explorerBaseURL: configuredExplorerBaseURL
            ),
            capabilities: capabilities,
            observedNetwork: observedNetwork,
            healthStatus: healthStatus,
            latestBlockHeight: latestBlockHeight,
            latencyMilliseconds: latencyMilliseconds,
            healthMessage: healthMessage
        )
    }

    private init(
        endpointConfiguration: MeshChainProviderEndpointConfiguration,
        capabilities: [MeshChainProviderCapability],
        observedNetwork: String?,
        healthStatus: MeshChainProviderHealthStatus,
        latestBlockHeight: Int?,
        latencyMilliseconds: Int?,
        healthMessage: String?
    ) throws {
        self.identity = try MeshChainProviderIdentity(
            providerName: Self.providerName,
            networkIdentity: Self.networkIdentity,
            chainId: Self.chainId,
            endpointConfiguration: endpointConfiguration
        )
        self.capabilities = Self.normalizedCapabilities(capabilities)
        self.observedNetwork = try observedNetwork.map {
            try MeshChainProviderIdentity.normalizedIdentifier("observedNetwork", $0)
        }
        self.healthStatus = healthStatus
        self.latestBlockHeight = latestBlockHeight
        self.latencyMilliseconds = latencyMilliseconds
        self.healthMessage = healthMessage
        try loadProviderConfiguration().validate()
    }

    public func loadProviderConfiguration() throws -> MeshChainProviderConfiguration {
        try MeshChainProviderConfiguration(identity: identity, capabilities: capabilities)
    }

    public func identifyNetwork() throws -> MeshChainProviderIdentity {
        try loadProviderConfiguration().require(.identifyNetwork)
        return identity
    }

    public func connect(checkedAt: String) async throws -> MeshChainProviderConnection {
        try loadProviderConfiguration().require(.loadProviderConfiguration)
        return try MeshChainProviderConnection(
            identity: identity,
            status: .configured,
            capabilities: capabilities,
            observedNetwork: observedNetwork,
            checkedAt: checkedAt
        )
    }

    public func checkHealth(checkedAt: String) async throws -> MeshChainProviderHealth {
        try loadProviderConfiguration().require(.checkHealth)
        return try MeshChainProviderHealth(
            identity: identity,
            status: healthStatus,
            capabilities: capabilities,
            checkedAt: checkedAt,
            latencyMilliseconds: latencyMilliseconds,
            latestBlockHeight: latestBlockHeight,
            message: healthMessage
        )
    }

    public func lookupTransaction(
        reference: MeshChainProofReference,
        checkedAt: String
    ) async throws -> MeshChainTransactionLookup {
        try loadProviderConfiguration().require(.lookupTransaction)
        return try MeshChainTransactionLookup(
            identity: identity,
            reference: reference,
            status: .pending,
            checkedAt: checkedAt,
            providerExtensions: [
                Self.providerName: [
                    "lookupMode": "configured-demo",
                    "network": identity.network
                ]
            ]
        )
    }

    public func lookupProof(
        reference: MeshChainProofReference,
        checkedAt: String
    ) async throws -> MeshChainProofLookup {
        try loadProviderConfiguration().require(.lookupProof)
        let transactionReference = try MeshChainProofReference(
            identity: identity,
            referenceType: .transaction,
            value: Self.deterministicTransactionHash(for: reference.value)
        )
        return try MeshChainProofLookup(
            identity: identity,
            reference: reference,
            status: .pending,
            proofType: .requestAnchor,
            transactionReference: transactionReference,
            checkedAt: checkedAt,
            providerExtensions: [
                Self.providerName: [
                    "lookupMode": "configured-demo",
                    "network": identity.network
                ]
            ]
        )
    }

    public static var defaultCapabilities: [MeshChainProviderCapability] {
        [
            .constructExplorerURL,
            .identifyNetwork,
            .loadProviderConfiguration,
            .checkHealth,
            .lookupTransaction,
            .lookupProof
        ]
    }

    private static func normalizedCapabilities(_ capabilities: [MeshChainProviderCapability]) -> [MeshChainProviderCapability] {
        Array(Set(capabilities)).sorted()
    }

    private static func deterministicTransactionHash(for proofReference: String) -> String {
        let digest = SHA256.hash(data: Data(proofReference.utf8))
        return "0x" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

public struct MeshMarooTestnetAdapterConfigSchema: Codable, Equatable, Sendable {
    public static let schemaName = "meshkit-maroo-testnet-adapter-config/v1"
    public static let providerName = MeshMarooTestnetChainProvider.providerName
    public static let networkIdentity = MeshMarooTestnetChainProvider.networkIdentity
    public static let chainId = MeshMarooTestnetChainProvider.chainId
    public static let endpointConfigurationKeys = [
        "rpcEndpoint",
        "explorerBaseURL",
        "faucetURL",
        "agentWalletKitBaseURL",
        "docsURL"
    ]
    public static let requiredEnvironmentKeys = [
        "MESHKIT_IOS_MAROO_LIVE_TX_HASH"
    ]
    public static let optionalEnvironmentKeys = [
        "MESHKIT_IOS_MAROO_ANCHOR_TX_HASH",
        "MESHKIT_MAROO_OKRW_CONTRACT_ADDRESS"
    ]
}

public struct MeshMarooTestnetExplorerAvailabilityCheck: Codable, Equatable, Sendable {
    public static let defaultOperation = "explorer HEAD"

    public let identity: MeshChainProviderIdentity
    public let explorerURL: URL
    public let operation: String

    public init(
        chainProvider: MeshMarooTestnetChainProvider = try! MeshMarooTestnetChainProvider(),
        explorerURL: URL? = nil,
        operation: String = Self.defaultOperation
    ) throws {
        self.identity = chainProvider.identity
        guard let resolvedExplorerURL = explorerURL ?? chainProvider.identity.explorerBaseURL else {
            throw MeshKitValidationError.chainProviderExplorerUnavailable
        }
        self.explorerURL = try MeshChainProviderIdentity.normalizedNetworkURL("explorerURL", resolvedExplorerURL)
        self.operation = try MeshExternalChainBlockerEvidence.normalizedEvidenceField("operation", operation)
        try endpointAvailabilityCheck().validate()
    }

    public func endpointAvailabilityCheck() throws -> MeshExternalChainEndpointAvailabilityCheck {
        try MeshExternalChainEndpointAvailabilityCheck(
            blockerType: .explorerUnavailable,
            identity: identity,
            endpoint: explorerURL,
            operation: operation
        )
    }

    public func blockerEvidence(
        observedAt: String,
        message: String,
        requestHash: MeshPayloadHash? = nil,
        requestNonce: String? = nil,
        anchoringReference: String? = nil,
        txHash: String? = nil
    ) throws -> MeshExternalChainBlockerEvidence {
        try endpointAvailabilityCheck().blockerEvidence(
            observedAt: observedAt,
            message: message,
            requestHash: requestHash,
            requestNonce: requestNonce,
            anchoringReference: anchoringReference,
            txHash: txHash
        )
    }

    public func evaluateHTTPStatus(
        _ httpStatus: Int?,
        observedAt: String,
        errorMessage: String? = nil
    ) throws -> MeshExternalChainBlockerEvidence? {
        try endpointAvailabilityCheck().evaluateHTTPStatus(
            httpStatus,
            observedAt: observedAt,
            errorMessage: errorMessage
        )
    }
}

public struct MeshMarooTestnetFaucetAvailabilityCheck: Codable, Equatable, Sendable {
    public static let defaultOperation = "faucet HEAD"

    public let identity: MeshChainProviderIdentity
    public let faucetURL: URL
    public let operation: String

    public init(
        chainProvider: MeshMarooTestnetChainProvider = try! MeshMarooTestnetChainProvider(),
        faucetURL: URL = MeshMarooTestnetChainProvider.defaultFaucetURL,
        operation: String = Self.defaultOperation
    ) throws {
        self.identity = chainProvider.identity
        self.faucetURL = try MeshChainProviderIdentity.normalizedNetworkURL("faucetURL", faucetURL)
        self.operation = try MeshExternalChainBlockerEvidence.normalizedEvidenceField("operation", operation)
        try endpointAvailabilityCheck().validate()
    }

    public func endpointAvailabilityCheck() throws -> MeshExternalChainEndpointAvailabilityCheck {
        try MeshExternalChainEndpointAvailabilityCheck(
            blockerType: .faucetUnavailable,
            identity: identity,
            endpoint: faucetURL,
            operation: operation
        )
    }

    public func blockerEvidence(
        observedAt: String,
        message: String,
        requestHash: MeshPayloadHash? = nil,
        requestNonce: String? = nil,
        anchoringReference: String? = nil,
        txHash: String? = nil
    ) throws -> MeshExternalChainBlockerEvidence {
        try endpointAvailabilityCheck().blockerEvidence(
            observedAt: observedAt,
            message: message,
            requestHash: requestHash,
            requestNonce: requestNonce,
            anchoringReference: anchoringReference,
            txHash: txHash
        )
    }

    public func evaluateHTTPStatus(
        _ httpStatus: Int?,
        observedAt: String,
        errorMessage: String? = nil
    ) throws -> MeshExternalChainBlockerEvidence? {
        try endpointAvailabilityCheck().evaluateHTTPStatus(
            httpStatus,
            observedAt: observedAt,
            errorMessage: errorMessage
        )
    }
}

public enum MeshMarooTestnetOKRWContractCodeExpectation: String, Codable, Equatable, Sendable {
    case deployedBytecode

    fileprivate func accepts(_ result: String?) -> Bool {
        guard let result else { return false }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("0x") && trimmed.count > 2
    }
}

public struct MeshMarooTestnetOKRWContractAvailabilityCheck: Codable, Equatable, Sendable {
    public static let defaultOperation = "eth_getCode OKRW"

    public let identity: MeshChainProviderIdentity
    public let rpcEndpoint: URL
    public let contractAddress: String
    public let operation: String
    public let codeExpectation: MeshMarooTestnetOKRWContractCodeExpectation

    public init(
        chainProvider: MeshMarooTestnetChainProvider = try! MeshMarooTestnetChainProvider(),
        rpcEndpoint: URL? = nil,
        contractAddress: String,
        operation: String = Self.defaultOperation,
        codeExpectation: MeshMarooTestnetOKRWContractCodeExpectation = .deployedBytecode
    ) throws {
        self.identity = chainProvider.identity
        self.rpcEndpoint = try MeshChainProviderIdentity.normalizedNetworkURL(
            "rpcEndpoint",
            rpcEndpoint ?? chainProvider.identity.rpcEndpoint
        )
        self.contractAddress = try Self.normalizedContractAddress(contractAddress)
        self.operation = try MeshExternalChainBlockerEvidence.normalizedEvidenceField("operation", operation)
        self.codeExpectation = codeExpectation
        try endpointAvailabilityCheck().validate()
    }

    public func endpointAvailabilityCheck() throws -> MeshExternalChainEndpointAvailabilityCheck {
        try MeshExternalChainEndpointAvailabilityCheck(
            blockerType: .okrwContractUnavailable,
            identity: identity,
            endpoint: rpcEndpoint,
            operation: operation
        )
    }

    public func blockerEvidence(
        observedAt: String,
        message: String,
        requestHash: MeshPayloadHash? = nil,
        requestNonce: String? = nil,
        anchoringReference: String? = nil,
        txHash: String? = nil
    ) throws -> MeshExternalChainBlockerEvidence {
        try endpointAvailabilityCheck().blockerEvidence(
            observedAt: observedAt,
            message: message,
            requestHash: requestHash,
            requestNonce: requestNonce,
            anchoringReference: anchoringReference,
            txHash: txHash
        )
    }

    public func evaluateHTTPStatus(
        _ httpStatus: Int?,
        observedAt: String,
        errorMessage: String? = nil
    ) throws -> MeshExternalChainBlockerEvidence? {
        try endpointAvailabilityCheck().evaluateHTTPStatus(
            httpStatus,
            observedAt: observedAt,
            errorMessage: errorMessage
        )
    }

    public func evaluateJSONRPCResponse(
        httpStatus: Int?,
        result: String?,
        observedAt: String,
        errorMessage: String? = nil
    ) throws -> MeshExternalChainBlockerEvidence? {
        if let httpEvidence = try evaluateHTTPStatus(
            httpStatus,
            observedAt: observedAt,
            errorMessage: errorMessage
        ) {
            return httpEvidence
        }

        guard codeExpectation.accepts(result) else {
            return try blockerEvidence(
                observedAt: observedAt,
                message: "\(operation) returned no deployed OKRW contract bytecode"
            )
        }

        return nil
    }

    private static func normalizedContractAddress(_ value: String) throws -> String {
        let normalized = try MeshExternalChainBlockerEvidence.normalizedEvidenceField(
            "contractAddress",
            value
        )
        guard normalized.hasPrefix("0x"),
              normalized.count == 42,
              normalized.dropFirst(2).allSatisfy({ $0.isHexDigit }) else {
            throw MeshKitValidationError.invalidChainProviderIdentity("contractAddress")
        }
        return normalized.lowercased()
    }
}

public enum MeshMarooTestnetRPCResultExpectation: String, Codable, Equatable, Sendable {
    case hexQuantity
    case nonEmptyString

    fileprivate func accepts(_ result: String?) -> Bool {
        guard let result else { return false }
        switch self {
        case .hexQuantity:
            return result.hasPrefix("0x") && result.count > 2
        case .nonEmptyString:
            return !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

public struct MeshMarooTestnetRPCAvailabilityCheck: Codable, Equatable, Sendable {
    public static let defaultOperation = "eth_blockNumber"

    public let identity: MeshChainProviderIdentity
    public let rpcEndpoint: URL
    public let operation: String
    public let resultExpectation: MeshMarooTestnetRPCResultExpectation

    public init(
        chainProvider: MeshMarooTestnetChainProvider = try! MeshMarooTestnetChainProvider(),
        rpcEndpoint: URL? = nil,
        operation: String = Self.defaultOperation,
        resultExpectation: MeshMarooTestnetRPCResultExpectation = .hexQuantity
    ) throws {
        self.identity = chainProvider.identity
        self.rpcEndpoint = try MeshChainProviderIdentity.normalizedNetworkURL(
            "rpcEndpoint",
            rpcEndpoint ?? chainProvider.identity.rpcEndpoint
        )
        self.operation = try MeshExternalChainBlockerEvidence.normalizedEvidenceField("operation", operation)
        self.resultExpectation = resultExpectation
        try endpointAvailabilityCheck().validate()
    }

    public func endpointAvailabilityCheck() throws -> MeshExternalChainEndpointAvailabilityCheck {
        try MeshExternalChainEndpointAvailabilityCheck(
            blockerType: .rpcUnavailable,
            identity: identity,
            endpoint: rpcEndpoint,
            operation: operation
        )
    }

    public func blockerEvidence(
        observedAt: String,
        message: String,
        requestHash: MeshPayloadHash? = nil,
        requestNonce: String? = nil,
        anchoringReference: String? = nil,
        txHash: String? = nil
    ) throws -> MeshExternalChainBlockerEvidence {
        try endpointAvailabilityCheck().blockerEvidence(
            observedAt: observedAt,
            message: message,
            requestHash: requestHash,
            requestNonce: requestNonce,
            anchoringReference: anchoringReference,
            txHash: txHash
        )
    }

    public func evaluateHTTPStatus(
        _ httpStatus: Int?,
        observedAt: String,
        errorMessage: String? = nil
    ) throws -> MeshExternalChainBlockerEvidence? {
        try endpointAvailabilityCheck().evaluateHTTPStatus(
            httpStatus,
            observedAt: observedAt,
            errorMessage: errorMessage
        )
    }

    public func evaluateJSONRPCResponse(
        httpStatus: Int?,
        result: String?,
        observedAt: String,
        errorMessage: String? = nil
    ) throws -> MeshExternalChainBlockerEvidence? {
        if let httpEvidence = try evaluateHTTPStatus(
            httpStatus,
            observedAt: observedAt,
            errorMessage: errorMessage
        ) {
            return httpEvidence
        }

        guard resultExpectation.accepts(result) else {
            return try blockerEvidence(
                observedAt: observedAt,
                message: "\(operation) returned unusable JSON-RPC result"
            )
        }

        return nil
    }
}

private extension KeyedDecodingContainer where K == MeshChainProviderIdentity.CodingKeys {
    func decodeString(preferred: K, fallback: K) throws -> String {
        if let value = try decodeIfPresent(String.self, forKey: preferred) {
            return value
        }
        return try decode(String.self, forKey: fallback)
    }
}
