import Foundation

public enum MeshChainProofCapability: String, Codable, CaseIterable, Comparable, Sendable {
    case constructRequestAnchorProof
    case constructPaymentExecutionProof
    case constructPolicyDenialProof
    case serializeReceiptResult

    public static func < (lhs: MeshChainProofCapability, rhs: MeshChainProofCapability) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum MeshChainProofType: String, Codable, CaseIterable, Comparable, Equatable, Sendable {
    case requestAnchor = "request_anchor"
    case paymentExecution = "payment_execution"
    case policyDenial = "policy_denial"

    public static func < (lhs: MeshChainProofType, rhs: MeshChainProofType) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum MeshChainProofStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case confirmed
    case pending
    case failed
}

public enum MeshChainProofPresentationState: String, Codable, CaseIterable, Equatable, Sendable {
    case paidComplete = "paid_complete"
    case submittedNotFinal = "submitted_not_final"
    case attemptedFailed = "attempted_failed"
    case policyDenied = "policy_denied"
}

public enum MeshChainProofFieldRequirement: String, Codable, Equatable, Sendable {
    case always
    case confirmedOnly = "confirmed_only"
    case optional
    case failureOnly = "failure_only"
}

public struct MeshChainProofFieldSchema: Codable, Equatable, Sendable {
    public let name: String
    public let valueType: String
    public let requirement: MeshChainProofFieldRequirement
    public let receiptResultKey: String?
    public let description: String

    public init(
        name: String,
        valueType: String,
        requirement: MeshChainProofFieldRequirement,
        receiptResultKey: String? = nil,
        description: String
    ) {
        self.name = name
        self.valueType = valueType
        self.requirement = requirement
        self.receiptResultKey = receiptResultKey
        self.description = description
    }
}

public struct MeshChainProofSchema: Codable, Equatable, Sendable {
    public static let version = "meshkit-chain-proof-schema/v1"

    public let version: String
    public let fields: [MeshChainProofFieldSchema]
    public let confirmedRequiredFields: [String]
    public let pendingRequiredFields: [String]
    public let failedRequiredFields: [String]
    public let policyDeniedRequiredFields: [String]

    public init(
        version: String = Self.version,
        fields: [MeshChainProofFieldSchema],
        confirmedRequiredFields: [String],
        pendingRequiredFields: [String],
        failedRequiredFields: [String],
        policyDeniedRequiredFields: [String]? = nil
    ) throws {
        self.version = version
        self.fields = fields
        self.confirmedRequiredFields = confirmedRequiredFields
        self.pendingRequiredFields = pendingRequiredFields
        self.failedRequiredFields = failedRequiredFields
        self.policyDeniedRequiredFields = policyDeniedRequiredFields ?? failedRequiredFields
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case fields
        case confirmedRequiredFields
        case pendingRequiredFields
        case failedRequiredFields
        case policyDeniedRequiredFields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(String.self, forKey: .version)
        let fields = try container.decode([MeshChainProofFieldSchema].self, forKey: .fields)
        let confirmedRequiredFields = try container.decode([String].self, forKey: .confirmedRequiredFields)
        let pendingRequiredFields = try container.decode([String].self, forKey: .pendingRequiredFields)
        let failedRequiredFields = try container.decode([String].self, forKey: .failedRequiredFields)
        let policyDeniedRequiredFields = try container.decodeIfPresent(
            [String].self,
            forKey: .policyDeniedRequiredFields
        )
        try self.init(
            version: version,
            fields: fields,
            confirmedRequiredFields: confirmedRequiredFields,
            pendingRequiredFields: pendingRequiredFields,
            failedRequiredFields: failedRequiredFields,
            policyDeniedRequiredFields: policyDeniedRequiredFields
        )
    }

    public static let providerNeutral = try! MeshChainProofSchema(
        fields: [
            MeshChainProofFieldSchema(name: "provider", valueType: "string", requirement: .always, receiptResultKey: "chainProvider", description: "Provider identifier without provider-specific semantics."),
            MeshChainProofFieldSchema(name: "chainId", valueType: "string", requirement: .always, receiptResultKey: "chainId", description: "Provider-neutral chain identifier."),
            MeshChainProofFieldSchema(name: "network", valueType: "string", requirement: .always, receiptResultKey: "chainNetwork", description: "Network identifier."),
            MeshChainProofFieldSchema(name: "proofType", valueType: "MeshChainProofType", requirement: .always, receiptResultKey: "chainProofType", description: "Request anchor, payment execution, or policy denial proof category."),
            MeshChainProofFieldSchema(name: "status", valueType: "MeshChainProofStatus", requirement: .always, receiptResultKey: "chainStatus", description: "Confirmed, pending, or failed chain proof status."),
            MeshChainProofFieldSchema(name: "presentationState", valueType: "MeshChainProofPresentationState", requirement: .always, receiptResultKey: "presentationState", description: "Receipt presentation state derived from proof type and status."),
            MeshChainProofFieldSchema(name: "requestHash", valueType: "MeshPayloadHash", requirement: .always, receiptResultKey: "requestHash", description: "Canonical signed MCP request hash."),
            MeshChainProofFieldSchema(name: "requestNonce", valueType: "string", requirement: .always, receiptResultKey: "requestNonce", description: "Nonce from the signed MCP request."),
            MeshChainProofFieldSchema(name: "policyId", valueType: "string", requirement: .always, receiptResultKey: "policyId", description: "Delegated spending policy identifier."),
            MeshChainProofFieldSchema(name: "policyHash", valueType: "MeshPayloadHash", requirement: .always, receiptResultKey: "policyHash", description: "Delegated spending policy hash."),
            MeshChainProofFieldSchema(name: "walletAddress", valueType: "string", requirement: .always, receiptResultKey: "walletAddress", description: "Agent wallet address."),
            MeshChainProofFieldSchema(name: "amount", valueType: "decimal", requirement: .always, receiptResultKey: "amount", description: "Payment or transfer amount."),
            MeshChainProofFieldSchema(name: "asset", valueType: "string", requirement: .always, receiptResultKey: "asset", description: "Asset symbol or currency code."),
            MeshChainProofFieldSchema(name: "recipient", valueType: "string", requirement: .always, receiptResultKey: "recipient", description: "Payment or transfer recipient."),
            MeshChainProofFieldSchema(name: "anchoringReference", valueType: "string", requirement: .always, receiptResultKey: "anchoringReference", description: "Request anchoring reference."),
            MeshChainProofFieldSchema(name: "executionAttemptId", valueType: "string", requirement: .optional, receiptResultKey: "executionAttemptId", description: "Stable payment execution attempt identity."),
            MeshChainProofFieldSchema(name: "paymentId", valueType: "string", requirement: .optional, receiptResultKey: "paymentId", description: "Provider-neutral payment identifier."),
            MeshChainProofFieldSchema(name: "authorizationId", valueType: "string", requirement: .optional, receiptResultKey: "authorizationId", description: "Provider-neutral authorization identifier."),
            MeshChainProofFieldSchema(name: "executionId", valueType: "string", requirement: .optional, receiptResultKey: "executionId", description: "Agent wallet execution identifier."),
            MeshChainProofFieldSchema(name: "executionKind", valueType: "MeshAgentWalletExecutionKind", requirement: .optional, receiptResultKey: "executionKind", description: "Payment or transfer execution kind."),
            MeshChainProofFieldSchema(name: "anchorTxHash", valueType: "string", requirement: .optional, receiptResultKey: "anchorTxHash", description: "Optional transaction hash for the request anchor."),
            MeshChainProofFieldSchema(name: "txHash", valueType: "string", requirement: .confirmedOnly, receiptResultKey: "txHash", description: "Confirmed payment or transfer transaction hash."),
            MeshChainProofFieldSchema(name: "explorerUrl", valueType: "url", requirement: .confirmedOnly, receiptResultKey: "explorerUrl", description: "Explorer URL for confirmed transaction proof."),
            MeshChainProofFieldSchema(name: "errorCode", valueType: "string", requirement: .failureOnly, receiptResultKey: "errorCode", description: "Failure or policy denial code."),
            MeshChainProofFieldSchema(name: "errorMessage", valueType: "string", requirement: .failureOnly, receiptResultKey: "errorMessage", description: "Failure or policy denial message."),
            MeshChainProofFieldSchema(name: "submittedAt", valueType: "iso8601-string", requirement: .optional, receiptResultKey: "submittedAt", description: "Provider observation or submission timestamp."),
            MeshChainProofFieldSchema(name: "confirmedAt", valueType: "iso8601-string", requirement: .confirmedOnly, receiptResultKey: "confirmedAt", description: "Confirmed transaction observation timestamp."),
            MeshChainProofFieldSchema(name: "providerExtensions", valueType: "map<string,map<string,string>>", requirement: .optional, description: "Provider-scoped extension bag kept out of core semantics.")
        ],
        confirmedRequiredFields: [
            "provider", "chainId", "network", "proofType", "status", "presentationState",
            "requestHash", "requestNonce", "policyId", "policyHash", "walletAddress",
            "amount", "asset", "recipient", "anchoringReference", "txHash",
            "explorerUrl", "confirmedAt"
        ],
        pendingRequiredFields: [
            "provider", "chainId", "network", "proofType", "status", "presentationState",
            "requestHash", "requestNonce", "policyId", "policyHash", "walletAddress",
            "amount", "asset", "recipient", "anchoringReference", "submittedAt"
        ],
        failedRequiredFields: [
            "provider", "chainId", "network", "proofType", "status", "presentationState",
            "requestHash", "requestNonce", "policyId", "policyHash", "walletAddress",
            "amount", "asset", "recipient", "anchoringReference", "errorCode", "errorMessage"
        ],
        policyDeniedRequiredFields: [
            "provider", "chainId", "network", "proofType", "status", "presentationState",
            "requestHash", "requestNonce", "policyId", "policyHash", "walletAddress",
            "amount", "asset", "recipient", "anchoringReference", "executionAttemptId",
            "executionId", "errorCode", "errorMessage"
        ]
    )

    public func validate() throws {
        guard version == Self.version else { throw MeshKitValidationError.invalidChainProof("schema.version") }
        let names = fields.map(\.name)
        guard Set(names).count == names.count else { throw MeshKitValidationError.invalidChainProof("schema.fields") }
        let fieldSet = Set(names)
        for requiredField in confirmedRequiredFields + pendingRequiredFields + failedRequiredFields + policyDeniedRequiredFields {
            guard fieldSet.contains(requiredField) else {
                throw MeshKitValidationError.invalidChainProof("schema.requiredFields")
            }
        }
        for field in fields where field.requirement == .always {
            guard confirmedRequiredFields.contains(field.name) else {
                throw MeshKitValidationError.invalidChainProof("schema.confirmedRequiredFields")
            }
            guard pendingRequiredFields.contains(field.name) else {
                throw MeshKitValidationError.invalidChainProof("schema.pendingRequiredFields")
            }
            guard failedRequiredFields.contains(field.name) else {
                throw MeshKitValidationError.invalidChainProof("schema.failedRequiredFields")
            }
        }
        for field in fields where field.requirement == .failureOnly {
            guard failedRequiredFields.contains(field.name) else {
                throw MeshKitValidationError.invalidChainProof("schema.failedRequiredFields")
            }
            guard policyDeniedRequiredFields.contains(field.name) else {
                throw MeshKitValidationError.invalidChainProof("schema.policyDeniedRequiredFields")
            }
        }
        for requiredField in policyDeniedRequiredFields {
            guard failedRequiredFields.contains(requiredField)
                || requiredField == "executionAttemptId"
                || requiredField == "executionId" else {
                throw MeshKitValidationError.invalidChainProof("schema.policyDeniedRequiredFields")
            }
        }
    }

    public func requiredFields(
        status: MeshChainProofStatus,
        proofType: MeshChainProofType,
        presentationState: MeshChainProofPresentationState
    ) throws -> [String] {
        switch (status, proofType, presentationState) {
        case (.confirmed, .paymentExecution, .paidComplete):
            return confirmedRequiredFields
        case (.pending, .requestAnchor, .submittedNotFinal),
             (.pending, .paymentExecution, .submittedNotFinal):
            return pendingRequiredFields
        case (.failed, .paymentExecution, .attemptedFailed):
            return failedRequiredFields
        case (.failed, .policyDenial, .policyDenied):
            return policyDeniedRequiredFields
        default:
            throw MeshKitValidationError.invalidChainProof("presentationState")
        }
    }

    public func validateReceiptResultFields(_ result: [String: String]) throws {
        try validate()
        let status = try MeshChainProofStatus(rawReceiptResult: result, key: "chainStatus")
        let proofType = try MeshChainProofType(rawReceiptResult: result, key: "chainProofType")
        let presentationState = try MeshChainProofPresentationState(rawReceiptResult: result, key: "presentationState")
        let requiredFieldNames = try requiredFields(
            status: status,
            proofType: proofType,
            presentationState: presentationState
        )
        let fieldsByName = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0) })

        for fieldName in requiredFieldNames {
            guard let field = fieldsByName[fieldName] else {
                throw MeshKitValidationError.invalidChainProof("schema.requiredFields")
            }
            let resultKey = field.receiptResultKey ?? field.name
            guard let value = result[resultKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  value == result[resultKey] else {
                throw MeshKitValidationError.invalidChainProof("receipt.result.\(resultKey)")
            }
        }

        switch (status, proofType, presentationState) {
        case (.confirmed, .paymentExecution, .paidComplete):
            guard result["errorCode"] == nil, result["errorMessage"] == nil else {
                throw MeshKitValidationError.invalidChainProof("receipt.result.errorCode")
            }
        case (.pending, .requestAnchor, .submittedNotFinal),
             (.pending, .paymentExecution, .submittedNotFinal),
             (.failed, .paymentExecution, .attemptedFailed),
             (.failed, .policyDenial, .policyDenied):
            guard result["txHash"] == nil else {
                throw MeshKitValidationError.invalidChainProof("receipt.result.txHash")
            }
            guard result["explorerUrl"] == nil else {
                throw MeshKitValidationError.invalidChainProof("receipt.result.explorerUrl")
            }
            guard result["confirmedAt"] == nil else {
                throw MeshKitValidationError.invalidChainProof("receipt.result.confirmedAt")
            }
        default:
            throw MeshKitValidationError.invalidChainProof("presentationState")
        }
    }
}

private extension MeshChainProofStatus {
    init(rawReceiptResult result: [String: String], key: String) throws {
        guard let rawValue = result[key], let value = Self(rawValue: rawValue) else {
            throw MeshKitValidationError.invalidChainProof("receipt.result.\(key)")
        }
        self = value
    }
}

private extension MeshChainProofType {
    init(rawReceiptResult result: [String: String], key: String) throws {
        guard let rawValue = result[key], let value = Self(rawValue: rawValue) else {
            throw MeshKitValidationError.invalidChainProof("receipt.result.\(key)")
        }
        self = value
    }
}

private extension MeshChainProofPresentationState {
    init(rawReceiptResult result: [String: String], key: String) throws {
        guard let rawValue = result[key], let value = Self(rawValue: rawValue) else {
            throw MeshKitValidationError.invalidChainProof("receipt.result.\(key)")
        }
        self = value
    }
}

public struct MeshChainProofVerificationStatus: Codable, Equatable, Sendable {
    public let proofType: MeshChainProofType
    public let status: MeshChainProofStatus
    public let presentationState: MeshChainProofPresentationState
    public let requiresTransactionProof: Bool
    public let isTerminal: Bool

    public init(
        proofType: MeshChainProofType,
        status: MeshChainProofStatus,
        presentationState: MeshChainProofPresentationState,
        requiresTransactionProof: Bool,
        isTerminal: Bool
    ) {
        self.proofType = proofType
        self.status = status
        self.presentationState = presentationState
        self.requiresTransactionProof = requiresTransactionProof
        self.isTerminal = isTerminal
    }
}

public struct MeshChainProofConfiguration: Codable, Equatable, Sendable {
    public let capabilities: [MeshChainProofCapability]
    public let supportedProofTypes: [MeshChainProofType]

    public init(
        capabilities: [MeshChainProofCapability],
        supportedProofTypes explicitSupportedProofTypes: [MeshChainProofType]? = nil
    ) throws {
        self.capabilities = Array(Set(capabilities)).sorted()
        self.supportedProofTypes = try Self.normalizedSupportedProofTypes(
            explicitSupportedProofTypes ?? Self.minimumSupportedProofTypes(for: self.capabilities),
            capabilities: self.capabilities
        )
        try validate()
    }

    public func supports(_ capability: MeshChainProofCapability) -> Bool {
        capabilities.contains(capability)
    }

    public func supports(proofType: MeshChainProofType) -> Bool {
        supportedProofTypes.contains(proofType)
    }

    public func require(_ capability: MeshChainProofCapability) throws {
        guard supports(capability) else { throw MeshKitValidationError.unsupportedCapability }
    }

    public func require(proofType: MeshChainProofType) throws {
        guard supports(proofType: proofType) else { throw MeshKitValidationError.unsupportedCapability }
    }

    public func validate() throws {
        guard !capabilities.isEmpty else { throw MeshKitValidationError.unsupportedCapability }
        guard !supportedProofTypes.isEmpty else { throw MeshKitValidationError.unsupportedCapability }
        for proofType in supportedProofTypes {
            guard Self.minimumSupportedProofTypes(for: capabilities).contains(proofType) else {
                throw MeshKitValidationError.unsupportedCapability
            }
        }
    }

    public static func featureDetection(
        capabilities: [MeshChainProofCapability],
        advertisedProofTypes: [MeshChainProofType]? = nil
    ) throws -> MeshChainProofFeatureDetection {
        let configuration = try MeshChainProofConfiguration(
            capabilities: capabilities,
            supportedProofTypes: advertisedProofTypes
        )
        return MeshChainProofFeatureDetection(configuration: configuration)
    }

    public static func minimumSupportedProofTypes(
        for capabilities: [MeshChainProofCapability]
    ) -> [MeshChainProofType] {
        let capabilitySet = Set(capabilities)
        var proofTypes = Set<MeshChainProofType>()
        if capabilitySet.contains(.constructRequestAnchorProof) {
            proofTypes.insert(.requestAnchor)
        }
        if capabilitySet.contains(.constructPaymentExecutionProof) {
            proofTypes.insert(.paymentExecution)
        }
        if capabilitySet.contains(.constructPolicyDenialProof) {
            proofTypes.insert(.policyDenial)
        }
        return proofTypes.sorted()
    }

    private static func normalizedSupportedProofTypes(
        _ proofTypes: [MeshChainProofType],
        capabilities: [MeshChainProofCapability]
    ) throws -> [MeshChainProofType] {
        let normalized = Array(Set(proofTypes)).sorted()
        guard !normalized.isEmpty else { throw MeshKitValidationError.unsupportedCapability }
        let minimum = minimumSupportedProofTypes(for: capabilities)
        for proofType in normalized {
            guard minimum.contains(proofType) else {
                throw MeshKitValidationError.unsupportedCapability
            }
        }
        return normalized
    }
}

public struct MeshChainProofFeatureDetection: Codable, Equatable, Sendable {
    public let capabilities: [MeshChainProofCapability]
    public let minimumSupportedProofTypes: [MeshChainProofType]
    public let supportedProofTypes: [MeshChainProofType]

    public init(configuration: MeshChainProofConfiguration) {
        self.capabilities = configuration.capabilities
        self.minimumSupportedProofTypes = MeshChainProofConfiguration.minimumSupportedProofTypes(
            for: configuration.capabilities
        )
        self.supportedProofTypes = configuration.supportedProofTypes
    }

    public func supports(_ proofType: MeshChainProofType) -> Bool {
        supportedProofTypes.contains(proofType)
    }
}

public struct MeshPaymentExecutionReceiptLinkage: Codable, Equatable, Sendable {
    public let proof: MeshChainProof
    public let receiptResultFields: [String: String]
    public let requestHash: MeshPayloadHash
    public let anchoringReference: String
    public let executionAttemptId: String?
    public let txHash: String?

    public init(
        proof: MeshChainProof,
        receiptResultFields: [String: String]
    ) throws {
        try proof.validate()
        try MeshReceipt.validateResultFields(receiptResultFields)
        guard receiptResultFields["requestHash"] == proof.requestHash.value.lowercased() else {
            throw MeshKitValidationError.invalidChainProof("requestHash")
        }
        guard receiptResultFields["anchoringReference"] == proof.anchoringReference else {
            throw MeshKitValidationError.invalidChainProof("anchoringReference")
        }
        guard receiptResultFields["policyId"] == proof.policyId else {
            throw MeshKitValidationError.invalidChainProof("policyId")
        }
        guard receiptResultFields["policyHash"] == proof.policyHash.value.lowercased() else {
            throw MeshKitValidationError.invalidChainProof("policyHash")
        }
        guard receiptResultFields["txHash"] == proof.txHash else {
            throw MeshKitValidationError.invalidChainProof("txHash")
        }
        guard receiptResultFields["executionAttemptId"] == proof.executionAttemptId else {
            throw MeshKitValidationError.invalidChainProof("executionAttemptId")
        }
        if let executionKind = proof.executionKind {
            guard receiptResultFields["executionKind"] == executionKind.rawValue else {
                throw MeshKitValidationError.invalidChainProof("executionKind")
            }
        }

        self.proof = proof
        self.receiptResultFields = receiptResultFields
        self.requestHash = proof.requestHash
        self.anchoringReference = proof.anchoringReference
        self.executionAttemptId = proof.executionAttemptId
        self.txHash = proof.txHash
    }
}

public enum MeshPaymentExecutionReceiptLinkageMapper {
    public static func map(
        paymentResult: MeshPaymentExecutionResult,
        executionRequest: MeshAgentWalletExecutionRequest,
        walletAddress: String
    ) throws -> MeshPaymentExecutionReceiptLinkage {
        try paymentResult.validate()
        try executionRequest.validate()
        guard paymentResult.signedRequestHash == executionRequest.requestAnchorMetadata.signedRequestHash else {
            throw MeshKitValidationError.invalidChainProof("requestHash")
        }

        let proof = try MeshChainProof(
            paymentResult: paymentResult,
            executionRequest: executionRequest,
            walletAddress: walletAddress
        )
        return try MeshPaymentExecutionReceiptLinkage(
            proof: proof,
            receiptResultFields: proof.receiptResultFields()
        )
    }
}

public enum MeshChainProofReferenceType: String, Codable, CaseIterable, Equatable, Sendable {
    case transaction
    case proof
}

public struct MeshChainProofReference: Codable, Equatable, Sendable {
    public let provider: String
    public let chainId: String
    public let network: String
    public let referenceType: MeshChainProofReferenceType
    public let value: String
    public let canonicalReference: String
    public let explorerUrl: URL?

    public init(
        provider: String,
        chainId: String,
        network: String,
        referenceType: MeshChainProofReferenceType,
        value: String,
        explorerUrl: URL? = nil
    ) throws {
        let normalizedProvider = try MeshChainProof.normalizedReferenceComponent("provider", provider)
        let normalizedChainId = try MeshChainProof.normalizedReferenceComponent("chainId", chainId)
        let normalizedNetwork = try MeshChainProof.normalizedReferenceComponent("network", network)
        let normalizedValue = try MeshChainProof.normalizedReferenceValue("value", value)

        self.provider = normalizedProvider
        self.chainId = normalizedChainId
        self.network = normalizedNetwork
        self.referenceType = referenceType
        self.value = normalizedValue
        self.canonicalReference = try Self.makeCanonicalReference(
            provider: normalizedProvider,
            network: normalizedNetwork,
            chainId: normalizedChainId,
            referenceType: referenceType,
            value: normalizedValue
        )
        self.explorerUrl = explorerUrl
        try validate()
    }

    public init(
        identity: MeshChainProviderIdentity,
        referenceType: MeshChainProofReferenceType,
        value: String,
        explorerUrl: URL? = nil
    ) throws {
        let normalizedValue = try MeshChainProof.normalizedReferenceValue("value", value)
        let resolvedExplorerUrl: URL?
        if let explorerUrl {
            resolvedExplorerUrl = explorerUrl
        } else if referenceType == .transaction {
            resolvedExplorerUrl = try? identity.explorerURL(transactionHash: normalizedValue)
        } else {
            resolvedExplorerUrl = nil
        }

        try self.init(
            provider: identity.provider,
            chainId: identity.chainId,
            network: identity.network,
            referenceType: referenceType,
            value: normalizedValue,
            explorerUrl: resolvedExplorerUrl
        )
    }

    public static func transaction(
        identity: MeshChainProviderIdentity,
        providerFields: [String: String],
        explorerUrl: URL? = nil
    ) throws -> MeshChainProofReference {
        try MeshChainProofReference(
            identity: identity,
            referenceType: .transaction,
            value: providerReferenceValue(
                "transactionHash",
                fields: providerFields,
                aliases: ["transactionHash", "transaction_hash", "txHash", "tx_hash", "hash"]
            ),
            explorerUrl: explorerUrl
        )
    }

    public static func proof(
        identity: MeshChainProviderIdentity,
        providerFields: [String: String],
        explorerUrl: URL? = nil
    ) throws -> MeshChainProofReference {
        try MeshChainProofReference(
            identity: identity,
            referenceType: .proof,
            value: providerReferenceValue(
                "proofReference",
                fields: providerFields,
                aliases: ["proofReference", "proof_reference", "proofId", "proof_id", "anchorId", "anchor_id", "requestAnchorId", "request_anchor_id", "reference"]
            ),
            explorerUrl: explorerUrl
        )
    }

    public func validate() throws {
        try MeshChainProof.requireReferenceField("provider", provider)
        try MeshChainProof.requireReferenceField("chainId", chainId)
        try MeshChainProof.requireReferenceField("network", network)
        try MeshChainProof.requireReferenceField("value", value)
        try MeshChainProof.requireField("canonicalReference", canonicalReference)
        if let explorerUrl {
            try MeshChainProviderIdentity.validateNetworkURL("explorerUrl", explorerUrl)
        }
    }

    private static func providerReferenceValue(
        _ field: String,
        fields: [String: String],
        aliases: [String]
    ) throws -> String {
        var normalizedFields: [String: String] = [:]
        for (key, value) in fields {
            normalizedFields[key.filter { $0 != "_" }.lowercased()] = value
        }
        for alias in aliases {
            if let value = normalizedFields[alias.filter({ $0 != "_" }).lowercased()] {
                return try MeshChainProof.normalizedReferenceValue(field, value)
            }
        }
        throw MeshKitValidationError.invalidChainProof(field)
    }

    private static func makeCanonicalReference(
        provider: String,
        network: String,
        chainId: String,
        referenceType: MeshChainProofReferenceType,
        value: String
    ) throws -> String {
        let encodedComponents = try [provider, network, chainId, referenceType.rawValue, value].map {
            try canonicalPathComponent($0)
        }
        return "chainproof://\(encodedComponents[0])/\(encodedComponents[1])/\(encodedComponents[2])/\(encodedComponents[3])/\(encodedComponents[4])"
    }

    private static func canonicalPathComponent(_ value: String) throws -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed),
              !encoded.isEmpty else {
            throw MeshKitValidationError.invalidChainProof("canonicalReference")
        }
        return encoded
    }
}

public struct MeshChainProof: Codable, Equatable, Sendable {
    public let provider: String
    public let chainId: String
    public let network: String
    public let proofType: MeshChainProofType
    public let status: MeshChainProofStatus
    public let presentationState: MeshChainProofPresentationState
    public let requestHash: MeshPayloadHash
    public let requestNonce: String
    public let policyId: String
    public let policyHash: MeshPayloadHash
    public let walletAddress: String
    public let amount: Decimal
    public let asset: String
    public let recipient: String
    public let anchoringReference: String
    public let executionAttemptId: String?
    public let paymentId: String?
    public let authorizationId: String?
    public let executionId: String?
    public let executionKind: MeshAgentWalletExecutionKind?
    public let anchorTxHash: String?
    public let txHash: String?
    public let explorerUrl: URL?
    public let errorCode: String?
    public let errorMessage: String?
    public let submittedAt: String?
    public let confirmedAt: String?
    public let providerExtensions: [String: [String: String]]

    private enum CodingKeys: String, CodingKey {
        case provider
        case chainId
        case network
        case proofType
        case status
        case presentationState
        case requestHash
        case requestNonce
        case policyId
        case policyHash
        case walletAddress
        case amount
        case asset
        case recipient
        case anchoringReference
        case executionAttemptId
        case paymentId
        case authorizationId
        case executionId
        case executionKind
        case anchorTxHash
        case txHash
        case explorerUrl
        case errorCode
        case errorMessage
        case submittedAt
        case confirmedAt
        case providerExtensions
    }

    public init(
        provider: String,
        chainId: String,
        network: String,
        proofType: MeshChainProofType,
        status: MeshChainProofStatus,
        presentationState: MeshChainProofPresentationState,
        requestHash: MeshPayloadHash,
        requestNonce: String,
        policyId: String,
        policyHash: MeshPayloadHash,
        walletAddress: String,
        amount: Decimal,
        asset: String,
        recipient: String,
        anchoringReference: String,
        executionAttemptId: String? = nil,
        paymentId: String? = nil,
        authorizationId: String? = nil,
        executionId: String? = nil,
        executionKind: MeshAgentWalletExecutionKind? = nil,
        anchorTxHash: String? = nil,
        txHash: String? = nil,
        explorerUrl: URL? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        submittedAt: String? = nil,
        confirmedAt: String? = nil,
        providerExtensions: [String: [String: String]] = [:]
    ) throws {
        self.provider = try Self.normalizedLowercaseField("provider", provider)
        self.chainId = try Self.normalizedLowercaseField("chainId", chainId)
        self.network = try Self.normalizedLowercaseField("network", network)
        self.proofType = proofType
        self.status = status
        self.presentationState = presentationState
        self.requestHash = requestHash
        self.requestNonce = try Self.stableField("requestNonce", requestNonce)
        self.policyId = try Self.stableField("policyId", policyId)
        self.policyHash = policyHash
        self.walletAddress = try Self.stableField("walletAddress", walletAddress)
        self.amount = amount
        self.asset = try Self.normalizedAsset("asset", asset)
        self.recipient = try Self.stableField("recipient", recipient)
        self.anchoringReference = try Self.stableField("anchoringReference", anchoringReference)
        self.executionAttemptId = try executionAttemptId.map { try Self.stableField("executionAttemptId", $0) }
        self.paymentId = try paymentId.map { try Self.stableField("paymentId", $0) }
        self.authorizationId = try authorizationId.map { try Self.stableField("authorizationId", $0) }
        self.executionId = try executionId.map { try Self.stableField("executionId", $0) }
        self.executionKind = executionKind
        self.anchorTxHash = try anchorTxHash.map { try Self.stableField("anchorTxHash", $0) }
        self.txHash = try txHash.map { try Self.stableField("txHash", $0) }
        self.explorerUrl = explorerUrl
        self.errorCode = try errorCode.map { try Self.stableField("errorCode", $0) }
        self.errorMessage = try errorMessage.map { try Self.stableField("errorMessage", $0) }
        self.submittedAt = try submittedAt.map { try Self.stableField("submittedAt", $0) }
        self.confirmedAt = try confirmedAt.map { try Self.stableField("confirmedAt", $0) }
        self.providerExtensions = try Self.normalizedProviderExtensions(providerExtensions)
        try validate()
    }

    public init(
        paymentResult: MeshPaymentExecutionResult,
        executionRequest: MeshAgentWalletExecutionRequest,
        walletAddress: String,
        policyDeniedErrorCode: String = "policy_denied",
        failedErrorCode: String = "payment_execution_failed"
    ) throws {
        let normalizedStatus = Self.normalizedVerificationStatus(for: paymentResult.status)
        let errorCode: String?
        let errorMessage: String?
        let confirmedAt: String?

        switch paymentResult.status {
        case .confirmed:
            errorCode = nil
            errorMessage = nil
            confirmedAt = paymentResult.observedAt
        case .pending:
            errorCode = nil
            errorMessage = nil
            confirmedAt = nil
        case .failed:
            errorCode = paymentResult.errorPayload?.code ?? failedErrorCode
            errorMessage = paymentResult.errorPayload?.message ?? paymentResult.message ?? "payment execution failed"
            confirmedAt = nil
        case .policyDenied:
            errorCode = paymentResult.errorPayload?.code ?? policyDeniedErrorCode
            errorMessage = paymentResult.errorPayload?.message ?? paymentResult.message ?? "policy denied"
            confirmedAt = nil
        }

        let transactionHash = paymentResult.status == .confirmed ? paymentResult.transactionHash : nil
        let explorerUrl = paymentResult.status == .confirmed ? paymentResult.explorerURL : nil

        try self.init(
            provider: paymentResult.identity.provider,
            chainId: paymentResult.identity.chainId,
            network: paymentResult.identity.network,
            proofType: normalizedStatus.proofType,
            status: normalizedStatus.status,
            presentationState: normalizedStatus.presentationState,
            requestHash: paymentResult.signedRequestHash,
            requestNonce: executionRequest.requestAnchorMetadata.nonce,
            policyId: executionRequest.policyId,
            policyHash: executionRequest.policyHash,
            walletAddress: walletAddress,
            amount: paymentResult.amount,
            asset: paymentResult.tokenSymbol ?? paymentResult.currencyCode ?? "",
            recipient: paymentResult.recipientAddress,
            anchoringReference: paymentResult.requestAnchorIdentifier.anchorId,
            executionAttemptId: Self.executionAttemptIdentity(
                paymentId: paymentResult.paymentId,
                authorizationId: paymentResult.authorizationId,
                executionId: executionRequest.executionId
            ),
            paymentId: paymentResult.paymentId,
            authorizationId: paymentResult.authorizationId,
            executionId: executionRequest.executionId,
            executionKind: paymentResult.kind,
            anchorTxHash: paymentResult.requestAnchorIdentifier.transactionHash,
            txHash: transactionHash,
            explorerUrl: explorerUrl,
            errorCode: errorCode,
            errorMessage: errorMessage,
            submittedAt: paymentResult.observedAt,
            confirmedAt: confirmedAt,
            providerExtensions: paymentResult.providerExtensions
        )
    }

    public init(
        requestAnchor: MeshRequestAnchor,
        policyId explicitPolicyId: String? = nil,
        policyHash explicitPolicyHash: MeshPayloadHash? = nil,
        walletAddress: String,
        amount: Decimal,
        asset: String,
        recipient: String
    ) throws {
        try requestAnchor.validate()
        guard requestAnchor.status == .submitted ||
              requestAnchor.status == .pending ||
              requestAnchor.status == .confirmed else {
            throw MeshKitValidationError.invalidChainProof("requestAnchor.status")
        }

        let policyId = try explicitPolicyId ?? requestAnchor.payload?.policyId ?? Self.missingChainProofField("policyId")
        let policyHash = try explicitPolicyHash ?? requestAnchor.payload?.policyHash ?? Self.missingChainProofField("policyHash")

        try self.init(
            provider: requestAnchor.identifier.identity.provider,
            chainId: requestAnchor.identifier.identity.chainId,
            network: requestAnchor.identifier.identity.network,
            proofType: .requestAnchor,
            status: .pending,
            presentationState: .submittedNotFinal,
            requestHash: requestAnchor.metadata.signedRequestHash,
            requestNonce: requestAnchor.metadata.nonce,
            policyId: policyId,
            policyHash: policyHash,
            walletAddress: walletAddress,
            amount: amount,
            asset: asset,
            recipient: recipient,
            anchoringReference: requestAnchor.identifier.anchorId,
            anchorTxHash: requestAnchor.identifier.transactionHash,
            submittedAt: requestAnchor.submittedAt
        )
        try validateSignedRequestAnchorProof(
            requestAnchor,
            policyId: explicitPolicyId,
            policyHash: explicitPolicyHash
        )
    }

    private static func missingChainProofField<T>(_ field: String) throws -> T {
        throw MeshKitValidationError.invalidChainProof(field)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            provider: try container.decode(String.self, forKey: .provider),
            chainId: try container.decode(String.self, forKey: .chainId),
            network: try container.decode(String.self, forKey: .network),
            proofType: try container.decode(MeshChainProofType.self, forKey: .proofType),
            status: try container.decode(MeshChainProofStatus.self, forKey: .status),
            presentationState: try container.decode(MeshChainProofPresentationState.self, forKey: .presentationState),
            requestHash: try container.decode(MeshPayloadHash.self, forKey: .requestHash),
            requestNonce: try container.decode(String.self, forKey: .requestNonce),
            policyId: try container.decode(String.self, forKey: .policyId),
            policyHash: try container.decode(MeshPayloadHash.self, forKey: .policyHash),
            walletAddress: try container.decode(String.self, forKey: .walletAddress),
            amount: try container.decode(Decimal.self, forKey: .amount),
            asset: try container.decode(String.self, forKey: .asset),
            recipient: try container.decode(String.self, forKey: .recipient),
            anchoringReference: try container.decode(String.self, forKey: .anchoringReference),
            executionAttemptId: try container.decodeIfPresent(String.self, forKey: .executionAttemptId),
            paymentId: try container.decodeIfPresent(String.self, forKey: .paymentId),
            authorizationId: try container.decodeIfPresent(String.self, forKey: .authorizationId),
            executionId: try container.decodeIfPresent(String.self, forKey: .executionId),
            executionKind: try container.decodeIfPresent(MeshAgentWalletExecutionKind.self, forKey: .executionKind),
            anchorTxHash: try container.decodeIfPresent(String.self, forKey: .anchorTxHash),
            txHash: try container.decodeIfPresent(String.self, forKey: .txHash),
            explorerUrl: try container.decodeIfPresent(URL.self, forKey: .explorerUrl),
            errorCode: try container.decodeIfPresent(String.self, forKey: .errorCode),
            errorMessage: try container.decodeIfPresent(String.self, forKey: .errorMessage),
            submittedAt: try container.decodeIfPresent(String.self, forKey: .submittedAt),
            confirmedAt: try container.decodeIfPresent(String.self, forKey: .confirmedAt),
            providerExtensions: try container.decodeIfPresent(
                [String: [String: String]].self,
                forKey: .providerExtensions
            ) ?? [:]
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(chainId, forKey: .chainId)
        try container.encode(network, forKey: .network)
        try container.encode(proofType, forKey: .proofType)
        try container.encode(status, forKey: .status)
        try container.encode(presentationState, forKey: .presentationState)
        try container.encode(requestHash, forKey: .requestHash)
        try container.encode(requestNonce, forKey: .requestNonce)
        try container.encode(policyId, forKey: .policyId)
        try container.encode(policyHash, forKey: .policyHash)
        try container.encode(walletAddress, forKey: .walletAddress)
        try container.encode(amount, forKey: .amount)
        try container.encode(asset, forKey: .asset)
        try container.encode(recipient, forKey: .recipient)
        try container.encode(anchoringReference, forKey: .anchoringReference)
        try container.encodeIfPresent(executionAttemptId, forKey: .executionAttemptId)
        try container.encodeIfPresent(paymentId, forKey: .paymentId)
        try container.encodeIfPresent(authorizationId, forKey: .authorizationId)
        try container.encodeIfPresent(executionId, forKey: .executionId)
        try container.encodeIfPresent(executionKind, forKey: .executionKind)
        try container.encodeIfPresent(anchorTxHash, forKey: .anchorTxHash)
        try container.encodeIfPresent(txHash, forKey: .txHash)
        try container.encodeIfPresent(explorerUrl, forKey: .explorerUrl)
        try container.encodeIfPresent(errorCode, forKey: .errorCode)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
        try container.encodeIfPresent(submittedAt, forKey: .submittedAt)
        try container.encodeIfPresent(confirmedAt, forKey: .confirmedAt)
        if !providerExtensions.isEmpty {
            try container.encode(providerExtensions, forKey: .providerExtensions)
        }
    }

    public static func normalizedVerificationStatus(
        for paymentStatus: MeshPaymentExecutionStatus
    ) -> MeshChainProofVerificationStatus {
        switch paymentStatus {
        case .confirmed:
            return MeshChainProofVerificationStatus(
                proofType: .paymentExecution,
                status: .confirmed,
                presentationState: .paidComplete,
                requiresTransactionProof: true,
                isTerminal: true
            )
        case .pending:
            return MeshChainProofVerificationStatus(
                proofType: .requestAnchor,
                status: .pending,
                presentationState: .submittedNotFinal,
                requiresTransactionProof: false,
                isTerminal: false
            )
        case .failed:
            return MeshChainProofVerificationStatus(
                proofType: .paymentExecution,
                status: .failed,
                presentationState: .attemptedFailed,
                requiresTransactionProof: false,
                isTerminal: true
            )
        case .policyDenied:
            return MeshChainProofVerificationStatus(
                proofType: .policyDenial,
                status: .failed,
                presentationState: .policyDenied,
                requiresTransactionProof: false,
                isTerminal: true
            )
        }
    }

    public func receiptResultFields() throws -> [String: String] {
        try validate()
        var result: [String: String] = [
            "chainProvider": provider,
            "chainId": chainId,
            "chainNetwork": network,
            "chainProofType": proofType.rawValue,
            "chainStatus": status.rawValue,
            "presentationState": presentationState.rawValue,
            "requestHashAlgorithm": requestHash.algorithm.lowercased(),
            "requestHash": requestHash.value.lowercased(),
            "requestNonce": requestNonce,
            "policyId": policyId,
            "policyHashAlgorithm": policyHash.algorithm.lowercased(),
            "policyHash": policyHash.value.lowercased(),
            "walletAddress": walletAddress,
            "amount": "\(amount)",
            "asset": asset,
            "recipient": recipient,
            "anchoringReference": anchoringReference
        ]
        result["executionAttemptId"] = executionAttemptId
        result["paymentId"] = paymentId
        result["authorizationId"] = authorizationId
        result["executionId"] = executionId
        result["executionKind"] = executionKind?.rawValue
        result["anchorTxHash"] = anchorTxHash
        result["txHash"] = txHash
        result["explorerUrl"] = explorerUrl?.absoluteString
        result["errorCode"] = errorCode
        result["errorMessage"] = errorMessage
        result["submittedAt"] = submittedAt
        result["confirmedAt"] = confirmedAt
        return result
    }

    static func stableReceiptField(_ field: String, _ value: String) throws -> String {
        try stableField(field, value)
    }

    public static func executionAttemptIdentity(
        paymentId: String? = nil,
        authorizationId: String? = nil,
        executionId: String
    ) throws -> String {
        let normalizedPaymentId = try paymentId.map { try stableField("paymentId", $0) }
        let normalizedAuthorizationId = try authorizationId.map { try stableField("authorizationId", $0) }
        let normalizedExecutionId = try stableField("executionId", executionId)
        return [
            "meshkit-execution-attempt/v1",
            normalizedPaymentId ?? "payment-unavailable",
            normalizedAuthorizationId ?? "authorization-unavailable",
            normalizedExecutionId
        ].joined(separator: ":")
    }

    public func transactionReference() throws -> MeshChainProofReference? {
        guard let txHash else { return nil }
        return try MeshChainProofReference(
            provider: provider,
            chainId: chainId,
            network: network,
            referenceType: .transaction,
            value: txHash,
            explorerUrl: explorerUrl
        )
    }

    public func proofReference() throws -> MeshChainProofReference {
        try MeshChainProofReference(
            provider: provider,
            chainId: chainId,
            network: network,
            referenceType: .proof,
            value: anchoringReference
        )
    }

    public func validateSignedRequestAnchorProof(
        _ requestAnchor: MeshRequestAnchor,
        policyId explicitPolicyId: String? = nil,
        policyHash explicitPolicyHash: MeshPayloadHash? = nil
    ) throws {
        try validate()
        try requestAnchor.validate()
        guard proofType == .requestAnchor,
              status == .pending,
              presentationState == .submittedNotFinal else {
            throw MeshKitValidationError.invalidChainProof("requestAnchor.status")
        }
        guard requestAnchor.status == .submitted ||
              requestAnchor.status == .pending ||
              requestAnchor.status == .confirmed else {
            throw MeshKitValidationError.invalidChainProof("requestAnchor.status")
        }
        guard provider == requestAnchor.identifier.identity.provider,
              chainId == requestAnchor.identifier.identity.chainId,
              network == requestAnchor.identifier.identity.network else {
            throw MeshKitValidationError.invalidChainProof("provider")
        }
        guard requestHash == requestAnchor.metadata.signedRequestHash else {
            throw MeshKitValidationError.invalidChainProof("requestHash")
        }
        guard requestNonce == requestAnchor.metadata.nonce else {
            throw MeshKitValidationError.invalidChainProof("requestNonce")
        }
        guard anchoringReference == requestAnchor.identifier.anchorId else {
            throw MeshKitValidationError.invalidChainProof("anchoringReference")
        }
        guard anchorTxHash == requestAnchor.identifier.transactionHash else {
            throw MeshKitValidationError.invalidChainProof("anchorTxHash")
        }
        guard txHash == nil else {
            throw MeshKitValidationError.invalidChainProof("txHash")
        }
        guard submittedAt == requestAnchor.submittedAt else {
            throw MeshKitValidationError.invalidChainProof("submittedAt")
        }

        if let payload = requestAnchor.payload {
            guard policyId == payload.policyId else {
                throw MeshKitValidationError.invalidChainProof("policyId")
            }
            guard policyHash == payload.policyHash else {
                throw MeshKitValidationError.invalidChainProof("policyHash")
            }
        }
        if let explicitPolicyId, policyId != explicitPolicyId {
            throw MeshKitValidationError.invalidChainProof("policyId")
        }
        if let explicitPolicyHash, policyHash != explicitPolicyHash {
            throw MeshKitValidationError.invalidChainProof("policyHash")
        }
    }

    public func validate() throws {
        try Self.requireField("provider", provider)
        try Self.requireField("chainId", chainId)
        try Self.requireField("network", network)
        try Self.validateHash("requestHash", requestHash)
        try Self.requireField("requestNonce", requestNonce)
        try Self.requireField("policyId", policyId)
        try Self.validateHash("policyHash", policyHash)
        try Self.requireField("walletAddress", walletAddress)
        guard amount > 0 else { throw MeshKitValidationError.invalidChainProof("amount") }
        try Self.requireField("asset", asset)
        try Self.requireField("recipient", recipient)
        try Self.requireField("anchoringReference", anchoringReference)
        if let executionAttemptId { try Self.requireField("executionAttemptId", executionAttemptId) }
        if let paymentId { try Self.requireField("paymentId", paymentId) }
        if let authorizationId { try Self.requireField("authorizationId", authorizationId) }
        if let executionId { try Self.requireField("executionId", executionId) }
        if let anchorTxHash { try Self.requireField("anchorTxHash", anchorTxHash) }
        if let txHash { try Self.requireField("txHash", txHash) }
        if let explorerUrl { try MeshChainProviderIdentity.validateNetworkURL("explorerUrl", explorerUrl) }
        if let errorCode { try Self.requireField("errorCode", errorCode) }
        if let errorMessage { try Self.requireField("errorMessage", errorMessage) }
        if let submittedAt { try Self.requireField("submittedAt", submittedAt) }
        if let confirmedAt { try Self.requireField("confirmedAt", confirmedAt) }
        try Self.validateProviderExtensions(providerExtensions)
        try validateStatusContract()
    }

    private func validateStatusContract() throws {
        switch (status, proofType, presentationState) {
        case (.confirmed, .paymentExecution, .paidComplete):
            guard txHash != nil else { throw MeshKitValidationError.invalidChainProof("txHash") }
            guard explorerUrl != nil else { throw MeshKitValidationError.invalidChainProof("explorerUrl") }
            guard confirmedAt != nil else { throw MeshKitValidationError.invalidChainProof("confirmedAt") }
            guard errorCode == nil, errorMessage == nil else {
                throw MeshKitValidationError.invalidChainProof("errorCode")
            }
        case (.pending, .requestAnchor, .submittedNotFinal),
             (.pending, .paymentExecution, .submittedNotFinal):
            guard submittedAt != nil else { throw MeshKitValidationError.invalidChainProof("submittedAt") }
            guard txHash == nil else { throw MeshKitValidationError.invalidChainProof("txHash") }
            guard explorerUrl == nil else { throw MeshKitValidationError.invalidChainProof("explorerUrl") }
            guard confirmedAt == nil, errorCode == nil, errorMessage == nil else {
                throw MeshKitValidationError.invalidChainProof("confirmedAt")
            }
        case (.failed, .paymentExecution, .attemptedFailed):
            guard errorCode != nil else { throw MeshKitValidationError.invalidChainProof("errorCode") }
            guard errorMessage != nil else { throw MeshKitValidationError.invalidChainProof("errorMessage") }
            guard txHash == nil else { throw MeshKitValidationError.invalidChainProof("txHash") }
            guard explorerUrl == nil else { throw MeshKitValidationError.invalidChainProof("explorerUrl") }
            guard confirmedAt == nil else { throw MeshKitValidationError.invalidChainProof("confirmedAt") }
        case (.failed, .policyDenial, .policyDenied):
            guard errorCode != nil else { throw MeshKitValidationError.invalidChainProof("errorCode") }
            guard errorMessage != nil else { throw MeshKitValidationError.invalidChainProof("errorMessage") }
            guard txHash == nil else { throw MeshKitValidationError.invalidChainProof("txHash") }
            guard explorerUrl == nil else { throw MeshKitValidationError.invalidChainProof("explorerUrl") }
            guard confirmedAt == nil else { throw MeshKitValidationError.invalidChainProof("confirmedAt") }
        default:
            throw MeshKitValidationError.invalidChainProof("presentationState")
        }
    }

    private static func normalizedLowercaseField(_ field: String, _ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { throw MeshKitValidationError.invalidChainProof(field) }
        try requireField(field, normalized)
        return normalized
    }

    fileprivate static func normalizedReferenceComponent(_ field: String, _ value: String) throws -> String {
        try normalizedLowercaseField(field, value)
    }

    fileprivate static func normalizedReferenceValue(_ field: String, _ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == value else { throw MeshKitValidationError.invalidChainProof(field) }
        try requireReferenceField(field, trimmed)
        if trimmed.hasPrefix("0X") {
            return "0x" + String(trimmed.dropFirst(2)).lowercased()
        }
        return trimmed
    }

    fileprivate static func requireReferenceField(_ field: String, _ value: String) throws {
        try requireField(field, value)
        guard value.rangeOfCharacter(from: CharacterSet(charactersIn: "/?#")) == nil else {
            throw MeshKitValidationError.invalidChainProof(field)
        }
    }

    private static func normalizedAsset(_ field: String, _ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { throw MeshKitValidationError.invalidChainProof(field) }
        try requireField(field, normalized)
        return normalized
    }

    private static func stableField(_ field: String, _ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == value else { throw MeshKitValidationError.invalidChainProof(field) }
        try requireField(field, trimmed)
        return trimmed
    }

    fileprivate static func requireField(_ field: String, _ value: String) throws {
        guard !value.isEmpty else { throw MeshKitValidationError.invalidChainProof(field) }
        guard value.rangeOfCharacter(from: CharacterSet.newlines.union(.controlCharacters)) == nil else {
            throw MeshKitValidationError.invalidChainProof(field)
        }
    }

    private static func validateHash(_ field: String, _ hash: MeshPayloadHash) throws {
        guard hash.algorithm.lowercased() == "sha256" else {
            throw MeshKitValidationError.unsupportedPayloadHashAlgorithm
        }
        guard hash.value.count == 64,
              hash.value.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdefABCDEF").inverted) == nil else {
            throw MeshKitValidationError.invalidChainProof("\(field).value")
        }
    }

    private static func normalizedProviderExtensions(
        _ providerExtensions: [String: [String: String]]
    ) throws -> [String: [String: String]] {
        var normalized: [String: [String: String]] = [:]
        for (provider, fields) in providerExtensions {
            let normalizedProvider = try normalizedLowercaseField("providerExtensions.provider", provider)
            guard !fields.isEmpty else {
                throw MeshKitValidationError.invalidChainProof("providerExtensions.\(normalizedProvider)")
            }
            var normalizedFields: [String: String] = [:]
            for (key, value) in fields {
                let normalizedKey = try stableField("providerExtensions.\(normalizedProvider).key", key)
                normalizedFields[normalizedKey] = try stableField(
                    "providerExtensions.\(normalizedProvider).\(normalizedKey)",
                    value
                )
            }
            normalized[normalizedProvider] = normalizedFields
        }
        return normalized
    }

    private static func validateProviderExtensions(
        _ providerExtensions: [String: [String: String]]
    ) throws {
        _ = try normalizedProviderExtensions(providerExtensions)
    }
}
