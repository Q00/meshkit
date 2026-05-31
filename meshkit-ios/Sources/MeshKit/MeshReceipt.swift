import CryptoKit
import Foundation

public struct MeshReceiptTrust: Codable, Equatable, Sendable {
    public let targetAppId: String
    public let targetBundleId: String
    public let receiptSigningAlgorithm: String
    public let receiptSigningKeyId: String
    public let publicKey: String

    public init(
        targetAppId: String,
        targetBundleId: String,
        receiptSigningAlgorithm: String,
        receiptSigningKeyId: String,
        publicKey: String
    ) {
        self.targetAppId = targetAppId
        self.targetBundleId = targetBundleId
        self.receiptSigningAlgorithm = receiptSigningAlgorithm
        self.receiptSigningKeyId = receiptSigningKeyId
        self.publicKey = publicKey
    }
}

public struct MeshReceipt: Codable, Equatable, Sendable {
    public let receiptId: String
    public let requestId: String
    public let capabilityId: String
    public let targetAppId: String
    public let targetBundleId: String
    public let requestPayloadHash: MeshPayloadHash
    public let status: String
    public let result: [String: String]
    public let nonce: String
    public let timestamp: String
    public let signature: MeshSignature

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case receiptId
        case requestId
        case capabilityId
        case targetAppId
        case targetBundleId
        case requestPayloadHash
        case status
        case result
        case nonce
        case timestamp
        case signature
    }

    public init(
        receiptId: String,
        requestId: String,
        capabilityId: String,
        targetAppId: String,
        targetBundleId: String,
        requestPayloadHash: MeshPayloadHash,
        status: String,
        result: [String: String],
        nonce: String,
        timestamp: String,
        signature: MeshSignature
    ) {
        self.receiptId = receiptId
        self.requestId = requestId
        self.capabilityId = capabilityId
        self.targetAppId = targetAppId
        self.targetBundleId = targetBundleId
        self.requestPayloadHash = requestPayloadHash
        self.status = status
        self.result = result
        self.nonce = nonce
        self.timestamp = timestamp
        self.signature = signature
    }

    public func signingInputData() -> Data {
        let components = [
            "meshkit-target-receipt-signing/v1",
            receiptId,
            requestId,
            capabilityId,
            targetAppId,
            targetBundleId,
            requestPayloadHash.algorithm.lowercased(),
            requestPayloadHash.value.lowercased(),
            status,
            MeshReceipt.canonicalResultString(result),
            timestamp,
            nonce
        ]
        return Data(components.joined(separator: "\n").utf8)
    }

    public func encodedForURLScheme() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        return data.base64EncodedString()
    }

    public static func decodedFromURLScheme(_ encoded: String) throws -> MeshReceipt {
        guard let data = Data(base64Encoded: encoded) else {
            throw MeshKitValidationError.invalidEncoding("mesh_receipt is not valid base64")
        }
        try validateProviderNeutralCoreSchema(jsonData: data)
        return try JSONDecoder().decode(MeshReceipt.self, from: data)
    }

    public func targetOwnershipMetadata() throws -> MeshReceiptOwnership {
        try MeshReceiptOwnershipMapper.ownership(of: self)
    }

    public static func validateProviderNeutralCoreSchema(jsonData data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw MeshKitValidationError.invalidEncoding("mesh_receipt is not valid JSON")
        }
        guard let receiptObject = object as? [String: Any] else {
            throw MeshKitValidationError.invalidEncoding("mesh_receipt root is not an object")
        }

        let allowedKeys = Set(CodingKeys.allCases.map(\.rawValue))
        for key in receiptObject.keys where !allowedKeys.contains(key) {
            throw MeshKitValidationError.invalidSecurityField("receipt.\(key)")
        }

        let requiredKeys = Set(MeshReceiptBaseSchema.providerNeutral.requiredRootFields)
        for key in requiredKeys where receiptObject[key] == nil {
            throw MeshKitValidationError.invalidSecurityField("receipt.\(key)")
        }

        try requireJSONString(receiptObject, key: "receiptId")
        try requireJSONString(receiptObject, key: "requestId")
        try requireJSONString(receiptObject, key: "capabilityId")
        try requireJSONString(receiptObject, key: "targetAppId")
        try requireJSONString(receiptObject, key: "targetBundleId")
        try requireJSONString(receiptObject, key: "status")
        try requireJSONString(receiptObject, key: "nonce")
        try requireJSONString(receiptObject, key: "timestamp")

        guard let requestPayloadHash = receiptObject["requestPayloadHash"] as? [String: Any] else {
            throw MeshKitValidationError.invalidSecurityField("receipt.requestPayloadHash")
        }
        let payloadHashAlgorithm = try requireJSONString(requestPayloadHash, key: "algorithm", prefix: "receipt.requestPayloadHash")
        let payloadHashValue = try requireJSONString(requestPayloadHash, key: "value", prefix: "receipt.requestPayloadHash")
        guard payloadHashAlgorithm.lowercased() == "sha256" else {
            throw MeshKitValidationError.unsupportedPayloadHashAlgorithm
        }
        guard payloadHashValue.count == 64,
              payloadHashValue.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdefABCDEF").inverted) == nil else {
            throw MeshKitValidationError.invalidSecurityField("receipt.requestPayloadHash.value")
        }

        guard let result = receiptObject["result"] as? [String: Any] else {
            throw MeshKitValidationError.invalidSecurityField("receipt.result")
        }
        for (key, value) in result {
            try requireSecurityField("receipt.result.key", key)
            guard let stringValue = value as? String else {
                throw MeshKitValidationError.invalidSecurityField("receipt.result[\(key)]")
            }
            try requireSecurityField("receipt.result[\(key)]", stringValue)
        }

        guard let signature = receiptObject["signature"] as? [String: Any] else {
            throw MeshKitValidationError.invalidSecurityField("receipt.signature")
        }
        try requireJSONString(signature, key: "algorithm", prefix: "receipt.signature")
        try requireJSONString(signature, key: "keyId", prefix: "receipt.signature")
        try requireJSONString(signature, key: "value", prefix: "receipt.signature")
    }

    @discardableResult
    private static func requireJSONString(
        _ object: [String: Any],
        key: String,
        prefix: String = "receipt"
    ) throws -> String {
        guard let value = object[key] as? String else {
            throw MeshKitValidationError.invalidSecurityField("\(prefix).\(key)")
        }
        try requireSecurityField("\(prefix).\(key)", value)
        return value
    }

    public static func canonicalResultString(_ result: [String: String]) -> String {
        result.keys.sorted().map { key in
            "\(escape(key))=\(escape(result[key] ?? ""))"
        }.joined(separator: "&")
    }

    public static func validateResultFields(_ result: [String: String]) throws {
        for (key, value) in result {
            try requireSecurityField("result.key", key)
            try requireSecurityField("result[\(key)]", value)
        }
    }

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    private static func requireSecurityField(_ field: String, _ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == value else { throw MeshKitValidationError.invalidSecurityField(field) }
        guard value.rangeOfCharacter(from: CharacterSet.newlines.union(.controlCharacters)) == nil else {
            throw MeshKitValidationError.invalidSecurityField(field)
        }
    }
}

public struct MeshReceiptBaseFieldSchema: Codable, Equatable, Sendable {
    public let name: String
    public let valueType: String
    public let requirement: MeshChainProofFieldRequirement
    public let description: String

    public init(
        name: String,
        valueType: String,
        requirement: MeshChainProofFieldRequirement,
        description: String
    ) {
        self.name = name
        self.valueType = valueType
        self.requirement = requirement
        self.description = description
    }
}

public struct MeshReceiptBaseSchema: Codable, Equatable, Sendable {
    public static let version = "meshkit-receipt-base-schema/v1"

    public let version: String
    public let fields: [MeshReceiptBaseFieldSchema]
    public let requiredRootFields: [String]
    public let ownershipResultFields: [String]
    public let anchoringResultFields: [String]
    public let paymentOrTransferResultFields: [String]
    public let timestampFields: [String]
    public let statusDiscriminatorFields: [String]

    public init(
        version: String = Self.version,
        fields: [MeshReceiptBaseFieldSchema],
        requiredRootFields: [String],
        ownershipResultFields: [String],
        anchoringResultFields: [String],
        paymentOrTransferResultFields: [String],
        timestampFields: [String],
        statusDiscriminatorFields: [String]
    ) throws {
        self.version = version
        self.fields = fields
        self.requiredRootFields = requiredRootFields
        self.ownershipResultFields = ownershipResultFields
        self.anchoringResultFields = anchoringResultFields
        self.paymentOrTransferResultFields = paymentOrTransferResultFields
        self.timestampFields = timestampFields
        self.statusDiscriminatorFields = statusDiscriminatorFields
        try validate()
    }

    public static let providerNeutral = try! MeshReceiptBaseSchema(
        fields: [
            MeshReceiptBaseFieldSchema(name: "receiptId", valueType: "string", requirement: .always, description: "Fresh target-owned receipt identifier."),
            MeshReceiptBaseFieldSchema(name: "requestId", valueType: "string", requirement: .always, description: "Signed MCP request identifier being answered."),
            MeshReceiptBaseFieldSchema(name: "capabilityId", valueType: "string", requirement: .always, description: "Target capability executed by the receipt owner."),
            MeshReceiptBaseFieldSchema(name: "targetAppId", valueType: "string", requirement: .always, description: "Target application identity that owns completion proof."),
            MeshReceiptBaseFieldSchema(name: "targetBundleId", valueType: "string", requirement: .always, description: "Target bundle identity that owns completion proof."),
            MeshReceiptBaseFieldSchema(name: "requestPayloadHash", valueType: "MeshPayloadHash", requirement: .always, description: "Hash of the MCP request payload correlated by DailyMart."),
            MeshReceiptBaseFieldSchema(name: "status", valueType: "string", requirement: .always, description: "Target receipt status discriminator."),
            MeshReceiptBaseFieldSchema(name: "result", valueType: "map<string,string>", requirement: .always, description: "Provider-neutral result fields including ownership, anchoring, payment, and chain proof linkage."),
            MeshReceiptBaseFieldSchema(name: "nonce", valueType: "string", requirement: .always, description: "Fresh target receipt nonce."),
            MeshReceiptBaseFieldSchema(name: "timestamp", valueType: "iso8601-string", requirement: .always, description: "Target receipt signing timestamp."),
            MeshReceiptBaseFieldSchema(name: "signature", valueType: "MeshSignature", requirement: .always, description: "DailyMart target receipt signature.")
        ],
        requiredRootFields: [
            "receiptId", "requestId", "capabilityId", "targetAppId", "targetBundleId",
            "requestPayloadHash", "status", "result", "nonce", "timestamp", "signature"
        ],
        ownershipResultFields: ["receiptOwner", "targetReceiptOwner"],
        anchoringResultFields: ["requestHash", "requestNonce", "anchoringReference"],
        paymentOrTransferResultFields: [
            "chainProvider", "chainNetwork", "chainId", "asset", "amount", "recipient",
            "paymentId", "authorizationId", "executionId", "executionAttemptId", "txHash", "explorerUrl"
        ],
        timestampFields: ["timestamp", "submittedAt", "confirmedAt"],
        statusDiscriminatorFields: ["status", "chainStatus", "chainProofType", "presentationState"]
    )

    public func validate() throws {
        guard version == Self.version else { throw MeshKitValidationError.invalidSecurityField("receipt.schema.version") }
        let names = fields.map(\.name)
        guard Set(names).count == names.count else {
            throw MeshKitValidationError.invalidSecurityField("receipt.schema.fields")
        }
        let fieldSet = Set(names)
        for field in requiredRootFields {
            guard fieldSet.contains(field) else {
                throw MeshKitValidationError.invalidSecurityField("receipt.schema.requiredRootFields")
            }
        }
    }
}

public struct MeshReceiptChainProofPayload: Codable, Equatable, Sendable {
    public static let version = "meshkit-receipt-chain-proof/v1"

    public let version: String
    public let proof: MeshChainProof

    public init(proof: MeshChainProof, version: String = MeshReceiptChainProofPayload.version) throws {
        self.version = version
        self.proof = proof
        try validate()
    }

    public func validate() throws {
        guard version == Self.version else { throw MeshKitValidationError.invalidChainProof("receiptChainProof.version") }
        try proof.validate()
    }
}

public enum MeshReceiptChainProofSerializer {
    public static let encodedProofResultKey = "chainProof"
    public static let encodedProofEncodingResultKey = "chainProofEncoding"
    public static let encodedProofEncoding = "base64-json"
    public static let proofVersionResultKey = "chainProofVersion"
    public static let externalChainExitConditionResultKey = "externalChainExitCondition"
    public static let externalChainBlockerTypeResultKey = "externalChainBlockerType"
    public static let externalChainOperationResultKey = "externalChainOperation"
    public static let externalChainObservedAtResultKey = "externalChainObservedAt"
    public static let externalChainEndpointResultKey = "externalChainEndpoint"
    public static let externalChainMessageResultKey = "externalChainMessage"

    public static func receiptResultFields(
        baseResult: [String: String],
        proof: MeshChainProof
    ) throws -> [String: String] {
        try MeshReceipt.validateResultFields(baseResult)
        let payload = try MeshReceiptChainProofPayload(proof: proof)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encodedProof = try encoder.encode(payload).base64EncodedString()

        var result = baseResult
        result[proofVersionResultKey] = MeshReceiptChainProofPayload.version
        result[encodedProofEncodingResultKey] = encodedProofEncoding
        result[encodedProofResultKey] = encodedProof
        for (key, value) in externalChainBlockerResultFields(from: proof) {
            result[key] = value
        }
        for (key, value) in try proof.receiptResultFields() {
            result[key] = value
        }
        if proof.status != .confirmed {
            result["txHash"] = nil
            result["explorerUrl"] = nil
        }
        try MeshReceipt.validateResultFields(result)
        return result
    }

    public static func externalChainBlockerResultFields(from proof: MeshChainProof) -> [String: String] {
        for provider in proof.providerExtensions.keys.sorted() {
            guard let fields = proof.providerExtensions[provider],
                  fields["exitCondition"] == MeshExternalChainBlockerEvidence.exitCondition else {
                continue
            }

            var result = [
                externalChainExitConditionResultKey: MeshExternalChainBlockerEvidence.exitCondition
            ]
            result[externalChainBlockerTypeResultKey] = fields["blockerType"]
            result[externalChainOperationResultKey] = fields["operation"]
            result[externalChainObservedAtResultKey] = fields["observedAt"]
            result[externalChainEndpointResultKey] = fields["endpoint"]
            result[externalChainMessageResultKey] = fields["message"]
            return result
        }
        return [:]
    }

    public static func decodeProof(from result: [String: String]) throws -> MeshChainProof {
        try MeshReceipt.validateResultFields(result)
        guard result[proofVersionResultKey] == MeshReceiptChainProofPayload.version else {
            throw MeshKitValidationError.invalidChainProof("receiptChainProof.version")
        }
        guard result[encodedProofEncodingResultKey] == encodedProofEncoding else {
            throw MeshKitValidationError.invalidChainProof("receiptChainProof.encoding")
        }
        guard let encodedProof = result[encodedProofResultKey],
              let data = Data(base64Encoded: encodedProof) else {
            throw MeshKitValidationError.invalidChainProof("receiptChainProof.payload")
        }
        let payload = try JSONDecoder().decode(MeshReceiptChainProofPayload.self, from: data)
        try payload.validate()
        return payload.proof
    }

    public static func targetOwnedProof(
        in receipt: MeshReceipt,
        expectedTargetAppId: String,
        expectedTargetBundleId: String,
        expectedRequest: MeshRequest? = nil
    ) throws -> MeshReceiptChainProofOwnership {
        let ownership = try MeshReceiptOwnershipMapper.assertTargetOwned(
            receipt,
            expectedTargetAppId: expectedTargetAppId,
            expectedTargetBundleId: expectedTargetBundleId
        )
        let proof = try decodeProof(from: receipt.result)
        try validateProofBinding(proof, receipt: receipt, expectedRequest: expectedRequest)
        return try MeshReceiptChainProofOwnership(receipt: receipt, ownership: ownership, proof: proof)
    }

    private static func validateProofBinding(
        _ proof: MeshChainProof,
        receipt: MeshReceipt,
        expectedRequest: MeshRequest?
    ) throws {
        try proof.validate()

        if let expectedRequest {
            guard receipt.requestId == expectedRequest.requestId,
                  receipt.capabilityId == expectedRequest.target.capabilityId,
                  receipt.requestPayloadHash == expectedRequest.payloadHash else {
                throw MeshKitValidationError.receiptCorrelationMismatch
            }
            guard proof.requestNonce == expectedRequest.nonce else {
                throw MeshKitValidationError.invalidChainProof("requestNonce")
            }
            guard proof.requestHash == (try MeshRequestAnchorCanonicalization.signedRequestHash(for: expectedRequest)) else {
                throw MeshKitValidationError.invalidChainProof("requestHash")
            }
        }

        _ = try proof.proofReference()
        if proof.status == .confirmed {
            guard try proof.transactionReference() != nil else {
                throw MeshKitValidationError.invalidChainProof("txHash")
            }
        }
    }
}

public struct MeshReceiptOwnership: Codable, Equatable, Sendable {
    public let receiptId: String
    public let requestId: String
    public let receiptOwner: String
    public let targetReceiptOwner: String
    public let targetAppId: String
    public let targetBundleId: String
    public let targetSignatureKeyId: String

    public init(
        receiptId: String,
        requestId: String,
        receiptOwner: String,
        targetReceiptOwner: String,
        targetAppId: String,
        targetBundleId: String,
        targetSignatureKeyId: String
    ) {
        self.receiptId = receiptId
        self.requestId = requestId
        self.receiptOwner = receiptOwner
        self.targetReceiptOwner = targetReceiptOwner
        self.targetAppId = targetAppId
        self.targetBundleId = targetBundleId
        self.targetSignatureKeyId = targetSignatureKeyId
    }

    public var isTargetOwned: Bool {
        receiptOwner == targetReceiptOwner
    }
}

public struct MeshReceiptChainProofOwnership: Codable, Equatable, Sendable {
    public let receiptId: String
    public let requestId: String
    public let ownership: MeshReceiptOwnership
    public let anchoredRequestLinkage: MeshReceiptAnchoredRequestLinkage
    public let proof: MeshChainProof
    public let proofReference: MeshChainProofReference
    public let transactionReference: MeshChainProofReference?

    public init(
        receipt: MeshReceipt,
        ownership: MeshReceiptOwnership,
        proof: MeshChainProof
    ) throws {
        guard receipt.receiptId == ownership.receiptId,
              receipt.requestId == ownership.requestId,
              ownership.isTargetOwned else {
            throw MeshKitValidationError.targetIdentityMismatch
        }
        try proof.validate()
        self.receiptId = receipt.receiptId
        self.requestId = receipt.requestId
        self.ownership = ownership
        self.anchoredRequestLinkage = try MeshReceiptAnchoredRequestLinkage(
            receiptId: receipt.receiptId,
            requestId: receipt.requestId,
            requestHash: proof.requestHash,
            anchoringReference: proof.anchoringReference
        )
        self.proof = proof
        self.proofReference = try proof.proofReference()
        self.transactionReference = try proof.transactionReference()
    }
}

public struct MeshReceiptAnchoredRequestLinkage: Codable, Equatable, Sendable {
    public let receiptId: String
    public let requestId: String
    public let requestHash: MeshPayloadHash
    public let anchoringReference: String

    private enum CodingKeys: String, CodingKey {
        case receiptId
        case requestId
        case requestHash
        case anchoringReference
    }

    public init(
        receiptId: String,
        requestId: String,
        requestHash: MeshPayloadHash,
        anchoringReference: String
    ) throws {
        self.receiptId = try MeshReceiptAnchoredRequestLinkage.stableField("receiptId", receiptId)
        self.requestId = try MeshReceiptAnchoredRequestLinkage.stableField("requestId", requestId)
        self.requestHash = requestHash
        self.anchoringReference = try MeshReceiptAnchoredRequestLinkage.stableField(
            "anchoringReference",
            anchoringReference
        )
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            receiptId: try container.decode(String.self, forKey: .receiptId),
            requestId: try container.decode(String.self, forKey: .requestId),
            requestHash: try container.decode(MeshPayloadHash.self, forKey: .requestHash),
            anchoringReference: try container.decode(String.self, forKey: .anchoringReference)
        )
    }

    public func validate() throws {
        try MeshReceiptAnchoredRequestLinkage.validateHash("requestHash", requestHash)
        _ = try MeshReceiptAnchoredRequestLinkage.stableField("receiptId", receiptId)
        _ = try MeshReceiptAnchoredRequestLinkage.stableField("requestId", requestId)
        _ = try MeshReceiptAnchoredRequestLinkage.stableField("anchoringReference", anchoringReference)
    }

    private static func validateHash(_ field: String, _ hash: MeshPayloadHash) throws {
        guard hash.algorithm.lowercased() == "sha256" else { throw MeshKitValidationError.invalidChainProof(field) }
        guard hash.value.count == 64,
              hash.value.lowercased() == hash.value,
              hash.value.allSatisfy({ $0.isHexDigit }) else {
            throw MeshKitValidationError.invalidChainProof("\(field).value")
        }
    }

    private static func stableField(_ field: String, _ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == value else { throw MeshKitValidationError.invalidChainProof(field) }
        guard value.rangeOfCharacter(from: CharacterSet.newlines.union(.controlCharacters)) == nil else {
            throw MeshKitValidationError.invalidChainProof(field)
        }
        return value
    }
}

public enum MeshReceiptOwnershipMapper {
    public static let receiptOwnerResultKey = "receiptOwner"
    public static let targetReceiptOwnerResultKey = "targetReceiptOwner"

    public static func targetOwnedResultFields(
        baseResult: [String: String],
        targetAppId: String,
        targetBundleId: String
    ) throws -> [String: String] {
        try MeshReceipt.validateResultFields(baseResult)
        let owner = try ownerIdentifier(targetAppId: targetAppId, targetBundleId: targetBundleId)
        var result = baseResult
        result[receiptOwnerResultKey] = owner
        result[targetReceiptOwnerResultKey] = owner
        try MeshReceipt.validateResultFields(result)
        return result
    }

    public static func ownership(ofSerializedReceipt encodedReceipt: String) throws -> MeshReceiptOwnership {
        try ownership(of: MeshReceipt.decodedFromURLScheme(encodedReceipt))
    }

    public static func ownership(of receipt: MeshReceipt) throws -> MeshReceiptOwnership {
        try MeshReceipt.validateResultFields(receipt.result)
        let fallbackOwner = try ownerIdentifier(targetAppId: receipt.targetAppId, targetBundleId: receipt.targetBundleId)
        let receiptOwner = receipt.result[receiptOwnerResultKey] ?? fallbackOwner
        let targetReceiptOwner = receipt.result[targetReceiptOwnerResultKey] ?? fallbackOwner
        try MeshReceipt.validateResultFields([
            receiptOwnerResultKey: receiptOwner,
            targetReceiptOwnerResultKey: targetReceiptOwner
        ])
        return MeshReceiptOwnership(
            receiptId: receipt.receiptId,
            requestId: receipt.requestId,
            receiptOwner: receiptOwner,
            targetReceiptOwner: targetReceiptOwner,
            targetAppId: receipt.targetAppId,
            targetBundleId: receipt.targetBundleId,
            targetSignatureKeyId: receipt.signature.keyId
        )
    }

    @discardableResult
    public static func assertTargetOwned(
        _ receipt: MeshReceipt,
        expectedTargetAppId: String,
        expectedTargetBundleId: String
    ) throws -> MeshReceiptOwnership {
        let ownership = try ownership(of: receipt)
        let expectedOwner = try ownerIdentifier(targetAppId: expectedTargetAppId, targetBundleId: expectedTargetBundleId)
        guard receipt.targetAppId == expectedTargetAppId,
              receipt.targetBundleId == expectedTargetBundleId,
              ownership.receiptOwner == expectedOwner,
              ownership.targetReceiptOwner == expectedOwner,
              ownership.isTargetOwned else {
            throw MeshKitValidationError.targetIdentityMismatch
        }
        return ownership
    }

    public static func ownerIdentifier(targetAppId: String, targetBundleId: String) throws -> String {
        try MeshReceipt.validateResultFields([
            "targetAppId": targetAppId,
            "targetBundleId": targetBundleId
        ])
        return "\(targetAppId)#\(targetBundleId)"
    }
}

public struct MeshReceiptSigner: Sendable {
    public let algorithm: String
    public let keyId: String
    private let signData: @Sendable (Data) throws -> Data

    public init(algorithm: String, keyId: String, signData: @escaping @Sendable (Data) throws -> Data) {
        self.algorithm = algorithm
        self.keyId = keyId
        self.signData = signData
    }

    public static func ed25519(keyId: String, privateKey: Curve25519.Signing.PrivateKey) -> MeshReceiptSigner {
        MeshReceiptSigner(algorithm: "Ed25519", keyId: keyId) { data in
            try privateKey.signature(for: data)
        }
    }

    public func makeReceipt(
        receiptId: String,
        request: MeshRequest,
        targetAppId: String,
        targetBundleId: String,
        status: String,
        result: [String: String],
        nonce: String = UUID().uuidString,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) throws -> MeshReceipt {
        let unsigned = MeshReceipt(
            receiptId: receiptId,
            requestId: request.requestId,
            capabilityId: request.target.capabilityId,
            targetAppId: targetAppId,
            targetBundleId: targetBundleId,
            requestPayloadHash: request.payloadHash,
            status: status,
            result: result,
            nonce: nonce,
            timestamp: timestamp,
            signature: MeshSignature(algorithm: algorithm, keyId: keyId, value: "")
        )
        let signature = try signData(unsigned.signingInputData()).base64EncodedString()
        return MeshReceipt(
            receiptId: unsigned.receiptId,
            requestId: unsigned.requestId,
            capabilityId: unsigned.capabilityId,
            targetAppId: unsigned.targetAppId,
            targetBundleId: unsigned.targetBundleId,
            requestPayloadHash: unsigned.requestPayloadHash,
            status: unsigned.status,
            result: unsigned.result,
            nonce: unsigned.nonce,
            timestamp: unsigned.timestamp,
            signature: MeshSignature(algorithm: algorithm, keyId: keyId, value: signature)
        )
    }
}

public enum MeshReceiptVerifier {
    public static func verify(_ receipt: MeshReceipt, trust: MeshReceiptTrust, maxAgeSeconds: TimeInterval = 300) throws -> MeshReceipt {
        try validateEnvelope(receipt)
        guard receipt.targetAppId == trust.targetAppId else { throw MeshKitValidationError.targetIdentityMismatch }
        guard receipt.targetBundleId == trust.targetBundleId else { throw MeshKitValidationError.targetIdentityMismatch }
        guard receipt.signature.algorithm == trust.receiptSigningAlgorithm else {
            throw MeshKitValidationError.signatureMismatch("receipt signing algorithm mismatch")
        }
        guard receipt.signature.keyId == trust.receiptSigningKeyId else {
            throw MeshKitValidationError.signatureMismatch("receipt signing key id mismatch")
        }
        guard trust.receiptSigningAlgorithm == "Ed25519" else {
            throw MeshKitValidationError.signatureMismatch("unsupported receipt signing algorithm: \(trust.receiptSigningAlgorithm)")
        }
        guard let timestamp = ISO8601DateFormatter().date(from: receipt.timestamp), abs(timestamp.timeIntervalSinceNow) <= maxAgeSeconds else {
            throw MeshKitValidationError.staleTimestamp
        }
        guard let publicKeyData = Data(base64Encoded: trust.publicKey), !publicKeyData.isEmpty else { throw MeshKitValidationError.signatureRequired }
        guard let signatureData = Data(base64Encoded: receipt.signature.value), !signatureData.isEmpty else {
            throw MeshKitValidationError.signatureMismatch("receipt signature is not valid base64")
        }
        do {
            let verifier = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
            guard verifier.isValidSignature(signatureData, for: receipt.signingInputData()) else {
                throw MeshKitValidationError.signatureMismatch("invalid receipt signature")
            }
        } catch let error as MeshKitValidationError {
            throw error
        } catch {
            throw MeshKitValidationError.signatureMismatch("invalid receipt signing public key")
        }
        return receipt
    }

    private static func validateEnvelope(_ receipt: MeshReceipt) throws {
        try requireSecurityField("receiptId", receipt.receiptId)
        try requireSecurityField("requestId", receipt.requestId)
        try requireSecurityField("capabilityId", receipt.capabilityId)
        try requireSecurityField("targetAppId", receipt.targetAppId)
        try requireSecurityField("targetBundleId", receipt.targetBundleId)
        try requireSecurityField("status", receipt.status)
        try requireSecurityField("nonce", receipt.nonce)
        try requireSecurityField("timestamp", receipt.timestamp)
        try requireSecurityField("signature.algorithm", receipt.signature.algorithm)
        try requireSecurityField("signature.keyId", receipt.signature.keyId)
        if receipt.signature.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MeshKitValidationError.signatureRequired }
        guard receipt.requestPayloadHash.algorithm.lowercased() == "sha256" else { throw MeshKitValidationError.unsupportedPayloadHashAlgorithm }
        guard receipt.requestPayloadHash.value.count == 64,
              receipt.requestPayloadHash.value.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdefABCDEF").inverted) == nil else {
            throw MeshKitValidationError.invalidSecurityField("requestPayloadHash.value")
        }
        for (key, value) in receipt.result {
            try requireSecurityField("result.key", key)
            try requireSecurityField("result[\(key)]", value)
        }
    }

    private static func requireSecurityField(_ field: String, _ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == value else { throw MeshKitValidationError.invalidSecurityField(field) }
        guard value.rangeOfCharacter(from: CharacterSet.newlines.union(.controlCharacters)) == nil else {
            throw MeshKitValidationError.invalidSecurityField(field)
        }
    }
}

public final class MeshPendingReceiptStore: @unchecked Sendable {
    private struct Pending: Sendable {
        let requestId: String
        let capabilityId: String
        let requestPayloadHash: MeshPayloadHash
    }

    private var pending: [String: Pending] = [:]
    private var consumed = Set<String>()
    private let lock = NSLock()

    public init() {}

    @discardableResult
    public func register(request: MeshRequest, capabilityId: String? = nil) -> String {
        let token = request.requestId
        lock.lock()
        defer { lock.unlock() }
        pending[token] = Pending(
            requestId: request.requestId,
            capabilityId: capabilityId ?? request.target.capabilityId,
            requestPayloadHash: request.payloadHash
        )
        return token
    }

    public func consumeVerified(
        _ receipt: MeshReceipt,
        expectedToken: String,
        trust: MeshReceiptTrust,
        maxAgeSeconds: TimeInterval = 300
    ) throws -> MeshReceipt {
        let pendingRecord: Pending
        lock.lock()
        if consumed.contains(expectedToken) {
            lock.unlock()
            throw MeshKitValidationError.replayDetected(expectedToken)
        }
        guard let stored = pending[expectedToken] else {
            lock.unlock()
            throw MeshKitValidationError.receiptCorrelationMismatch
        }
        pendingRecord = stored
        lock.unlock()

        guard receipt.requestId == expectedToken,
              receipt.requestId == pendingRecord.requestId,
              receipt.capabilityId == pendingRecord.capabilityId,
              receipt.requestPayloadHash == pendingRecord.requestPayloadHash else {
            throw MeshKitValidationError.receiptCorrelationMismatch
        }

        let verified = try MeshReceiptVerifier.verify(receipt, trust: trust, maxAgeSeconds: maxAgeSeconds)

        lock.lock()
        pending.removeValue(forKey: expectedToken)
        consumed.insert(expectedToken)
        lock.unlock()
        return verified
    }
}
