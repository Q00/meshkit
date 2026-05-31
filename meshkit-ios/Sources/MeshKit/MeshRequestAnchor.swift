import CryptoKit
import Foundation
#if canImport(FoundationNetworking)
@preconcurrency import FoundationNetworking
#endif

public enum MeshRequestAnchorStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case submitted
    case pending
    case confirmed
    case failed
    case unavailable
}

public enum MeshMarooTestnetRequestAnchorProviderOutcome: String, Codable, CaseIterable, Equatable, Sendable {
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
            throw MeshKitValidationError.invalidChainProviderIdentity("providerOutcome")
        }

        switch normalized {
        case "success",
             "succeeded",
             "confirmed",
             "complete",
             "completed",
             "anchored",
             "committed",
             "included",
             "finalized",
             "finalised":
            self = .success
        case "pending",
             "submitted",
             "accepted",
             "queued",
             "broadcast",
             "broadcasted",
             "processing",
             "in_flight",
             "awaiting_confirmation",
             "unconfirmed":
            self = .pending
        case "failure",
             "failed",
             "error",
             "rejected",
             "declined",
             "reverted",
             "dropped",
             "expired",
             "timeout",
             "timed_out",
             "rpc_error",
             "provider_error":
            self = .failure
        case "policy_denied",
             "policydenied",
             "policy_rejected",
             "policy_rejection",
             "authorization_denied",
             "auth_denied",
             "wallet_policy_denied",
             "spending_limit_denied",
             "spending_limit_exceeded",
             "delegated_limit_exceeded",
             "limit_exceeded":
            self = .policyDenied
        default:
            throw MeshKitValidationError.invalidChainProviderIdentity("providerOutcome")
        }
    }

    public var anchorStatus: MeshRequestAnchorStatus {
        switch self {
        case .success:
            return .confirmed
        case .pending:
            return .pending
        case .failure, .policyDenied:
            return .failed
        }
    }

    public var isPolicyDenied: Bool {
        self == .policyDenied
    }
}

public struct MeshMarooTestnetRequestAnchorResultMapping: Codable, Equatable, Sendable {
    public let providerOutcome: MeshMarooTestnetRequestAnchorProviderOutcome
    public let anchorStatus: MeshRequestAnchorStatus
    public let isPolicyDenied: Bool
    public let errorCode: String?
    public let defaultMessage: String?

    public init(providerOutcome: MeshMarooTestnetRequestAnchorProviderOutcome) {
        self.providerOutcome = providerOutcome
        self.anchorStatus = providerOutcome.anchorStatus
        self.isPolicyDenied = providerOutcome.isPolicyDenied

        switch providerOutcome {
        case .success, .pending:
            self.errorCode = nil
            self.defaultMessage = nil
        case .failure:
            self.errorCode = "request_anchor_failed"
            self.defaultMessage = "maroo testnet request anchor submission failed"
        case .policyDenied:
            self.errorCode = "policy_denied"
            self.defaultMessage = "maroo testnet request anchor policy denied"
        }
    }

    public init(providerOutcome value: String) throws {
        self.init(providerOutcome: try MeshMarooTestnetRequestAnchorProviderOutcome(providerValue: value))
    }
}

public struct MeshMarooTestnetRequestAnchorStateMapping: Codable, Equatable, Sendable {
    public let providerAnchorState: String
    public let providerOutcome: MeshMarooTestnetRequestAnchorProviderOutcome
    public let anchorStatus: MeshRequestAnchorStatus
    public let defaultMessage: String?

    public init(providerAnchorState value: String) throws {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        guard !normalized.isEmpty else {
            throw MeshKitValidationError.invalidChainProviderIdentity("providerAnchorState")
        }

        switch normalized {
        case "anchored",
             "committed",
             "complete",
             "completed",
             "confirmed",
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
             "tx_finalised",
             "tx_finalized",
             "tx_included",
             "tx_mined",
             "tx_success",
             "tx_succeeded":
            self.providerAnchorState = normalized
            self.providerOutcome = .success
            self.anchorStatus = .confirmed
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
            self.providerAnchorState = normalized
            self.providerOutcome = .pending
            self.anchorStatus = .pending
            self.defaultMessage = nil
        case "contract_reverted",
             "declined",
             "dropped",
             "error",
             "expired",
             "failed",
             "failure",
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
             "tx_expired",
             "tx_failed",
             "tx_failure",
             "tx_provider_error",
             "tx_rejected",
             "tx_reverted",
             "tx_rpc_error",
             "tx_timeout",
             "tx_timed_out":
            self.providerAnchorState = normalized
            self.providerOutcome = .failure
            self.anchorStatus = .failed
            self.defaultMessage = "maroo testnet request anchor submission failed"
        default:
            throw MeshKitValidationError.invalidChainProviderIdentity("providerAnchorState")
        }
    }
}

public struct MeshRequestAnchorHashInput: Codable, Equatable, Sendable {
    public let version: String
    public let requestId: String
    public let nonce: String
    public let timestamp: String
    public let callerAppId: String
    public let callerBundleId: String
    public let callerPublicKeyId: String
    public let targetBundleId: String
    public let capabilityId: String
    public let capabilityVersion: String
    public let payloadHashAlgorithm: String
    public let payloadHashValue: String
    public let signatureAlgorithm: String
    public let signatureKeyId: String
    public let signatureValue: String
    public let canonicalString: String

    public init(request: MeshRequest) throws {
        try MeshTarget.validateRequestEnvelope(request)
        guard !request.signature.algorithm.isEmpty,
              !request.signature.keyId.isEmpty,
              !request.signature.value.isEmpty else {
            throw MeshKitValidationError.signatureRequired
        }

        self.version = MeshRequestAnchorCanonicalization.version
        self.requestId = try normalizedAnchorField("requestId", request.requestId)
        self.nonce = try normalizedAnchorField("nonce", request.nonce)
        self.timestamp = try normalizedAnchorField("timestamp", request.timestamp)
        self.callerAppId = try normalizedAnchorField("callerAppId", request.caller.appId)
        self.callerBundleId = try normalizedAnchorField("callerBundleId", request.caller.bundleId)
        self.callerPublicKeyId = try normalizedAnchorField("callerPublicKeyId", request.caller.publicKeyId)
        self.targetBundleId = try normalizedAnchorField("targetBundleId", request.target.targetBundleId)
        self.capabilityId = try normalizedAnchorField("capabilityId", request.target.capabilityId)
        self.capabilityVersion = try normalizedAnchorField("capabilityVersion", request.target.version)
        self.payloadHashAlgorithm = request.payloadHash.algorithm.lowercased()
        self.payloadHashValue = request.payloadHash.value.lowercased()
        self.signatureAlgorithm = try normalizedAnchorField("signature.algorithm", request.signature.algorithm)
        self.signatureKeyId = try normalizedAnchorField("signature.keyId", request.signature.keyId)
        self.signatureValue = try normalizedAnchorField("signature.value", request.signature.value)
        try validateHash("payloadHash", MeshPayloadHash(algorithm: payloadHashAlgorithm, value: payloadHashValue))

        self.canonicalString = [
            version,
            "requestId=\(requestId)",
            "nonce=\(nonce)",
            "timestamp=\(timestamp)",
            "callerAppId=\(callerAppId)",
            "callerBundleId=\(callerBundleId)",
            "callerPublicKeyId=\(callerPublicKeyId)",
            "targetBundleId=\(targetBundleId)",
            "capabilityId=\(capabilityId)",
            "capabilityVersion=\(capabilityVersion)",
            "payloadHashAlgorithm=\(payloadHashAlgorithm)",
            "payloadHashValue=\(payloadHashValue)",
            "signatureAlgorithm=\(signatureAlgorithm)",
            "signatureKeyId=\(signatureKeyId)",
            "signatureValue=\(signatureValue)"
        ].joined(separator: "\n")
    }

    public var data: Data {
        Data(canonicalString.utf8)
    }

    public func sha256Hash() -> MeshPayloadHash {
        let digest = SHA256.hash(data: data)
        return MeshPayloadHash(value: digest.map { String(format: "%02x", $0) }.joined())
    }
}

public enum MeshRequestAnchorCanonicalization {
    public static let version = "meshkit-request-anchor/v1"

    public static func canonicalRequestHashInput(for request: MeshRequest) throws -> MeshRequestAnchorHashInput {
        try MeshRequestAnchorHashInput(request: request)
    }

    public static func signedRequestHash(for request: MeshRequest) throws -> MeshPayloadHash {
        try canonicalRequestHashInput(for: request).sha256Hash()
    }

    public static func anchoringReference(
        for request: MeshRequest,
        providerIdentity: MeshChainProviderIdentity
    ) throws -> MeshRequestAnchorIdentifier {
        try anchoringReference(
            forSignedRequestHash: signedRequestHash(for: request),
            providerIdentity: providerIdentity
        )
    }

    public static func anchoringReference(
        forSignedRequestHash signedRequestHash: MeshPayloadHash,
        providerIdentity: MeshChainProviderIdentity
    ) throws -> MeshRequestAnchorIdentifier {
        try validateHash("signedRequestHash", signedRequestHash)
        try providerIdentity.validate()

        return try MeshRequestAnchorIdentifier(
            identity: providerIdentity,
            anchorId: anchoringReferenceId(forSignedRequestHash: signedRequestHash)
        )
    }

    public static func anchoringReference(
        for metadata: MeshSignedRequestAnchorMetadata,
        providerIdentity: MeshChainProviderIdentity
    ) throws -> MeshRequestAnchorIdentifier {
        try metadata.validate()
        return try anchoringReference(
            forSignedRequestHash: metadata.signedRequestHash,
            providerIdentity: providerIdentity
        )
    }

    public static func anchoringReferenceId(
        forSignedRequestHash signedRequestHash: MeshPayloadHash
    ) throws -> String {
        try validateHash("signedRequestHash", signedRequestHash)
        return "request-anchor-\(signedRequestHash.algorithm.lowercased())-\(signedRequestHash.value.lowercased())"
    }

    public static func validate(
        metadata: MeshSignedRequestAnchorMetadata,
        boundTo request: MeshRequest
    ) throws {
        try metadata.validate()
        let hashInput = try canonicalRequestHashInput(for: request)
        guard metadata.requestId == request.requestId else {
            throw MeshKitValidationError.signatureMismatch("request anchor request id mismatch")
        }
        guard metadata.nonce == hashInput.nonce else {
            throw MeshKitValidationError.signatureMismatch("request anchor nonce mismatch")
        }
        guard metadata.timestamp == request.timestamp else {
            throw MeshKitValidationError.signatureMismatch("request anchor timestamp mismatch")
        }
        guard metadata.callerAppId == request.caller.appId,
              metadata.callerBundleId == request.caller.bundleId,
              metadata.targetBundleId == request.target.targetBundleId,
              metadata.capabilityId == request.target.capabilityId else {
            throw MeshKitValidationError.signatureMismatch("request anchor envelope mismatch")
        }
        guard metadata.payloadHash == request.payloadHash else {
            throw MeshKitValidationError.payloadHashMismatch
        }
        guard metadata.signature == request.signature else {
            throw MeshKitValidationError.signatureMismatch("request anchor signature mismatch")
        }
        guard metadata.signedRequestHash == hashInput.sha256Hash() else {
            throw MeshKitValidationError.signatureMismatch("request anchor signed request hash mismatch")
        }
    }
}

public struct MeshSignedRequestAnchorMetadata: Codable, Equatable, Sendable {
    public let requestId: String
    public let nonce: String
    public let timestamp: String
    public let callerAppId: String
    public let callerBundleId: String
    public let targetBundleId: String
    public let capabilityId: String
    public let payloadHash: MeshPayloadHash
    public let signature: MeshSignature
    public let signedRequestHash: MeshPayloadHash

    public init(request: MeshRequest) throws {
        try MeshTarget.validateRequestEnvelope(request)
        guard !request.signature.algorithm.isEmpty,
              !request.signature.keyId.isEmpty,
              !request.signature.value.isEmpty else {
            throw MeshKitValidationError.signatureRequired
        }

        self.requestId = request.requestId
        self.nonce = request.nonce
        self.timestamp = request.timestamp
        self.callerAppId = request.caller.appId
        self.callerBundleId = request.caller.bundleId
        self.targetBundleId = request.target.targetBundleId
        self.capabilityId = request.target.capabilityId
        self.payloadHash = request.payloadHash
        self.signature = request.signature
        self.signedRequestHash = try MeshRequestAnchorCanonicalization.signedRequestHash(for: request)
        try validate()
        try MeshRequestAnchorCanonicalization.validate(metadata: self, boundTo: request)
    }

    public init(
        requestId: String,
        nonce: String,
        timestamp: String,
        callerAppId: String,
        callerBundleId: String,
        targetBundleId: String,
        capabilityId: String,
        payloadHash: MeshPayloadHash,
        signature: MeshSignature,
        signedRequestHash: MeshPayloadHash
    ) throws {
        self.requestId = requestId
        self.nonce = nonce
        self.timestamp = timestamp
        self.callerAppId = callerAppId
        self.callerBundleId = callerBundleId
        self.targetBundleId = targetBundleId
        self.capabilityId = capabilityId
        self.payloadHash = payloadHash
        self.signature = signature
        self.signedRequestHash = signedRequestHash
        try validate()
    }

    public func validate() throws {
        try requireAnchorField("requestId", requestId)
        try requireAnchorField("nonce", nonce)
        try requireAnchorField("timestamp", timestamp)
        try requireAnchorField("callerAppId", callerAppId)
        try requireAnchorField("callerBundleId", callerBundleId)
        try requireAnchorField("targetBundleId", targetBundleId)
        try requireAnchorField("capabilityId", capabilityId)
        try requireAnchorField("signature.algorithm", signature.algorithm)
        try requireAnchorField("signature.keyId", signature.keyId)
        try requireAnchorField("signature.value", signature.value)
        try validateHash("payloadHash", payloadHash)
        try validateHash("signedRequestHash", signedRequestHash)
    }

}

public struct MeshRequestAnchorPayload: Codable, Equatable, Sendable {
    public let version: String
    public let metadata: MeshSignedRequestAnchorMetadata
    public let requestNonce: String
    public let policyId: String
    public let policyHash: MeshPayloadHash

    private enum CodingKeys: String, CodingKey {
        case version
        case metadata
        case requestNonce
        case policyId
        case policyHash
    }

    public init(
        metadata: MeshSignedRequestAnchorMetadata,
        policyId: String,
        policyHash: MeshPayloadHash,
        version: String = MeshRequestAnchorCanonicalization.version
    ) throws {
        self.version = try normalizedAnchorField("version", version)
        self.metadata = metadata
        self.requestNonce = try normalizedAnchorField("requestNonce", metadata.nonce)
        self.policyId = try normalizedAnchorField("policyId", policyId)
        self.policyHash = policyHash
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(String.self, forKey: .version)
        self.metadata = try container.decode(MeshSignedRequestAnchorMetadata.self, forKey: .metadata)
        self.requestNonce = try container.decodeIfPresent(String.self, forKey: .requestNonce) ?? metadata.nonce
        self.policyId = try container.decode(String.self, forKey: .policyId)
        self.policyHash = try container.decode(MeshPayloadHash.self, forKey: .policyHash)
        try validate()
    }

    public func validate() throws {
        guard version == MeshRequestAnchorCanonicalization.version else {
            throw MeshKitValidationError.invalidChainProviderIdentity("version")
        }
        try metadata.validate()
        try validateAnchorIdentifierFormat("requestNonce", requestNonce)
        guard requestNonce == metadata.nonce else {
            throw MeshKitValidationError.signatureMismatch("request anchor payload nonce mismatch")
        }
        try validateAnchorIdentifierFormat("policyId", policyId)
        try validateHash("policyHash", policyHash)
    }
}

public struct MeshSignedMCPRequestAnchoringFields: Codable, Equatable, Sendable {
    public let signedMCPRequestHash: MeshPayloadHash
    public let requestNonce: String
    public let policyId: String
    public let policyHash: MeshPayloadHash

    public init(
        signedMCPRequestHash: MeshPayloadHash,
        requestNonce: String,
        policyId: String,
        policyHash: MeshPayloadHash
    ) throws {
        self.signedMCPRequestHash = signedMCPRequestHash
        self.requestNonce = try normalizedAnchorField("requestNonce", requestNonce)
        self.policyId = try normalizedAnchorField("policyId", policyId)
        self.policyHash = policyHash
        try validate()
    }

    public init(payload: MeshRequestAnchorPayload) throws {
        try payload.validate()
        try self.init(
            signedMCPRequestHash: payload.metadata.signedRequestHash,
            requestNonce: payload.requestNonce,
            policyId: payload.policyId,
            policyHash: payload.policyHash
        )
    }

    public init(submission: MeshRequestAnchorSubmission) throws {
        try submission.validate()
        try self.init(payload: submission.payload)
    }

    public init(submitInput: MeshRequestAnchorSubmitInput) throws {
        try submitInput.validate()
        try self.init(
            signedMCPRequestHash: submitInput.signedMCPRequestHash,
            requestNonce: submitInput.requestNonce,
            policyId: submitInput.policyId,
            policyHash: submitInput.policyHash
        )
        try validate(boundTo: submitInput.payload)
    }

    public init(providerInput: MeshRequestAnchorProviderInput) throws {
        try providerInput.validate()
        try self.init(payload: providerInput.payload)
    }

    public init(executionRequest: MeshAgentWalletExecutionRequest) throws {
        try executionRequest.validate()
        try self.init(
            signedMCPRequestHash: executionRequest.requestAnchorMetadata.signedRequestHash,
            requestNonce: executionRequest.requestAnchorMetadata.nonce,
            policyId: executionRequest.policyId,
            policyHash: executionRequest.policyHash
        )
    }

    public init(paymentRequest: MeshPaymentExecutionRequest) throws {
        try paymentRequest.validate()
        try self.init(executionRequest: paymentRequest.executionRequest)
        guard signedMCPRequestHash == paymentRequest.requestHash else {
            throw MeshKitValidationError.signatureMismatch("signed MCP request anchoring fields payment request hash mismatch")
        }
        if let payload = paymentRequest.requestAnchor.payload {
            try validate(boundTo: payload)
        }
    }

    public func validate() throws {
        try validateHash("signedMCPRequestHash", signedMCPRequestHash)
        try validateAnchorIdentifierFormat("requestNonce", requestNonce)
        try validateAnchorIdentifierFormat("policyId", policyId)
        try validateHash("policyHash", policyHash)
    }

    public func validate(boundTo payload: MeshRequestAnchorPayload) throws {
        try validate()
        let payloadFields = try MeshSignedMCPRequestAnchoringFields(payload: payload)
        guard self == payloadFields else {
            throw MeshKitValidationError.signatureMismatch("signed MCP request anchoring fields payload linkage mismatch")
        }
    }
}

public extension MeshRequestAnchorPayload {
    func signedMCPRequestAnchoringFields() throws -> MeshSignedMCPRequestAnchoringFields {
        try MeshSignedMCPRequestAnchoringFields(payload: self)
    }
}

public extension MeshRequestAnchorSubmission {
    func signedMCPRequestAnchoringFields() throws -> MeshSignedMCPRequestAnchoringFields {
        try MeshSignedMCPRequestAnchoringFields(submission: self)
    }
}

public extension MeshRequestAnchorSubmitInput {
    func signedMCPRequestAnchoringFields() throws -> MeshSignedMCPRequestAnchoringFields {
        try MeshSignedMCPRequestAnchoringFields(submitInput: self)
    }
}

public extension MeshRequestAnchorProviderInput {
    func signedMCPRequestAnchoringFields() throws -> MeshSignedMCPRequestAnchoringFields {
        try MeshSignedMCPRequestAnchoringFields(providerInput: self)
    }
}

public enum MeshRequestAnchorPolicyBinding {
    public static func validate(
        payload: MeshRequestAnchorPayload,
        boundPolicy policy: MeshAgentWalletDelegatedSpendingPolicy
    ) throws {
        try payload.validate()
        try policy.validate()
        guard payload.policyId == policy.policyId else {
            throw MeshKitValidationError.signatureMismatch("request anchor policy id mismatch")
        }
        guard payload.policyHash == policy.policyHash else {
            throw MeshKitValidationError.signatureMismatch("request anchor policy hash mismatch")
        }
    }
}

public struct MeshRequestAnchorSubmitInput: Codable, Equatable, Sendable {
    public static let version = "meshkit-request-anchor-submit-input/v1"

    public let version: String
    public let providerMetadata: MeshChainProviderMetadata
    public let payload: MeshRequestAnchorPayload
    public let signedMCPRequestHash: MeshPayloadHash
    public let requestNonce: String
    public let policyId: String
    public let policyHash: MeshPayloadHash
    public let submittedAt: String

    public init(
        payload: MeshRequestAnchorPayload,
        providerIdentity: MeshChainProviderIdentity,
        submittedAt: String,
        version: String = MeshRequestAnchorSubmitInput.version
    ) throws {
        try self.init(
            payload: payload,
            signedMCPRequestHash: payload.metadata.signedRequestHash,
            requestNonce: payload.metadata.nonce,
            policyId: payload.policyId,
            policyHash: payload.policyHash,
            providerIdentity: providerIdentity,
            submittedAt: submittedAt,
            version: version
        )
    }

    public init(
        payload: MeshRequestAnchorPayload,
        anchoringFields: MeshSignedMCPRequestAnchoringFields,
        providerIdentity: MeshChainProviderIdentity,
        submittedAt: String,
        version: String = MeshRequestAnchorSubmitInput.version
    ) throws {
        try anchoringFields.validate(boundTo: payload)
        try self.init(
            payload: payload,
            signedMCPRequestHash: anchoringFields.signedMCPRequestHash,
            requestNonce: anchoringFields.requestNonce,
            policyId: anchoringFields.policyId,
            policyHash: anchoringFields.policyHash,
            providerIdentity: providerIdentity,
            submittedAt: submittedAt,
            version: version
        )
    }

    public init(
        payload: MeshRequestAnchorPayload,
        signedMCPRequestHash: MeshPayloadHash,
        requestNonce: String,
        policyId: String,
        policyHash: MeshPayloadHash,
        providerIdentity: MeshChainProviderIdentity,
        submittedAt: String,
        version: String = MeshRequestAnchorSubmitInput.version
    ) throws {
        self.version = try normalizedAnchorField("version", version)
        self.providerMetadata = providerIdentity.metadata
        self.payload = payload
        self.signedMCPRequestHash = signedMCPRequestHash
        self.requestNonce = try normalizedAnchorField("requestNonce", requestNonce)
        self.policyId = try normalizedAnchorField("policyId", policyId)
        self.policyHash = policyHash
        self.submittedAt = try normalizedAnchorField("submittedAt", submittedAt)
        try validate(providerIdentity: providerIdentity)
    }

    public init(
        request: MeshRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        providerIdentity: MeshChainProviderIdentity,
        submittedAt: String,
        version: String = MeshRequestAnchorSubmitInput.version
    ) throws {
        let payload = try MeshRequestAnchorPayload(
            metadata: MeshSignedRequestAnchorMetadata(request: request),
            policyId: policy.policyId,
            policyHash: policy.policyHash
        )
        try MeshRequestAnchorPolicyBinding.validate(payload: payload, boundPolicy: policy)
        try self.init(
            payload: payload,
            providerIdentity: providerIdentity,
            submittedAt: submittedAt,
            version: version
        )
        try MeshRequestAnchorCanonicalization.validate(metadata: payload.metadata, boundTo: request)
    }

    public func validate() throws {
        guard version == Self.version else {
            throw MeshKitValidationError.invalidChainProviderIdentity("version")
        }
        try providerMetadata.validate()
        try payload.validate()
        try validateHash("signedMCPRequestHash", signedMCPRequestHash)
        try validateAnchorIdentifierFormat("requestNonce", requestNonce)
        try validateAnchorIdentifierFormat("policyId", policyId)
        try validateHash("policyHash", policyHash)
        try requireAnchorField("submittedAt", submittedAt)
        guard signedMCPRequestHash == payload.metadata.signedRequestHash,
              requestNonce == payload.metadata.nonce else {
            throw MeshKitValidationError.signatureMismatch("request anchor submit input request linkage mismatch")
        }
        guard policyId == payload.policyId,
              policyHash == payload.policyHash else {
            throw MeshKitValidationError.signatureMismatch("request anchor submit input policy linkage mismatch")
        }
    }

    public func validate(providerIdentity: MeshChainProviderIdentity) throws {
        try validate()
        try providerIdentity.validate()
        guard providerMetadata == providerIdentity.metadata else {
            throw MeshKitValidationError.signatureMismatch("request anchor provider metadata mismatch")
        }
    }
}

public struct MeshRequestAnchorReferenceCreationInput: Codable, Equatable, Sendable {
    public static let version = "meshkit-request-anchor-reference-creation-input/v1"

    public let version: String
    public let providerMetadata: MeshChainProviderMetadata
    public let metadata: MeshSignedRequestAnchorMetadata
    public let requestHash: MeshPayloadHash
    public let requestNonce: String
    public let policyId: String?
    public let policyHash: MeshPayloadHash?
    public let status: MeshRequestAnchorStatus
    public let canonicalString: String

    public init(
        metadata: MeshSignedRequestAnchorMetadata,
        providerIdentity: MeshChainProviderIdentity,
        policyId: String? = nil,
        policyHash: MeshPayloadHash? = nil,
        status: MeshRequestAnchorStatus = .submitted,
        version: String = MeshRequestAnchorReferenceCreationInput.version
    ) throws {
        self.version = try normalizedAnchorField("version", version)
        self.providerMetadata = providerIdentity.metadata
        self.metadata = metadata
        self.requestHash = MeshPayloadHash(
            algorithm: metadata.signedRequestHash.algorithm.lowercased(),
            value: metadata.signedRequestHash.value.lowercased()
        )
        self.requestNonce = try normalizedAnchorField("requestNonce", metadata.nonce)
        self.policyId = try policyId.map { try normalizedAnchorField("policyId", $0) }
        self.policyHash = policyHash
        self.status = status
        self.canonicalString = try Self.makeCanonicalString(
            version: self.version,
            providerMetadata: self.providerMetadata,
            metadata: metadata,
            requestHash: self.requestHash,
            requestNonce: self.requestNonce,
            policyId: self.policyId,
            policyHash: self.policyHash,
            status: self.status
        )
        try validate(providerIdentity: providerIdentity)
    }

    public init(
        request: MeshRequest,
        providerIdentity: MeshChainProviderIdentity,
        policyId: String? = nil,
        policyHash: MeshPayloadHash? = nil,
        status: MeshRequestAnchorStatus = .submitted,
        version: String = MeshRequestAnchorReferenceCreationInput.version
    ) throws {
        try self.init(
            metadata: MeshSignedRequestAnchorMetadata(request: request),
            providerIdentity: providerIdentity,
            policyId: policyId,
            policyHash: policyHash,
            status: status,
            version: version
        )
        try MeshRequestAnchorCanonicalization.validate(metadata: metadata, boundTo: request)
    }

    public init(
        payload: MeshRequestAnchorPayload,
        providerIdentity: MeshChainProviderIdentity,
        status: MeshRequestAnchorStatus = .submitted,
        version: String = MeshRequestAnchorReferenceCreationInput.version
    ) throws {
        try self.init(
            metadata: payload.metadata,
            providerIdentity: providerIdentity,
            policyId: payload.policyId,
            policyHash: payload.policyHash,
            status: status,
            version: version
        )
        try payload.validate()
    }

    public init(
        request: MeshRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        providerIdentity: MeshChainProviderIdentity,
        status: MeshRequestAnchorStatus = .submitted,
        version: String = MeshRequestAnchorReferenceCreationInput.version
    ) throws {
        let payload = try MeshRequestAnchorPayload(
            metadata: MeshSignedRequestAnchorMetadata(request: request),
            policyId: policy.policyId,
            policyHash: policy.policyHash
        )
        try MeshRequestAnchorPolicyBinding.validate(payload: payload, boundPolicy: policy)
        try self.init(
            payload: payload,
            providerIdentity: providerIdentity,
            status: status,
            version: version
        )
        try MeshRequestAnchorCanonicalization.validate(metadata: payload.metadata, boundTo: request)
    }

    public func validate(providerIdentity: MeshChainProviderIdentity) throws {
        try validate()
        try providerIdentity.validate()
        guard providerMetadata == providerIdentity.metadata else {
            throw MeshKitValidationError.signatureMismatch("request anchor reference provider metadata mismatch")
        }
    }

    public func validate() throws {
        guard version == Self.version else {
            throw MeshKitValidationError.invalidChainProviderIdentity("version")
        }
        try providerMetadata.validate()
        try metadata.validate()
        try validateHash("requestHash", requestHash)
        try validateAnchorIdentifierFormat("requestNonce", requestNonce)
        if let policyId {
            try validateAnchorIdentifierFormat("policyId", policyId)
        }
        if let policyHash {
            try validateHash("policyHash", policyHash)
        }
        guard (policyId == nil) == (policyHash == nil) else {
            throw MeshKitValidationError.signatureMismatch("request anchor reference policy linkage mismatch")
        }
        guard requestHash == MeshPayloadHash(
            algorithm: metadata.signedRequestHash.algorithm.lowercased(),
            value: metadata.signedRequestHash.value.lowercased()
        ), requestNonce == metadata.nonce else {
            throw MeshKitValidationError.signatureMismatch("request anchor reference metadata linkage mismatch")
        }
        let expectedCanonicalString = try Self.makeCanonicalString(
            version: version,
            providerMetadata: providerMetadata,
            metadata: metadata,
            requestHash: requestHash,
            requestNonce: requestNonce,
            policyId: policyId,
            policyHash: policyHash,
            status: status
        )
        guard canonicalString == expectedCanonicalString else {
            throw MeshKitValidationError.signatureMismatch("request anchor reference canonical input mismatch")
        }
    }

    private static func makeCanonicalString(
        version: String,
        providerMetadata: MeshChainProviderMetadata,
        metadata: MeshSignedRequestAnchorMetadata,
        requestHash: MeshPayloadHash,
        requestNonce: String,
        policyId: String?,
        policyHash: MeshPayloadHash?,
        status: MeshRequestAnchorStatus
    ) throws -> String {
        try providerMetadata.validate()
        try metadata.validate()
        try validateHash("requestHash", requestHash)
        try validateAnchorIdentifierFormat("requestNonce", requestNonce)
        if let policyId {
            try validateAnchorIdentifierFormat("policyId", policyId)
        }
        if let policyHash {
            try validateHash("policyHash", policyHash)
        }
        guard (policyId == nil) == (policyHash == nil) else {
            throw MeshKitValidationError.signatureMismatch("request anchor reference policy linkage mismatch")
        }

        return [
            version,
            "provider=\(providerMetadata.provider)",
            "network=\(providerMetadata.network)",
            "chainId=\(providerMetadata.chainId)",
            "requestId=\(metadata.requestId)",
            "requestNonce=\(requestNonce)",
            "timestamp=\(metadata.timestamp)",
            "callerAppId=\(metadata.callerAppId)",
            "callerBundleId=\(metadata.callerBundleId)",
            "targetBundleId=\(metadata.targetBundleId)",
            "capabilityId=\(metadata.capabilityId)",
            "payloadHashAlgorithm=\(metadata.payloadHash.algorithm.lowercased())",
            "payloadHashValue=\(metadata.payloadHash.value.lowercased())",
            "signatureAlgorithm=\(metadata.signature.algorithm)",
            "signatureKeyId=\(metadata.signature.keyId)",
            "signedRequestHashAlgorithm=\(requestHash.algorithm.lowercased())",
            "signedRequestHashValue=\(requestHash.value.lowercased())",
            "policyId=\(policyId ?? "")",
            "policyHashAlgorithm=\(policyHash?.algorithm.lowercased() ?? "")",
            "policyHashValue=\(policyHash?.value.lowercased() ?? "")",
            "status=\(status.rawValue)"
        ].joined(separator: "\n")
    }
}

public struct MeshRequestAnchorReferenceCreationOutput: Codable, Equatable, Sendable {
    public static let version = "meshkit-request-anchor-reference-creation-output/v1"

    public let version: String
    public let anchoringReference: MeshRequestAnchorIdentifier
    public let requestHash: MeshPayloadHash
    public let requestNonce: String
    public let providerMetadata: MeshChainProviderMetadata
    public let policyId: String?
    public let policyHash: MeshPayloadHash?
    public let status: MeshRequestAnchorStatus
    public let canonicalString: String

    public init(
        anchoringReference: MeshRequestAnchorIdentifier,
        requestHash: MeshPayloadHash,
        requestNonce: String,
        providerMetadata: MeshChainProviderMetadata,
        policyId: String? = nil,
        policyHash: MeshPayloadHash? = nil,
        status: MeshRequestAnchorStatus = .submitted,
        version: String = MeshRequestAnchorReferenceCreationOutput.version
    ) throws {
        self.version = try normalizedAnchorField("version", version)
        self.anchoringReference = anchoringReference
        self.requestHash = requestHash
        self.requestNonce = try normalizedAnchorField("requestNonce", requestNonce)
        self.providerMetadata = providerMetadata
        self.policyId = try policyId.map { try normalizedAnchorField("policyId", $0) }
        self.policyHash = policyHash
        self.status = status
        self.canonicalString = try Self.makeCanonicalString(
            version: self.version,
            anchoringReference: anchoringReference,
            requestHash: requestHash,
            requestNonce: self.requestNonce,
            providerMetadata: providerMetadata,
            policyId: self.policyId,
            policyHash: self.policyHash,
            status: self.status
        )
        try validate()
    }

    public func validate() throws {
        guard version == Self.version else {
            throw MeshKitValidationError.invalidChainProviderIdentity("version")
        }
        try anchoringReference.validate()
        try validateHash("requestHash", requestHash)
        try validateAnchorIdentifierFormat("requestNonce", requestNonce)
        try providerMetadata.validate()
        if let policyId {
            try validateAnchorIdentifierFormat("policyId", policyId)
        }
        if let policyHash {
            try validateHash("policyHash", policyHash)
        }
        guard (policyId == nil) == (policyHash == nil) else {
            throw MeshKitValidationError.signatureMismatch("request anchor reference output policy linkage mismatch")
        }
        guard anchoringReference.identity.metadata == providerMetadata else {
            throw MeshKitValidationError.signatureMismatch("request anchor reference output provider metadata mismatch")
        }
        guard anchoringReference.anchorId == (try MeshRequestAnchorCanonicalization.anchoringReferenceId(
            forSignedRequestHash: requestHash
        )) else {
            throw MeshKitValidationError.signatureMismatch("request anchor reference output hash mismatch")
        }
        let expectedCanonicalString = try Self.makeCanonicalString(
            version: version,
            anchoringReference: anchoringReference,
            requestHash: requestHash,
            requestNonce: requestNonce,
            providerMetadata: providerMetadata,
            policyId: policyId,
            policyHash: policyHash,
            status: status
        )
        guard canonicalString == expectedCanonicalString else {
            throw MeshKitValidationError.signatureMismatch("request anchor reference output canonical linkage mismatch")
        }
    }

    private static func makeCanonicalString(
        version: String,
        anchoringReference: MeshRequestAnchorIdentifier,
        requestHash: MeshPayloadHash,
        requestNonce: String,
        providerMetadata: MeshChainProviderMetadata,
        policyId: String?,
        policyHash: MeshPayloadHash?,
        status: MeshRequestAnchorStatus
    ) throws -> String {
        try anchoringReference.validate()
        try validateHash("requestHash", requestHash)
        try validateAnchorIdentifierFormat("requestNonce", requestNonce)
        try providerMetadata.validate()
        if let policyId {
            try validateAnchorIdentifierFormat("policyId", policyId)
        }
        if let policyHash {
            try validateHash("policyHash", policyHash)
        }
        guard (policyId == nil) == (policyHash == nil) else {
            throw MeshKitValidationError.signatureMismatch("request anchor reference output policy linkage mismatch")
        }

        return [
            version,
            "provider=\(providerMetadata.provider)",
            "network=\(providerMetadata.network)",
            "chainId=\(providerMetadata.chainId)",
            "anchorId=\(anchoringReference.anchorId)",
            "anchorTransactionHash=\(anchoringReference.transactionHash ?? "")",
            "requestNonce=\(requestNonce)",
            "requestHashAlgorithm=\(requestHash.algorithm.lowercased())",
            "requestHashValue=\(requestHash.value.lowercased())",
            "policyId=\(policyId ?? "")",
            "policyHashAlgorithm=\(policyHash?.algorithm.lowercased() ?? "")",
            "policyHashValue=\(policyHash?.value.lowercased() ?? "")",
            "status=\(status.rawValue)"
        ].joined(separator: "\n")
    }
}

public struct MeshRequestAnchorReferenceCreationModule: Sendable {
    public let configuration: MeshChainProviderConfiguration

    public init(configuration: MeshChainProviderConfiguration) {
        self.configuration = configuration
    }

    public init(provider: any MeshRequestAnchorProvider) throws {
        self.configuration = try MeshChainProviderConfiguration(
            identity: provider.identity,
            capabilities: provider.capabilities
        )
    }

    public func createReference(
        _ input: MeshRequestAnchorReferenceCreationInput
    ) throws -> MeshRequestAnchorReferenceCreationOutput {
        try configuration.require(.createRequestAnchorReference)
        try input.validate(providerIdentity: configuration.identity)
        let reference = try MeshRequestAnchorCanonicalization.anchoringReference(
            for: input.metadata,
            providerIdentity: configuration.identity
        )
        return try MeshRequestAnchorReferenceCreationOutput(
            anchoringReference: reference,
            requestHash: input.requestHash,
            requestNonce: input.requestNonce,
            providerMetadata: input.providerMetadata,
            policyId: input.policyId,
            policyHash: input.policyHash,
            status: input.status
        )
    }

    public func createReference(
        metadata: MeshSignedRequestAnchorMetadata
    ) throws -> MeshRequestAnchorReferenceCreationOutput {
        let input = try MeshRequestAnchorReferenceCreationInput(
            metadata: metadata,
            providerIdentity: configuration.identity
        )
        return try createReference(input)
    }

    public func createReference(
        request: MeshRequest
    ) throws -> MeshRequestAnchorReferenceCreationOutput {
        let input = try MeshRequestAnchorReferenceCreationInput(
            request: request,
            providerIdentity: configuration.identity
        )
        return try createReference(input)
    }

    public func createReference(
        payload: MeshRequestAnchorPayload,
        status: MeshRequestAnchorStatus = .submitted
    ) throws -> MeshRequestAnchorReferenceCreationOutput {
        let input = try MeshRequestAnchorReferenceCreationInput(
            payload: payload,
            providerIdentity: configuration.identity,
            status: status
        )
        return try createReference(input)
    }

    public func createReference(
        request: MeshRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        status: MeshRequestAnchorStatus = .submitted
    ) throws -> MeshRequestAnchorReferenceCreationOutput {
        let input = try MeshRequestAnchorReferenceCreationInput(
            request: request,
            policy: policy,
            providerIdentity: configuration.identity,
            status: status
        )
        return try createReference(input)
    }
}

public struct MeshRequestAnchorReferenceSigningInput: Codable, Equatable, Sendable {
    public static let version = "meshkit-request-anchor-reference-signing-input/v1"

    public let version: String
    public let anchoringReference: MeshRequestAnchorIdentifier
    public let requestHash: MeshPayloadHash
    public let requestNonce: String
    public let providerMetadata: MeshChainProviderMetadata
    public let policyId: String?
    public let policyHash: MeshPayloadHash?
    public let status: MeshRequestAnchorStatus
    public let canonicalString: String

    public init(
        anchoringReference: MeshRequestAnchorIdentifier,
        requestHash: MeshPayloadHash,
        requestNonce: String,
        providerMetadata: MeshChainProviderMetadata,
        policyId: String? = nil,
        policyHash: MeshPayloadHash? = nil,
        status: MeshRequestAnchorStatus = .submitted,
        version: String = MeshRequestAnchorReferenceSigningInput.version
    ) throws {
        self.version = try normalizedAnchorField("version", version)
        self.anchoringReference = anchoringReference
        self.requestHash = requestHash
        self.requestNonce = try normalizedAnchorField("requestNonce", requestNonce)
        self.providerMetadata = providerMetadata
        self.policyId = try policyId.map { try normalizedAnchorField("policyId", $0) }
        self.policyHash = policyHash
        self.status = status
        self.canonicalString = try Self.makeCanonicalString(
            version: self.version,
            anchoringReference: anchoringReference,
            requestHash: requestHash,
            requestNonce: self.requestNonce,
            providerMetadata: providerMetadata,
            policyId: self.policyId,
            policyHash: self.policyHash,
            status: self.status
        )
        try validate()
    }

    public init(referenceOutput: MeshRequestAnchorReferenceCreationOutput) throws {
        try self.init(
            anchoringReference: referenceOutput.anchoringReference,
            requestHash: referenceOutput.requestHash,
            requestNonce: referenceOutput.requestNonce,
            providerMetadata: referenceOutput.providerMetadata,
            policyId: referenceOutput.policyId,
            policyHash: referenceOutput.policyHash,
            status: referenceOutput.status
        )
    }

    public var data: Data {
        Data(canonicalString.utf8)
    }

    public func validate() throws {
        guard version == Self.version else {
            throw MeshKitValidationError.invalidChainProviderIdentity("version")
        }
        try anchoringReference.validate()
        try validateHash("requestHash", requestHash)
        try validateAnchorIdentifierFormat("requestNonce", requestNonce)
        try providerMetadata.validate()
        if let policyId {
            try validateAnchorIdentifierFormat("policyId", policyId)
        }
        if let policyHash {
            try validateHash("policyHash", policyHash)
        }
        guard (policyId == nil) == (policyHash == nil) else {
            throw MeshKitValidationError.signatureMismatch("request anchor reference signing policy linkage mismatch")
        }
        guard anchoringReference.identity.metadata == providerMetadata else {
            throw MeshKitValidationError.signatureMismatch("request anchor reference signing provider metadata mismatch")
        }
        guard anchoringReference.anchorId == (try MeshRequestAnchorCanonicalization.anchoringReferenceId(
            forSignedRequestHash: requestHash
        )) else {
            throw MeshKitValidationError.signatureMismatch("request anchor reference signing hash mismatch")
        }
        let expectedCanonicalString = try Self.makeCanonicalString(
            version: version,
            anchoringReference: anchoringReference,
            requestHash: requestHash,
            requestNonce: requestNonce,
            providerMetadata: providerMetadata,
            policyId: policyId,
            policyHash: policyHash,
            status: status
        )
        guard canonicalString == expectedCanonicalString else {
            throw MeshKitValidationError.signatureMismatch("request anchor reference signing canonical input mismatch")
        }
    }

    private static func makeCanonicalString(
        version: String,
        anchoringReference: MeshRequestAnchorIdentifier,
        requestHash: MeshPayloadHash,
        requestNonce: String,
        providerMetadata: MeshChainProviderMetadata,
        policyId: String?,
        policyHash: MeshPayloadHash?,
        status: MeshRequestAnchorStatus
    ) throws -> String {
        try anchoringReference.validate()
        try validateHash("requestHash", requestHash)
        try validateAnchorIdentifierFormat("requestNonce", requestNonce)
        try providerMetadata.validate()
        if let policyId {
            try validateAnchorIdentifierFormat("policyId", policyId)
        }
        if let policyHash {
            try validateHash("policyHash", policyHash)
        }
        guard (policyId == nil) == (policyHash == nil) else {
            throw MeshKitValidationError.signatureMismatch("request anchor reference signing policy linkage mismatch")
        }

        return [
            version,
            "provider=\(providerMetadata.provider)",
            "network=\(providerMetadata.network)",
            "chainId=\(providerMetadata.chainId)",
            "anchorId=\(anchoringReference.anchorId)",
            "anchorTransactionHash=\(anchoringReference.transactionHash ?? "")",
            "requestNonce=\(requestNonce)",
            "requestHashAlgorithm=\(requestHash.algorithm.lowercased())",
            "requestHashValue=\(requestHash.value.lowercased())",
            "policyId=\(policyId ?? "")",
            "policyHashAlgorithm=\(policyHash?.algorithm.lowercased() ?? "")",
            "policyHashValue=\(policyHash?.value.lowercased() ?? "")",
            "status=\(status.rawValue)"
        ].joined(separator: "\n")
    }
}

public struct MeshSignedRequestAnchorReference: Codable, Equatable, Sendable {
    public static let version = "meshkit-signed-request-anchor-reference/v1"

    public let version: String
    public let input: MeshRequestAnchorReferenceSigningInput
    public let signature: MeshSignature

    public init(
        input: MeshRequestAnchorReferenceSigningInput,
        signature: MeshSignature,
        version: String = MeshSignedRequestAnchorReference.version
    ) throws {
        self.version = try normalizedAnchorField("version", version)
        self.input = input
        self.signature = signature
        try validate()
    }

    public var anchoringReference: MeshRequestAnchorIdentifier { input.anchoringReference }
    public var requestHash: MeshPayloadHash { input.requestHash }
    public var requestNonce: String { input.requestNonce }
    public var providerMetadata: MeshChainProviderMetadata { input.providerMetadata }
    public var policyId: String? { input.policyId }
    public var policyHash: MeshPayloadHash? { input.policyHash }
    public var status: MeshRequestAnchorStatus { input.status }
    public var canonicalString: String { input.canonicalString }

    public func validate() throws {
        guard version == Self.version else {
            throw MeshKitValidationError.invalidChainProviderIdentity("version")
        }
        try input.validate()
        try requireAnchorField("signature.algorithm", signature.algorithm)
        try requireAnchorField("signature.keyId", signature.keyId)
        try requireAnchorField("signature.value", signature.value)
    }
}

public struct MeshRequestAnchorReferenceSigningModule: Sendable {
    public let configuration: MeshChainProviderConfiguration
    public let signer: MeshRequestSigner

    public init(configuration: MeshChainProviderConfiguration, signer: MeshRequestSigner) {
        self.configuration = configuration
        self.signer = signer
    }

    public func signReference(
        _ input: MeshRequestAnchorReferenceSigningInput
    ) throws -> MeshSignedRequestAnchorReference {
        try configuration.require(.signRequestAnchorReference)
        try input.validate()
        guard input.providerMetadata == configuration.identity.metadata else {
            throw MeshKitValidationError.signatureMismatch("request anchor reference signing provider metadata mismatch")
        }
        let signature = try signer.signature(for: input.data)
        return try MeshSignedRequestAnchorReference(input: input, signature: signature)
    }

    public func signReference(
        _ output: MeshRequestAnchorReferenceCreationOutput
    ) throws -> MeshSignedRequestAnchorReference {
        try signReference(MeshRequestAnchorReferenceSigningInput(referenceOutput: output))
    }
}

public struct MeshRequestAnchorSubmission: Codable, Equatable, Sendable {
    public static let version = "meshkit-request-anchor-submission/v1"

    public let version: String
    public let providerMetadata: MeshChainProviderMetadata
    public let payload: MeshRequestAnchorPayload
    public let submittedAt: String

    public init(
        payload: MeshRequestAnchorPayload,
        providerIdentity: MeshChainProviderIdentity,
        submittedAt: String,
        version: String = MeshRequestAnchorSubmission.version
    ) throws {
        self.version = try normalizedAnchorField("version", version)
        self.providerMetadata = providerIdentity.metadata
        self.payload = payload
        self.submittedAt = try normalizedAnchorField("submittedAt", submittedAt)
        try validate(providerIdentity: providerIdentity)
    }

    public init(
        request: MeshRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        providerIdentity: MeshChainProviderIdentity,
        submittedAt: String,
        version: String = MeshRequestAnchorSubmission.version
    ) throws {
        let metadata = try MeshSignedRequestAnchorMetadata(request: request)
        let payload = try MeshRequestAnchorPayload(
            metadata: metadata,
            policyId: policy.policyId,
            policyHash: policy.policyHash
        )
        try MeshRequestAnchorPolicyBinding.validate(payload: payload, boundPolicy: policy)
        try self.init(
            payload: payload,
            providerIdentity: providerIdentity,
            submittedAt: submittedAt,
            version: version
        )
        try validate(boundTo: request, policy: policy, providerIdentity: providerIdentity)
    }

    public func validate() throws {
        guard version == Self.version else {
            throw MeshKitValidationError.invalidChainProviderIdentity("version")
        }
        try providerMetadata.validate()
        try payload.validate()
        try requireAnchorField("submittedAt", submittedAt)
    }

    public func validate(providerIdentity: MeshChainProviderIdentity) throws {
        try validate()
        try providerIdentity.validate()
        guard providerMetadata == providerIdentity.metadata else {
            throw MeshKitValidationError.signatureMismatch("request anchor provider metadata mismatch")
        }
    }

    public func validate(
        boundTo request: MeshRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        providerIdentity: MeshChainProviderIdentity
    ) throws {
        try validate(providerIdentity: providerIdentity)
        try MeshRequestAnchorCanonicalization.validate(metadata: payload.metadata, boundTo: request)
        try MeshRequestAnchorPolicyBinding.validate(payload: payload, boundPolicy: policy)
    }
}

public struct MeshRequestAnchorProviderCapabilityMetadata: Codable, Equatable, Sendable {
    public static let version = "meshkit-request-anchor-provider-capability-metadata/v1"
    public static let requiredAnchoringCapabilities: [MeshChainProviderCapability] = [
        .anchorSignedRequest,
        .constructExplorerURL,
        .loadProviderConfiguration
    ]

    public let version: String
    public let adapterId: String
    public let providerMetadata: MeshChainProviderMetadata
    public let endpointConfiguration: MeshChainProviderEndpointConfiguration
    public let capabilities: [MeshChainProviderCapability]
    public let requiredAnchoringCapabilities: [MeshChainProviderCapability]
    public let providerInputVersion: String

    public init(
        adapterId: String,
        providerIdentity: MeshChainProviderIdentity,
        capabilities: [MeshChainProviderCapability],
        requiredAnchoringCapabilities: [MeshChainProviderCapability] = Self.requiredAnchoringCapabilities,
        providerInputVersion: String = MeshRequestAnchorProviderInput.version,
        version: String = MeshRequestAnchorProviderCapabilityMetadata.version
    ) throws {
        self.version = try normalizedAnchorField("version", version)
        self.adapterId = try normalizedAnchorField("adapterId", adapterId)
        self.providerMetadata = providerIdentity.metadata
        self.endpointConfiguration = providerIdentity.endpointConfiguration
        self.capabilities = Array(Set(capabilities)).sorted()
        self.requiredAnchoringCapabilities = Array(Set(requiredAnchoringCapabilities)).sorted()
        self.providerInputVersion = try normalizedAnchorField("providerInputVersion", providerInputVersion)
        try validate()
    }

    public func supports(_ capability: MeshChainProviderCapability) -> Bool {
        capabilities.contains(capability)
    }

    public func validate() throws {
        guard version == Self.version else {
            throw MeshKitValidationError.invalidChainProviderIdentity("version")
        }
        try requireAnchorField("adapterId", adapterId)
        try providerMetadata.validate()
        try endpointConfiguration.validate()
        guard !capabilities.isEmpty else { throw MeshKitValidationError.unsupportedCapability }
        guard providerInputVersion == MeshRequestAnchorProviderInput.version else {
            throw MeshKitValidationError.invalidChainProviderIdentity("providerInputVersion")
        }
        for capability in requiredAnchoringCapabilities {
            guard capabilities.contains(capability) else {
                throw MeshKitValidationError.unsupportedCapability
            }
        }
    }
}

public struct MeshRequestAnchorProviderInput: Codable, Equatable, Sendable {
    public static let version = "meshkit-request-anchor-provider-input/v1"

    public let version: String
    public let providerMetadata: MeshChainProviderMetadata
    public let endpointConfiguration: MeshChainProviderEndpointConfiguration
    public let payload: MeshRequestAnchorPayload
    public let submittedAt: String
    public let canonicalString: String

    public init(
        payload: MeshRequestAnchorPayload,
        providerIdentity: MeshChainProviderIdentity,
        submittedAt: String,
        version: String = MeshRequestAnchorProviderInput.version
    ) throws {
        self.version = try normalizedAnchorField("version", version)
        self.providerMetadata = providerIdentity.metadata
        self.endpointConfiguration = providerIdentity.endpointConfiguration
        self.payload = payload
        self.submittedAt = try normalizedAnchorField("submittedAt", submittedAt)
        self.canonicalString = try Self.makeCanonicalString(
            version: self.version,
            providerMetadata: self.providerMetadata,
            payload: payload,
            submittedAt: self.submittedAt
        )
        try validate(providerIdentity: providerIdentity)
    }

    public func validate(providerIdentity: MeshChainProviderIdentity) throws {
        try validate()
        try providerIdentity.validate()
        guard providerMetadata == providerIdentity.metadata else {
            throw MeshKitValidationError.signatureMismatch("request anchor provider metadata mismatch")
        }
        guard endpointConfiguration == providerIdentity.endpointConfiguration else {
            throw MeshKitValidationError.signatureMismatch("request anchor provider endpoint configuration mismatch")
        }
    }

    public func validate() throws {
        guard version == Self.version else {
            throw MeshKitValidationError.invalidChainProviderIdentity("version")
        }
        try providerMetadata.validate()
        try endpointConfiguration.validate()
        try payload.validate()
        try requireAnchorField("submittedAt", submittedAt)
        let expectedCanonicalString = try Self.makeCanonicalString(
            version: version,
            providerMetadata: providerMetadata,
            payload: payload,
            submittedAt: submittedAt
        )
        guard canonicalString == expectedCanonicalString else {
            throw MeshKitValidationError.signatureMismatch("request anchor provider canonical input mismatch")
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
        payload: MeshRequestAnchorPayload,
        submittedAt: String
    ) throws -> String {
        try providerMetadata.validate()
        try payload.validate()
        try requireAnchorField("submittedAt", submittedAt)

        return [
            version,
            "provider=\(providerMetadata.provider)",
            "network=\(providerMetadata.network)",
            "chainId=\(providerMetadata.chainId)",
            "requestId=\(payload.metadata.requestId)",
            "requestNonce=\(payload.metadata.nonce)",
            "signedRequestHashAlgorithm=\(payload.metadata.signedRequestHash.algorithm.lowercased())",
            "signedRequestHashValue=\(payload.metadata.signedRequestHash.value.lowercased())",
            "payloadHashAlgorithm=\(payload.metadata.payloadHash.algorithm.lowercased())",
            "payloadHashValue=\(payload.metadata.payloadHash.value.lowercased())",
            "signatureAlgorithm=\(payload.metadata.signature.algorithm)",
            "signatureKeyId=\(payload.metadata.signature.keyId)",
            "signatureValue=\(payload.metadata.signature.value)",
            "policyId=\(payload.policyId)",
            "policyHashAlgorithm=\(payload.policyHash.algorithm.lowercased())",
            "policyHashValue=\(payload.policyHash.value.lowercased())",
            "submittedAt=\(submittedAt)"
        ].joined(separator: "\n")
    }
}

public struct MeshMarooTestnetRequestAnchorSubmissionResponse: Codable, Equatable, Sendable {
    public static let version = "meshkit-maroo-request-anchor-response/v1"

    public let version: String
    public let providerMetadata: MeshChainProviderMetadata
    public let anchorId: String
    public let transactionHash: String?
    public let status: MeshRequestAnchorStatus
    public let observedAt: String?
    public let message: String?
    public let providerOutcome: MeshMarooTestnetRequestAnchorProviderOutcome?

    public var resultMapping: MeshMarooTestnetRequestAnchorResultMapping? {
        providerOutcome.map { MeshMarooTestnetRequestAnchorResultMapping(providerOutcome: $0) }
    }

    public init(
        providerMetadata: MeshChainProviderMetadata,
        anchorId: String,
        transactionHash: String? = nil,
        status: MeshRequestAnchorStatus,
        observedAt: String? = nil,
        message: String? = nil,
        providerOutcome: MeshMarooTestnetRequestAnchorProviderOutcome? = nil,
        version: String = MeshMarooTestnetRequestAnchorSubmissionResponse.version
    ) throws {
        self.version = try normalizedAnchorField("version", version)
        self.providerMetadata = providerMetadata
        self.anchorId = try normalizedAnchorField("anchorId", anchorId)
        self.transactionHash = try transactionHash.map { try normalizedAnchorField("transactionHash", $0) }
        self.status = status
        self.observedAt = try observedAt.map { try normalizedAnchorField("observedAt", $0) }
        self.message = try message.map { try normalizedAnchorField("message", $0) }
        self.providerOutcome = providerOutcome
        try validateResultMapping()
        try validate()
    }

    public init(
        providerMetadata: MeshChainProviderMetadata,
        anchorId: String,
        transactionHash: String? = nil,
        providerOutcome: String,
        observedAt: String? = nil,
        message: String? = nil,
        version: String = MeshMarooTestnetRequestAnchorSubmissionResponse.version
    ) throws {
        let mapping = try MeshMarooTestnetRequestAnchorResultMapping(providerOutcome: providerOutcome)
        try self.init(
            providerMetadata: providerMetadata,
            anchorId: anchorId,
            transactionHash: transactionHash,
            status: mapping.anchorStatus,
            observedAt: observedAt,
            message: message ?? mapping.defaultMessage,
            providerOutcome: mapping.providerOutcome,
            version: version
        )
    }

    public init(
        providerMetadata: MeshChainProviderMetadata,
        anchorId: String,
        transactionHash: String? = nil,
        providerAnchorState: String,
        observedAt: String? = nil,
        message: String? = nil,
        version: String = MeshMarooTestnetRequestAnchorSubmissionResponse.version
    ) throws {
        let mapping = try MeshMarooTestnetRequestAnchorStateMapping(providerAnchorState: providerAnchorState)
        try self.init(
            providerMetadata: providerMetadata,
            anchorId: anchorId,
            transactionHash: transactionHash,
            status: mapping.anchorStatus,
            observedAt: observedAt,
            message: message ?? mapping.defaultMessage,
            providerOutcome: mapping.providerOutcome,
            version: version
        )
    }

    public func validate() throws {
        guard version == Self.version else {
            throw MeshKitValidationError.invalidChainProviderIdentity("version")
        }
        try providerMetadata.validate()
        try requireAnchorField("anchorId", anchorId)
        if let transactionHash {
            try requireAnchorField("transactionHash", transactionHash)
        }
        if let observedAt {
            try requireAnchorField("observedAt", observedAt)
        }
        if let message {
            try requireAnchorField("message", message)
        }
        try validateResultMapping()
    }

    public func validate(
        providerIdentity: MeshChainProviderIdentity,
        submittedAt: String
    ) throws {
        try validate()
        try providerIdentity.validate()
        try requireAnchorField("submittedAt", submittedAt)
        guard providerMetadata == providerIdentity.metadata else {
            throw MeshKitValidationError.signatureMismatch("request anchor provider metadata mismatch")
        }
    }

    public func normalizedRequestAnchor(
        payload: MeshRequestAnchorPayload,
        identity: MeshChainProviderIdentity,
        submittedAt: String
    ) throws -> MeshRequestAnchor {
        try payload.validate()
        try validate(providerIdentity: identity, submittedAt: submittedAt)
        return try MeshRequestAnchor(
            metadata: payload.metadata,
            payload: payload,
            identifier: MeshRequestAnchorIdentifier(
                identity: identity,
                anchorId: anchorId,
                transactionHash: transactionHash
            ),
            status: status,
            submittedAt: submittedAt,
            observedAt: observedAt ?? submittedAt,
            message: message
        )
    }

    private func validateResultMapping() throws {
        guard let mapping = resultMapping else { return }
        guard mapping.anchorStatus == status else {
            throw MeshKitValidationError.invalidChainProviderIdentity("providerOutcome")
        }
        if mapping.providerOutcome == .success, transactionHash == nil {
            throw MeshKitValidationError.invalidChainProviderIdentity("transactionHash")
        }
        if mapping.providerOutcome == .policyDenied, transactionHash != nil {
            throw MeshKitValidationError.invalidChainProviderIdentity("transactionHash")
        }
    }
}

public protocol MeshMarooTestnetRequestAnchorSubmissionClient: Sendable {
    func submitRequestAnchor(
        _ input: MeshRequestAnchorProviderInput
    ) async throws -> MeshMarooTestnetRequestAnchorSubmissionResponse
}

public protocol MeshMarooTestnetRequestAnchorHTTPTransport: Sendable {
    func sendMarooRequestAnchor(
        _ request: URLRequest
    ) async throws -> (Data, HTTPURLResponse)
}

public struct MeshMarooTestnetURLSessionRequestAnchorHTTPTransport: MeshMarooTestnetRequestAnchorHTTPTransport {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func sendMarooRequestAnchor(
        _ request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, httpResponse)
    }
}

public struct MeshMarooTestnetRequestAnchorTransactionRequest: Codable, Equatable, Sendable {
    public static let version = "maroo-testnet-request-anchor/v1"
    public static let requestType = "meshkit_request_anchor"

    public let version: String
    public let requestType: String
    public let provider: String
    public let network: String
    public let chainId: String
    public let rpcEndpoint: URL
    public let explorerBaseURL: URL?
    public let anchorPayloadIdentity: String
    public let targetOwner: String
    public let delegatedSigner: String
    public let anchorHash: MeshPayloadHash
    public let requestId: String
    public let requestNonce: String
    public let signedMCPRequestHash: MeshPayloadHash
    public let signedMCPRequestSignature: MeshSignature
    public let policyId: String
    public let policyHash: MeshPayloadHash
    public let submittedAt: String

    private enum CodingKeys: String, CodingKey {
        case version = "schema_version"
        case requestType = "request_type"
        case provider
        case network
        case chainId = "chain_id"
        case rpcEndpoint = "rpc_endpoint"
        case explorerBaseURL = "explorer_base_url"
        case anchorPayloadIdentity = "anchor_payload_identity"
        case targetOwner = "target_owner"
        case delegatedSigner = "delegated_signer"
        case anchorHash = "anchor_hash"
        case requestId = "request_id"
        case requestNonce = "request_nonce"
        case signedMCPRequestHash = "signed_mcp_request_hash"
        case signedMCPRequestSignature = "signed_mcp_request_signature"
        case policyId = "policy_id"
        case policyHash = "policy_hash"
        case submittedAt = "submitted_at"
    }

    public init(
        providerMetadata: MeshChainProviderMetadata,
        endpointConfiguration: MeshChainProviderEndpointConfiguration,
        anchorPayloadIdentity: String,
        targetOwner: String,
        delegatedSigner: String,
        anchorHash: MeshPayloadHash,
        requestId: String,
        requestNonce: String,
        signedMCPRequestHash: MeshPayloadHash,
        signedMCPRequestSignature: MeshSignature,
        policyId: String,
        policyHash: MeshPayloadHash,
        submittedAt: String,
        version: String = MeshMarooTestnetRequestAnchorTransactionRequest.version,
        requestType: String = MeshMarooTestnetRequestAnchorTransactionRequest.requestType
    ) throws {
        self.version = try normalizedAnchorField("version", version)
        self.requestType = try normalizedAnchorField("requestType", requestType)
        self.provider = providerMetadata.provider
        self.network = providerMetadata.network
        self.chainId = providerMetadata.chainId
        self.rpcEndpoint = endpointConfiguration.rpcEndpoint
        self.explorerBaseURL = endpointConfiguration.explorerBaseURL
        self.anchorPayloadIdentity = try normalizedAnchorField("anchorPayloadIdentity", anchorPayloadIdentity)
        self.targetOwner = try normalizedAnchorField("targetOwner", targetOwner)
        self.delegatedSigner = try normalizedAnchorField("delegatedSigner", delegatedSigner)
        self.anchorHash = anchorHash
        self.requestId = try normalizedAnchorField("requestId", requestId)
        self.requestNonce = try normalizedAnchorField("requestNonce", requestNonce)
        self.signedMCPRequestHash = signedMCPRequestHash
        self.signedMCPRequestSignature = signedMCPRequestSignature
        self.policyId = try normalizedAnchorField("policyId", policyId)
        self.policyHash = policyHash
        self.submittedAt = try normalizedAnchorField("submittedAt", submittedAt)
        try validate(providerMetadata: providerMetadata, endpointConfiguration: endpointConfiguration)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(String.self, forKey: .version)
        self.requestType = try container.decode(String.self, forKey: .requestType)
        self.provider = try container.decode(String.self, forKey: .provider)
        self.network = try container.decode(String.self, forKey: .network)
        self.chainId = try container.decode(String.self, forKey: .chainId)
        self.rpcEndpoint = try container.decode(URL.self, forKey: .rpcEndpoint)
        self.explorerBaseURL = try container.decodeIfPresent(URL.self, forKey: .explorerBaseURL)
        self.anchorPayloadIdentity = try container.decode(String.self, forKey: .anchorPayloadIdentity)
        self.targetOwner = try container.decode(String.self, forKey: .targetOwner)
        self.delegatedSigner = try container.decode(String.self, forKey: .delegatedSigner)
        self.anchorHash = try container.decode(MeshPayloadHash.self, forKey: .anchorHash)
        self.requestId = try container.decode(String.self, forKey: .requestId)
        self.requestNonce = try container.decode(String.self, forKey: .requestNonce)
        self.signedMCPRequestHash = try container.decode(MeshPayloadHash.self, forKey: .signedMCPRequestHash)
        self.signedMCPRequestSignature = try container.decode(MeshSignature.self, forKey: .signedMCPRequestSignature)
        self.policyId = try container.decode(String.self, forKey: .policyId)
        self.policyHash = try container.decode(MeshPayloadHash.self, forKey: .policyHash)
        self.submittedAt = try container.decode(String.self, forKey: .submittedAt)
        try validate()
    }

    public func validate(
        providerMetadata expectedProviderMetadata: MeshChainProviderMetadata? = nil,
        endpointConfiguration expectedEndpointConfiguration: MeshChainProviderEndpointConfiguration? = nil
    ) throws {
        guard version == Self.version else {
            throw MeshKitValidationError.invalidChainProviderIdentity("version")
        }
        guard requestType == Self.requestType else {
            throw MeshKitValidationError.invalidChainProviderIdentity("requestType")
        }
        let providerMetadata = try MeshChainProviderMetadata(provider: provider, network: network, chainId: chainId)
        guard providerMetadata.provider == MeshMarooTestnetChainProvider.providerName,
              providerMetadata.network == MeshMarooTestnetChainProvider.networkIdentity,
              providerMetadata.chainId == MeshMarooTestnetChainProvider.chainId else {
            throw MeshKitValidationError.signatureMismatch("maroo request anchor provider metadata mismatch")
        }
        if let expectedProviderMetadata, providerMetadata != expectedProviderMetadata {
            throw MeshKitValidationError.signatureMismatch("maroo request anchor provider metadata mismatch")
        }
        let endpointConfiguration = try MeshChainProviderEndpointConfiguration(
            rpcEndpoint: rpcEndpoint,
            explorerBaseURL: explorerBaseURL
        )
        if let expectedEndpointConfiguration, endpointConfiguration != expectedEndpointConfiguration {
            throw MeshKitValidationError.signatureMismatch("maroo request anchor endpoint configuration mismatch")
        }
        try requireAnchorField("anchorPayloadIdentity", anchorPayloadIdentity)
        try requireAnchorField("targetOwner", targetOwner)
        try requireAnchorField("delegatedSigner", delegatedSigner)
        try validateHash("anchorHash", anchorHash)
        try requireAnchorField("requestId", requestId)
        try requireAnchorField("requestNonce", requestNonce)
        try validateHash("signedMCPRequestHash", signedMCPRequestHash)
        try requireAnchorField("signedMCPRequestSignature.algorithm", signedMCPRequestSignature.algorithm)
        try requireAnchorField("signedMCPRequestSignature.keyId", signedMCPRequestSignature.keyId)
        try requireAnchorField("signedMCPRequestSignature.value", signedMCPRequestSignature.value)
        try requireAnchorField("policyId", policyId)
        try validateHash("policyHash", policyHash)
        try requireAnchorField("submittedAt", submittedAt)
        try validateInternalLinkage()
    }

    public func validate(providerInput input: MeshRequestAnchorProviderInput) throws {
        try input.validate()
        try validate(
            providerMetadata: input.providerMetadata,
            endpointConfiguration: input.endpointConfiguration
        )
        let expected = try MeshMarooTestnetRequestAnchorSerializer.transactionRequest(from: input)
        guard self == expected else {
            throw MeshKitValidationError.signatureMismatch("maroo request anchor provider input linkage mismatch")
        }
    }

    private func validateInternalLinkage() throws {
        let identityParts = anchorPayloadIdentity.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard identityParts == [
            MeshRequestAnchorCanonicalization.version,
            requestId,
            requestNonce,
            policyId
        ] else {
            throw MeshKitValidationError.signatureMismatch("maroo request anchor payload identity mismatch")
        }

        let signerParts = delegatedSigner.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard signerParts.count == 3,
              signerParts.allSatisfy({ !$0.isEmpty }),
              signerParts[2] == signedMCPRequestSignature.keyId else {
            throw MeshKitValidationError.signatureMismatch("maroo request anchor delegated signer mismatch")
        }
    }
}

public enum MeshMarooTestnetRequestAnchorSerializer {
    public static func transactionRequest(
        from input: MeshRequestAnchorProviderInput
    ) throws -> MeshMarooTestnetRequestAnchorTransactionRequest {
        try input.validate()
        return try MeshMarooTestnetRequestAnchorTransactionRequest(
            providerMetadata: input.providerMetadata,
            endpointConfiguration: input.endpointConfiguration,
            anchorPayloadIdentity: anchorPayloadIdentity(for: input.payload),
            targetOwner: input.payload.metadata.targetBundleId,
            delegatedSigner: delegatedSigner(for: input.payload.metadata),
            anchorHash: input.sha256Hash(),
            requestId: input.payload.metadata.requestId,
            requestNonce: input.payload.metadata.nonce,
            signedMCPRequestHash: input.payload.metadata.signedRequestHash,
            signedMCPRequestSignature: input.payload.metadata.signature,
            policyId: input.payload.policyId,
            policyHash: input.payload.policyHash,
            submittedAt: input.submittedAt
        )
    }

    public static func anchorPayloadIdentity(
        for payload: MeshRequestAnchorPayload
    ) throws -> String {
        try payload.validate()
        return [
            payload.version,
            payload.metadata.requestId,
            payload.metadata.nonce,
            payload.policyId
        ].joined(separator: ":")
    }

    public static func delegatedSigner(
        for metadata: MeshSignedRequestAnchorMetadata
    ) throws -> String {
        try metadata.validate()
        return [
            metadata.callerAppId,
            metadata.callerBundleId,
            metadata.signature.keyId
        ].joined(separator: ":")
    }
}

public struct MeshMarooTestnetDeterministicRequestAnchorSubmissionClient: MeshMarooTestnetRequestAnchorSubmissionClient {
    public let status: MeshRequestAnchorStatus
    public let transactionHash: String?
    public let message: String?

    public init(
        status: MeshRequestAnchorStatus = .submitted,
        transactionHash: String? = nil,
        message: String? = nil
    ) throws {
        self.status = status
        self.transactionHash = try transactionHash.map { try normalizedAnchorField("transactionHash", $0) }
        self.message = try message.map { try normalizedAnchorField("message", $0) }
    }

    public func submitRequestAnchor(
        _ input: MeshRequestAnchorProviderInput
    ) async throws -> MeshMarooTestnetRequestAnchorSubmissionResponse {
        try input.validate()
        return try MeshMarooTestnetRequestAnchorSubmissionResponse(
            providerMetadata: input.providerMetadata,
            anchorId: "maroo-anchor-\(input.payload.metadata.requestId)",
            transactionHash: transactionHash ?? Self.deterministicAnchorTransactionHash(input: input),
            status: status,
            observedAt: input.submittedAt,
            message: messageForStatus
        )
    }

    private var messageForStatus: String? {
        if let message {
            return message
        }
        return status == .failed ? "maroo testnet request anchor submission failed" : nil
    }

    private static func deterministicAnchorTransactionHash(input: MeshRequestAnchorProviderInput) -> String {
        let data = Data("\(MeshMarooTestnetRequestAnchorAdapter.adapterId):\(input.sha256Hash().value)".utf8)
        let digest = SHA256.hash(data: data)
        return "0x" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

public struct MeshMarooTestnetRPCRequestAnchorSubmissionClient: MeshMarooTestnetRequestAnchorSubmissionClient {
    public static let jsonRPCVersion = "2.0"
    public static let method = "meshkit_submitRequestAnchor"

    public let transport: any MeshMarooTestnetRequestAnchorHTTPTransport
    public let requestId: Int

    public init(
        transport: any MeshMarooTestnetRequestAnchorHTTPTransport = MeshMarooTestnetURLSessionRequestAnchorHTTPTransport(),
        requestId: Int = 1
    ) {
        self.transport = transport
        self.requestId = requestId
    }

    public func submitRequestAnchor(
        _ input: MeshRequestAnchorProviderInput
    ) async throws -> MeshMarooTestnetRequestAnchorSubmissionResponse {
        try input.validate()
        let transactionRequest = try MeshMarooTestnetRequestAnchorSerializer.transactionRequest(from: input)
        try transactionRequest.validate(providerInput: input)

        let request = try httpRequest(
            transactionRequest: transactionRequest,
            endpoint: input.endpointConfiguration.rpcEndpoint
        )
        let (data, response) = try await transport.sendMarooRequestAnchor(request)
        guard (200..<300).contains(response.statusCode) else {
            return try rpcFailureResponse(
                input: input,
                message: "maroo testnet request anchor HTTP \(response.statusCode)"
            )
        }

        let decoder = JSONDecoder()
        let rpcResponse = try decoder.decode(MeshMarooTestnetRequestAnchorJSONRPCResponse.self, from: data)
        if let error = rpcResponse.error {
            return try rpcFailureResponse(input: input, message: error.normalizedMessage)
        }

        guard let result = rpcResponse.result else {
            return try rpcFailureResponse(
                input: input,
                message: "maroo testnet request anchor RPC result missing"
            )
        }

        return try result.submissionResponse(
            providerMetadata: input.providerMetadata,
            fallbackAnchorId: "maroo-anchor-\(input.payload.metadata.requestId)",
            fallbackObservedAt: input.submittedAt
        )
    }

    public func httpRequest(
        transactionRequest: MeshMarooTestnetRequestAnchorTransactionRequest,
        endpoint: URL
    ) throws -> URLRequest {
        try transactionRequest.validate()
        try MeshChainProviderIdentity.validateNetworkURL("rpcEndpoint", endpoint)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        let rpcRequest = MeshMarooTestnetRequestAnchorJSONRPCRequest(
            id: requestId,
            method: Self.method,
            params: [transactionRequest]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        request.httpBody = try encoder.encode(rpcRequest)
        return request
    }

    private func rpcFailureResponse(
        input: MeshRequestAnchorProviderInput,
        message: String
    ) throws -> MeshMarooTestnetRequestAnchorSubmissionResponse {
        try MeshMarooTestnetRequestAnchorSubmissionResponse(
            providerMetadata: input.providerMetadata,
            anchorId: "maroo-anchor-\(input.payload.metadata.requestId)",
            providerOutcome: MeshMarooTestnetRequestAnchorProviderOutcome.failure.rawValue,
            observedAt: input.submittedAt,
            message: sanitizedMarooAnchorMessage(message)
        )
    }
}

private struct MeshMarooTestnetRequestAnchorJSONRPCRequest: Encodable, Sendable {
    let jsonrpc: String
    let id: Int
    let method: String
    let params: [MeshMarooTestnetRequestAnchorTransactionRequest]

    init(
        jsonrpc: String = MeshMarooTestnetRPCRequestAnchorSubmissionClient.jsonRPCVersion,
        id: Int,
        method: String,
        params: [MeshMarooTestnetRequestAnchorTransactionRequest]
    ) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
}

private struct MeshMarooTestnetRequestAnchorJSONRPCResponse: Decodable {
    let result: MeshMarooTestnetRequestAnchorRPCResult?
    let error: MeshMarooTestnetRequestAnchorJSONRPCError?
}

private struct MeshMarooTestnetRequestAnchorJSONRPCError: Decodable {
    let code: Int?
    let message: String

    var normalizedMessage: String {
        if let code {
            return sanitizedMarooAnchorMessage("maroo RPC \(code): \(message)")
        }
        return sanitizedMarooAnchorMessage(message)
    }
}

private struct MeshMarooTestnetRequestAnchorRPCResult: Decodable {
    let anchorId: String?
    let transactionHash: String?
    let providerOutcome: MeshMarooTestnetRequestAnchorProviderOutcome?
    let providerAnchorState: MeshMarooTestnetRequestAnchorStateMapping?
    let status: MeshRequestAnchorStatus?
    let observedAt: String?
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case anchorId
        case anchor_id
        case transactionHash
        case transaction_hash
        case txHash
        case tx_hash
        case providerOutcome
        case provider_outcome
        case providerAnchorState
        case provider_anchor_state
        case anchorState
        case anchor_state
        case transactionState
        case transaction_state
        case txStatus
        case tx_status
        case status
        case anchorStatus
        case anchor_status
        case observedAt
        case observed_at
        case message
    }

    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let transactionHash = try? singleValue.decode(String.self) {
            self.anchorId = nil
            self.transactionHash = transactionHash
            self.providerOutcome = .success
            self.providerAnchorState = nil
            self.status = nil
            self.observedAt = nil
            self.message = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.anchorId = try container.decodeOptionalString(.anchorId, fallback: .anchor_id)
        self.transactionHash = try container.decodeOptionalString(.transactionHash, fallback: .transaction_hash)
            ?? container.decodeOptionalString(.txHash, fallback: .tx_hash)
        let providerOutcomeValue = try container.decodeOptionalString(.providerOutcome, fallback: .provider_outcome)
        self.providerOutcome = try providerOutcomeValue.map {
            try MeshMarooTestnetRequestAnchorProviderOutcome(providerValue: $0)
        }
        let providerAnchorStateValue = try container.decodeOptionalString(.providerAnchorState, fallback: .provider_anchor_state)
            ?? container.decodeOptionalString(.anchorState, fallback: .anchor_state)
            ?? container.decodeOptionalString(.transactionState, fallback: .transaction_state)
            ?? container.decodeOptionalString(.txStatus, fallback: .tx_status)
        self.providerAnchorState = try providerAnchorStateValue.map {
            try MeshMarooTestnetRequestAnchorStateMapping(providerAnchorState: $0)
        }
        let statusValue = try container.decodeOptionalString(.status, fallback: .anchorStatus)
            ?? container.decodeIfPresent(String.self, forKey: .anchor_status)
        self.status = try statusValue.map { value in
            if let status = MeshRequestAnchorStatus(rawValue: value) {
                return status
            }
            return try MeshMarooTestnetRequestAnchorStateMapping(providerAnchorState: value).anchorStatus
        }
        self.observedAt = try container.decodeOptionalString(.observedAt, fallback: .observed_at)
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
            .map(sanitizedMarooAnchorMessage)
    }

    func submissionResponse(
        providerMetadata: MeshChainProviderMetadata,
        fallbackAnchorId: String,
        fallbackObservedAt: String
    ) throws -> MeshMarooTestnetRequestAnchorSubmissionResponse {
        if let providerOutcome {
            return try MeshMarooTestnetRequestAnchorSubmissionResponse(
                providerMetadata: providerMetadata,
                anchorId: anchorId ?? fallbackAnchorId,
                transactionHash: transactionHash,
                providerOutcome: providerOutcome.rawValue,
                observedAt: observedAt ?? fallbackObservedAt,
                message: message
            )
        }

        if let providerAnchorState {
            return try MeshMarooTestnetRequestAnchorSubmissionResponse(
                providerMetadata: providerMetadata,
                anchorId: anchorId ?? fallbackAnchorId,
                transactionHash: transactionHash,
                providerAnchorState: providerAnchorState.providerAnchorState,
                observedAt: observedAt ?? fallbackObservedAt,
                message: message
            )
        }

        return try MeshMarooTestnetRequestAnchorSubmissionResponse(
            providerMetadata: providerMetadata,
            anchorId: anchorId ?? fallbackAnchorId,
            transactionHash: transactionHash,
            status: status ?? (transactionHash == nil ? .pending : .submitted),
            observedAt: observedAt ?? fallbackObservedAt,
            message: message
        )
    }
}

public struct MeshRequestAnchorSubmissionOutput: Codable, Equatable, Sendable {
    public static let version = "meshkit-request-anchor-output/v1"

    public let version: String
    public let anchoringReference: MeshRequestAnchorIdentifier
    public let requestHash: MeshPayloadHash
    public let requestNonce: String
    public let policyId: String
    public let policyHash: MeshPayloadHash
    public let status: MeshRequestAnchorStatus
    public let submittedAt: String
    public let observedAt: String?
    public let message: String?

    public init(
        anchoringReference: MeshRequestAnchorIdentifier,
        requestHash: MeshPayloadHash,
        requestNonce: String,
        policyId: String,
        policyHash: MeshPayloadHash,
        status: MeshRequestAnchorStatus,
        submittedAt: String,
        observedAt: String? = nil,
        message: String? = nil,
        version: String = MeshRequestAnchorSubmissionOutput.version
    ) throws {
        self.version = try normalizedAnchorField("version", version)
        self.anchoringReference = anchoringReference
        self.requestHash = requestHash
        self.requestNonce = try normalizedAnchorField("requestNonce", requestNonce)
        self.policyId = try normalizedAnchorField("policyId", policyId)
        self.policyHash = policyHash
        self.status = status
        self.submittedAt = try normalizedAnchorField("submittedAt", submittedAt)
        self.observedAt = try observedAt.map { try normalizedAnchorField("observedAt", $0) }
        self.message = try message.map { try normalizedAnchorField("message", $0) }
        try validate()
    }

    public init(anchor: MeshRequestAnchor) throws {
        try anchor.validate()
        guard let payload = anchor.payload else {
            throw MeshKitValidationError.invalidChainProviderIdentity("request anchor payload")
        }
        try self.init(
            anchoringReference: anchor.identifier,
            requestHash: anchor.metadata.signedRequestHash,
            requestNonce: anchor.metadata.nonce,
            policyId: payload.policyId,
            policyHash: payload.policyHash,
            status: anchor.status,
            submittedAt: anchor.submittedAt,
            observedAt: anchor.observedAt,
            message: anchor.message
        )
        try Self.validate(output: self, anchor: anchor)
    }

    public func validate() throws {
        guard version == Self.version else {
            throw MeshKitValidationError.invalidChainProviderIdentity("version")
        }
        try anchoringReference.validate()
        try validateHash("requestHash", requestHash)
        try requireAnchorField("requestNonce", requestNonce)
        try requireAnchorField("policyId", policyId)
        try validateHash("policyHash", policyHash)
        try requireAnchorField("submittedAt", submittedAt)
        if let observedAt {
            try requireAnchorField("observedAt", observedAt)
        }
        if let message {
            try requireAnchorField("message", message)
        }
    }

    public static func validate(
        output: MeshRequestAnchorSubmissionOutput,
        anchor: MeshRequestAnchor
    ) throws {
        try output.validate()
        try anchor.validate()
        guard let payload = anchor.payload else {
            throw MeshKitValidationError.invalidChainProviderIdentity("request anchor payload")
        }
        guard output.anchoringReference == anchor.identifier else {
            throw MeshKitValidationError.signatureMismatch("request anchor output reference mismatch")
        }
        guard output.requestHash == anchor.metadata.signedRequestHash,
              output.requestNonce == anchor.metadata.nonce else {
            throw MeshKitValidationError.signatureMismatch("request anchor output request linkage mismatch")
        }
        guard output.policyId == payload.policyId,
              output.policyHash == payload.policyHash else {
            throw MeshKitValidationError.signatureMismatch("request anchor output policy linkage mismatch")
        }
        guard output.status == anchor.status,
              output.submittedAt == anchor.submittedAt,
              output.observedAt == anchor.observedAt,
              output.message == anchor.message else {
            throw MeshKitValidationError.signatureMismatch("request anchor output status mismatch")
        }
    }

    public static func validate(
        output: MeshRequestAnchorSubmissionOutput,
        anchor: MeshRequestAnchor,
        for submission: MeshRequestAnchorSubmission,
        providerIdentity: MeshChainProviderIdentity
    ) throws {
        try MeshRequestAnchorSubmissionModule.validate(
            anchor: anchor,
            for: submission,
            providerIdentity: providerIdentity
        )
        try validate(output: output, anchor: anchor)
        guard output.requestHash == submission.payload.metadata.signedRequestHash,
              output.requestNonce == submission.payload.metadata.nonce else {
            throw MeshKitValidationError.signatureMismatch("request anchor output submission request linkage mismatch")
        }
        guard output.policyId == submission.payload.policyId,
              output.policyHash == submission.payload.policyHash else {
            throw MeshKitValidationError.signatureMismatch("request anchor output submission policy linkage mismatch")
        }
    }
}

public struct MeshRequestAnchorReferenceOutput: Codable, Equatable, Sendable {
    public static let version = "meshkit-request-anchor-reference-output/v1"

    public let version: String
    public let requestHash: MeshPayloadHash
    public let requestNonce: String
    public let policyId: String
    public let policyHash: MeshPayloadHash
    public let providerReference: MeshRequestAnchorIdentifier
    public let status: MeshRequestAnchorStatus

    public init(
        requestHash: MeshPayloadHash,
        requestNonce: String,
        policyId: String,
        policyHash: MeshPayloadHash,
        providerReference: MeshRequestAnchorIdentifier,
        status: MeshRequestAnchorStatus,
        version: String = MeshRequestAnchorReferenceOutput.version
    ) throws {
        self.version = try normalizedAnchorField("version", version)
        self.requestHash = requestHash
        self.requestNonce = try normalizedAnchorField("requestNonce", requestNonce)
        self.policyId = try normalizedAnchorField("policyId", policyId)
        self.policyHash = policyHash
        self.providerReference = providerReference
        self.status = status
        try validate()
    }

    public init(anchor: MeshRequestAnchor) throws {
        try anchor.validate()
        guard let payload = anchor.payload else {
            throw MeshKitValidationError.invalidChainProviderIdentity("request anchor payload")
        }
        try self.init(
            requestHash: anchor.metadata.signedRequestHash,
            requestNonce: anchor.metadata.nonce,
            policyId: payload.policyId,
            policyHash: payload.policyHash,
            providerReference: anchor.identifier,
            status: anchor.status
        )
        try Self.validate(output: self, anchor: anchor)
    }

    public init(submissionOutput: MeshRequestAnchorSubmissionOutput) throws {
        try submissionOutput.validate()
        try self.init(
            requestHash: submissionOutput.requestHash,
            requestNonce: submissionOutput.requestNonce,
            policyId: submissionOutput.policyId,
            policyHash: submissionOutput.policyHash,
            providerReference: submissionOutput.anchoringReference,
            status: submissionOutput.status
        )
    }

    public func validate() throws {
        guard version == Self.version else {
            throw MeshKitValidationError.invalidChainProviderIdentity("version")
        }
        try validateHash("requestHash", requestHash)
        try validateAnchorIdentifierFormat("requestNonce", requestNonce)
        try validateAnchorIdentifierFormat("policyId", policyId)
        try validateHash("policyHash", policyHash)
        try providerReference.validate()
    }

    public static func validate(
        output: MeshRequestAnchorReferenceOutput,
        anchor: MeshRequestAnchor
    ) throws {
        try output.validate()
        try anchor.validate()
        guard let payload = anchor.payload else {
            throw MeshKitValidationError.invalidChainProviderIdentity("request anchor payload")
        }
        guard output.providerReference == anchor.identifier else {
            throw MeshKitValidationError.signatureMismatch("request anchor reference output provider reference mismatch")
        }
        guard output.requestHash == anchor.metadata.signedRequestHash,
              output.requestNonce == anchor.metadata.nonce else {
            throw MeshKitValidationError.signatureMismatch("request anchor reference output request linkage mismatch")
        }
        guard output.policyId == payload.policyId,
              output.policyHash == payload.policyHash else {
            throw MeshKitValidationError.signatureMismatch("request anchor reference output policy linkage mismatch")
        }
        guard output.status == anchor.status else {
            throw MeshKitValidationError.signatureMismatch("request anchor reference output status mismatch")
        }
    }
}

public struct MeshRequestAnchorSubmissionModule: Sendable {
    public let provider: any MeshRequestAnchorProvider

    public init(provider: any MeshRequestAnchorProvider) {
        self.provider = provider
    }

    public func submitAnchor(
        _ input: MeshRequestAnchorSubmitInput
    ) async throws -> MeshRequestAnchorSubmissionOutput {
        let configuration = try MeshChainProviderConfiguration(
            identity: provider.identity,
            capabilities: provider.capabilities
        )
        try configuration.require(.anchorSignedRequest)
        try input.validate(providerIdentity: configuration.identity)

        let anchor = try await provider.anchorSignedRequest(
            payload: input.payload,
            submittedAt: input.submittedAt
        )
        try anchor.validate()
        guard anchor.metadata.signedRequestHash == input.signedMCPRequestHash,
              anchor.metadata.nonce == input.requestNonce else {
            throw MeshKitValidationError.signatureMismatch("request anchor submitted input request linkage mismatch")
        }
        guard anchor.payload?.policyId == input.policyId,
              anchor.payload?.policyHash == input.policyHash else {
            throw MeshKitValidationError.signatureMismatch("request anchor submitted input policy linkage mismatch")
        }
        guard anchor.identifier.identity.metadata == configuration.identity.metadata,
              anchor.submittedAt == input.submittedAt else {
            throw MeshKitValidationError.signatureMismatch("request anchor submitted input provider linkage mismatch")
        }

        let output = try MeshRequestAnchorSubmissionOutput(anchor: anchor)
        guard output.requestHash == input.signedMCPRequestHash,
              output.requestNonce == input.requestNonce,
              output.policyId == input.policyId,
              output.policyHash == input.policyHash else {
            throw MeshKitValidationError.signatureMismatch("request anchor output submit input linkage mismatch")
        }
        return output
    }

    public func submitAnchor(
        payload: MeshRequestAnchorPayload,
        signedMCPRequestHash: MeshPayloadHash,
        requestNonce: String,
        policyId: String,
        policyHash: MeshPayloadHash,
        submittedAt: String
    ) async throws -> MeshRequestAnchorSubmissionOutput {
        let input = try MeshRequestAnchorSubmitInput(
            payload: payload,
            signedMCPRequestHash: signedMCPRequestHash,
            requestNonce: requestNonce,
            policyId: policyId,
            policyHash: policyHash,
            providerIdentity: provider.identity,
            submittedAt: submittedAt
        )
        return try await submitAnchor(input)
    }

    public func submit(
        _ submission: MeshRequestAnchorSubmission,
        boundTo request: MeshRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy
    ) async throws -> MeshRequestAnchor {
        let configuration = try MeshChainProviderConfiguration(
            identity: provider.identity,
            capabilities: provider.capabilities
        )
        try configuration.require(.anchorSignedRequest)
        try submission.validate(
            boundTo: request,
            policy: policy,
            providerIdentity: configuration.identity
        )

        let anchor = try await provider.anchorSignedRequest(
            payload: submission.payload,
            submittedAt: submission.submittedAt
        )
        try Self.validate(anchor: anchor, for: submission, providerIdentity: configuration.identity)
        return anchor
    }

    public func submitAnchor(
        _ submission: MeshRequestAnchorSubmission,
        boundTo request: MeshRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy
    ) async throws -> MeshRequestAnchorSubmissionOutput {
        let configuration = try MeshChainProviderConfiguration(
            identity: provider.identity,
            capabilities: provider.capabilities
        )
        try configuration.require(.anchorSignedRequest)
        try submission.validate(
            boundTo: request,
            policy: policy,
            providerIdentity: configuration.identity
        )

        let input = try MeshRequestAnchorSubmitInput(
            payload: submission.payload,
            providerIdentity: configuration.identity,
            submittedAt: submission.submittedAt
        )
        let output = try await submitAnchor(input)
        guard output.requestHash == submission.payload.metadata.signedRequestHash,
              output.requestNonce == submission.payload.metadata.nonce else {
            throw MeshKitValidationError.signatureMismatch("request anchor output submission request linkage mismatch")
        }
        guard output.policyId == submission.payload.policyId,
              output.policyHash == submission.payload.policyHash else {
            throw MeshKitValidationError.signatureMismatch("request anchor output submission policy linkage mismatch")
        }
        return output
    }

    public func submitOutput(
        _ submission: MeshRequestAnchorSubmission,
        boundTo request: MeshRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy
    ) async throws -> MeshRequestAnchorSubmissionOutput {
        try await submitAnchor(submission, boundTo: request, policy: policy)
    }

    public func submitOutput(
        request: MeshRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        submittedAt: String
    ) async throws -> MeshRequestAnchorSubmissionOutput {
        let submission = try MeshRequestAnchorSubmission(
            request: request,
            policy: policy,
            providerIdentity: provider.identity,
            submittedAt: submittedAt
        )
        return try await submitOutput(submission, boundTo: request, policy: policy)
    }

    public func submit(
        request: MeshRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        submittedAt: String
    ) async throws -> MeshRequestAnchor {
        let submission = try MeshRequestAnchorSubmission(
            request: request,
            policy: policy,
            providerIdentity: provider.identity,
            submittedAt: submittedAt
        )
        return try await submit(submission, boundTo: request, policy: policy)
    }

    public func submitAndExecute(
        _ submission: MeshRequestAnchorSubmission,
        boundTo request: MeshRequest,
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        authorizationDecision: MeshAgentWalletAuthorizationDecision,
        paymentId: String,
        requestedAt: String,
        paymentSubmittedAt: String,
        executor: any MeshPaymentExecutor
    ) async throws -> MeshPaymentExecutionResult {
        try policy.validateExecutionRequest(
            authorizationDecision.executionRequest,
            requestedAt: requestedAt
        )
        let anchor = try await submit(submission, boundTo: request, policy: policy)
        let paymentRequest = try MeshPaymentExecutionRequest(
            paymentId: paymentId,
            authorizationDecision: authorizationDecision,
            requestAnchor: anchor,
            requestedAt: requestedAt
        )
        return try await executor.executePayment(
            paymentRequest,
            originatingRequest: request,
            submittedAt: paymentSubmittedAt
        )
    }

    public static func validate(
        anchor: MeshRequestAnchor,
        for submission: MeshRequestAnchorSubmission,
        providerIdentity: MeshChainProviderIdentity
    ) throws {
        try anchor.validate()
        try submission.validate(providerIdentity: providerIdentity)
        guard anchor.metadata == submission.payload.metadata else {
            throw MeshKitValidationError.signatureMismatch("request anchor submitted metadata mismatch")
        }
        guard anchor.payload == submission.payload else {
            throw MeshKitValidationError.signatureMismatch("request anchor submitted payload mismatch")
        }
        guard anchor.identifier.identity.metadata == providerIdentity.metadata else {
            throw MeshKitValidationError.signatureMismatch("request anchor provider metadata mismatch")
        }
        guard anchor.submittedAt == submission.submittedAt else {
            throw MeshKitValidationError.signatureMismatch("request anchor submitted timestamp mismatch")
        }
    }
}

public struct MeshRequestAnchorStatusModule: Sendable {
    public let provider: any MeshRequestAnchorProvider

    public init(provider: any MeshRequestAnchorProvider) {
        self.provider = provider
    }

    public func lookup(
        identifier: MeshRequestAnchorIdentifier,
        checkedAt: String
    ) async throws -> MeshRequestAnchor {
        let response = try await lookupResponse(identifier: identifier, checkedAt: checkedAt)
        guard let anchor = response.anchor else {
            throw MeshKitValidationError.requestAnchorReferenceNotFound(identifier.anchorId)
        }
        return anchor
    }

    public func lookupResponse(
        identifier: MeshRequestAnchorIdentifier,
        checkedAt: String
    ) async throws -> MeshRequestAnchorStatusLookupResponse {
        let configuration = try MeshChainProviderConfiguration(
            identity: provider.identity,
            capabilities: provider.capabilities
        )
        try configuration.require(.lookupRequestAnchorStatus)
        try identifier.validate()
        guard identifier.identity.metadata == configuration.identity.metadata else {
            throw MeshKitValidationError.signatureMismatch("request anchor provider metadata mismatch")
        }

        let response = try await provider.requestAnchorStatusResponse(
            identifier: identifier,
            checkedAt: checkedAt
        )
        try Self.validate(response: response, identifier: identifier, providerIdentity: configuration.identity)
        return response
    }

    public func status(
        identifier: MeshRequestAnchorIdentifier,
        checkedAt: String
    ) async throws -> MeshRequestAnchorStatus {
        try await lookup(identifier: identifier, checkedAt: checkedAt).status
    }

    public static func validate(
        anchor: MeshRequestAnchor,
        identifier: MeshRequestAnchorIdentifier,
        providerIdentity: MeshChainProviderIdentity
    ) throws {
        try anchor.validate()
        try identifier.validate()
        try providerIdentity.validate()
        guard identifier.identity.metadata == providerIdentity.metadata,
              anchor.identifier.identity.metadata == providerIdentity.metadata else {
            throw MeshKitValidationError.signatureMismatch("request anchor provider metadata mismatch")
        }
        guard anchor.identifier == identifier else {
            throw MeshKitValidationError.signatureMismatch("request anchor status identifier mismatch")
        }
    }

    public static func validate(
        response: MeshRequestAnchorStatusLookupResponse,
        identifier: MeshRequestAnchorIdentifier,
        providerIdentity: MeshChainProviderIdentity
    ) throws {
        try response.validate()
        try identifier.validate()
        try providerIdentity.validate()
        guard response.identifier == identifier,
              response.identifier.identity.metadata == providerIdentity.metadata else {
            throw MeshKitValidationError.signatureMismatch("request anchor status identifier mismatch")
        }
        if let anchor = response.anchor {
            try validate(anchor: anchor, identifier: identifier, providerIdentity: providerIdentity)
        }
    }
}

public struct MeshRequestAnchorResolutionModule: Sendable {
    public let provider: any MeshRequestAnchorProvider

    public init(provider: any MeshRequestAnchorProvider) {
        self.provider = provider
    }

    public func resolveRequestHash(
        identifier: MeshRequestAnchorIdentifier,
        checkedAt: String
    ) async throws -> MeshPayloadHash {
        let response = try await resolveResponse(identifier: identifier, checkedAt: checkedAt)
        guard let requestHash = response.requestHash else {
            throw MeshKitValidationError.requestAnchorReferenceNotFound(identifier.anchorId)
        }
        return requestHash
    }

    public func resolveResponse(
        identifier: MeshRequestAnchorIdentifier,
        checkedAt: String
    ) async throws -> MeshRequestAnchorResolutionResponse {
        let configuration = try MeshChainProviderConfiguration(
            identity: provider.identity,
            capabilities: provider.capabilities
        )
        try configuration.require(.resolveRequestAnchorHash)
        try identifier.validate()
        guard identifier.identity.metadata == configuration.identity.metadata else {
            throw MeshKitValidationError.signatureMismatch("request anchor provider metadata mismatch")
        }

        let response = try await provider.requestAnchorResolutionResponse(
            identifier: identifier,
            checkedAt: checkedAt
        )
        try Self.validate(response: response, identifier: identifier, providerIdentity: configuration.identity)
        return response
    }

    public static func validate(
        response: MeshRequestAnchorResolutionResponse,
        identifier: MeshRequestAnchorIdentifier,
        providerIdentity: MeshChainProviderIdentity
    ) throws {
        try response.validate()
        try identifier.validate()
        try providerIdentity.validate()
        guard response.identifier == identifier,
              response.identifier.identity.metadata == providerIdentity.metadata else {
            throw MeshKitValidationError.signatureMismatch("request anchor resolution identifier mismatch")
        }
    }
}

public enum MeshRequestAnchorStatusLookupOutcome: String, Codable, Equatable, Sendable {
    case known
    case unknownReference
}

public enum MeshRequestAnchorResolutionOutcome: String, Codable, Equatable, Sendable {
    case known
    case unknownReference
}

public struct MeshRequestAnchorResolutionResponse: Codable, Equatable, Sendable {
    public let outcome: MeshRequestAnchorResolutionOutcome
    public let identifier: MeshRequestAnchorIdentifier
    public let requestHash: MeshPayloadHash?
    public let anchorStatus: MeshRequestAnchorStatus?
    public let checkedAt: String
    public let message: String?

    public init(
        outcome: MeshRequestAnchorResolutionOutcome,
        identifier: MeshRequestAnchorIdentifier,
        requestHash: MeshPayloadHash? = nil,
        anchorStatus: MeshRequestAnchorStatus? = nil,
        checkedAt: String,
        message: String? = nil
    ) throws {
        self.outcome = outcome
        self.identifier = identifier
        self.requestHash = requestHash
        self.anchorStatus = anchorStatus
        self.checkedAt = try normalizedAnchorField("checkedAt", checkedAt)
        self.message = try message.map { try normalizedAnchorField("message", $0) }
        try validate()
    }

    public static func known(
        identifier: MeshRequestAnchorIdentifier,
        requestHash: MeshPayloadHash,
        anchorStatus: MeshRequestAnchorStatus,
        checkedAt: String
    ) throws -> MeshRequestAnchorResolutionResponse {
        try MeshRequestAnchorResolutionResponse(
            outcome: .known,
            identifier: identifier,
            requestHash: requestHash,
            anchorStatus: anchorStatus,
            checkedAt: checkedAt
        )
    }

    public static func unknownReference(
        identifier: MeshRequestAnchorIdentifier,
        checkedAt: String,
        message: String = "unknown anchoring reference"
    ) throws -> MeshRequestAnchorResolutionResponse {
        try MeshRequestAnchorResolutionResponse(
            outcome: .unknownReference,
            identifier: identifier,
            checkedAt: checkedAt,
            message: message
        )
    }

    public func validate() throws {
        try identifier.validate()
        try requireAnchorField("checkedAt", checkedAt)
        if let message {
            try requireAnchorField("message", message)
        }

        switch outcome {
        case .known:
            guard let requestHash else {
                throw MeshKitValidationError.invalidChainProviderIdentity("requestHash")
            }
            guard anchorStatus != nil else {
                throw MeshKitValidationError.invalidChainProviderIdentity("anchorStatus")
            }
            try validateHash("requestHash", requestHash)
        case .unknownReference:
            guard requestHash == nil else {
                throw MeshKitValidationError.signatureMismatch("unknown request anchor resolution cannot include request hash")
            }
            guard anchorStatus == nil else {
                throw MeshKitValidationError.signatureMismatch("unknown request anchor resolution cannot include anchor status")
            }
        }
    }
}

public struct MeshRequestAnchorStatusLookupResponse: Codable, Equatable, Sendable {
    public let outcome: MeshRequestAnchorStatusLookupOutcome
    public let identifier: MeshRequestAnchorIdentifier
    public let anchor: MeshRequestAnchor?
    public let checkedAt: String
    public let message: String?

    public init(
        outcome: MeshRequestAnchorStatusLookupOutcome,
        identifier: MeshRequestAnchorIdentifier,
        anchor: MeshRequestAnchor? = nil,
        checkedAt: String,
        message: String? = nil
    ) throws {
        self.outcome = outcome
        self.identifier = identifier
        self.anchor = anchor
        self.checkedAt = try normalizedAnchorField("checkedAt", checkedAt)
        self.message = try message.map { try normalizedAnchorField("message", $0) }
        try validate()
    }

    public static func known(
        anchor: MeshRequestAnchor,
        checkedAt: String
    ) throws -> MeshRequestAnchorStatusLookupResponse {
        try MeshRequestAnchorStatusLookupResponse(
            outcome: .known,
            identifier: anchor.identifier,
            anchor: anchor,
            checkedAt: checkedAt,
            message: anchor.message
        )
    }

    public static func unknownReference(
        identifier: MeshRequestAnchorIdentifier,
        checkedAt: String,
        message: String = "unknown anchoring reference"
    ) throws -> MeshRequestAnchorStatusLookupResponse {
        try MeshRequestAnchorStatusLookupResponse(
            outcome: .unknownReference,
            identifier: identifier,
            checkedAt: checkedAt,
            message: message
        )
    }

    public func validate() throws {
        try identifier.validate()
        try requireAnchorField("checkedAt", checkedAt)
        if let message {
            try requireAnchorField("message", message)
        }

        switch outcome {
        case .known:
            guard let anchor else {
                throw MeshKitValidationError.invalidChainProviderIdentity("anchor")
            }
            try anchor.validate()
            guard anchor.identifier == identifier else {
                throw MeshKitValidationError.signatureMismatch("request anchor status identifier mismatch")
            }
        case .unknownReference:
            guard anchor == nil else {
                throw MeshKitValidationError.signatureMismatch("unknown request anchor response cannot include anchor")
            }
        }
    }
}

public struct MeshRequestAnchorIdentifier: Codable, Equatable, Sendable {
    public let identity: MeshChainProviderIdentity
    public let anchorId: String
    public let transactionHash: String?
    public let explorerURL: URL?

    private enum CodingKeys: String, CodingKey {
        case identity
        case anchorId
        case transactionHash
        case explorerURL
    }

    public init(
        identity: MeshChainProviderIdentity,
        anchorId: String,
        transactionHash: String? = nil,
        explorerURL: URL? = nil
    ) throws {
        self.identity = identity
        self.anchorId = try normalizedAnchorField("anchorId", anchorId)
        self.transactionHash = try transactionHash.map { try normalizedAnchorField("transactionHash", $0) }
        if let explorerURL {
            self.explorerURL = explorerURL
        } else if let transactionHash {
            self.explorerURL = try? identity.explorerURL(transactionHash: transactionHash)
        } else {
            self.explorerURL = nil
        }
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            identity: container.decode(MeshChainProviderIdentity.self, forKey: .identity),
            anchorId: container.decode(String.self, forKey: .anchorId),
            transactionHash: container.decodeIfPresent(String.self, forKey: .transactionHash),
            explorerURL: container.decodeIfPresent(URL.self, forKey: .explorerURL)
        )
    }

    public func validate() throws {
        try identity.validate()
        try requireAnchorField("anchorId", anchorId)
        if let transactionHash {
            try requireAnchorField("transactionHash", transactionHash)
        }
        if let explorerURL {
            try MeshChainProviderIdentity.validateNetworkURL("explorerURL", explorerURL)
        }
    }
}

public struct MeshRequestAnchor: Codable, Equatable, Sendable {
    public let metadata: MeshSignedRequestAnchorMetadata
    public let payload: MeshRequestAnchorPayload?
    public let identifier: MeshRequestAnchorIdentifier
    public let status: MeshRequestAnchorStatus
    public let submittedAt: String
    public let observedAt: String?
    public let message: String?

    private enum CodingKeys: String, CodingKey {
        case metadata
        case payload
        case identifier
        case status
        case submittedAt
        case observedAt
        case message
    }

    public init(
        metadata: MeshSignedRequestAnchorMetadata,
        payload: MeshRequestAnchorPayload? = nil,
        identifier: MeshRequestAnchorIdentifier,
        status: MeshRequestAnchorStatus,
        submittedAt: String,
        observedAt: String? = nil,
        message: String? = nil
    ) throws {
        self.metadata = metadata
        self.payload = payload
        self.identifier = identifier
        self.status = status
        self.submittedAt = try normalizedAnchorField("submittedAt", submittedAt)
        self.observedAt = try observedAt.map { try normalizedAnchorField("observedAt", $0) }
        self.message = try message.map { try normalizedAnchorField("message", $0) }
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            metadata: container.decode(MeshSignedRequestAnchorMetadata.self, forKey: .metadata),
            payload: container.decodeIfPresent(MeshRequestAnchorPayload.self, forKey: .payload),
            identifier: container.decode(MeshRequestAnchorIdentifier.self, forKey: .identifier),
            status: container.decode(MeshRequestAnchorStatus.self, forKey: .status),
            submittedAt: container.decode(String.self, forKey: .submittedAt),
            observedAt: container.decodeIfPresent(String.self, forKey: .observedAt),
            message: container.decodeIfPresent(String.self, forKey: .message)
        )
    }

    public func validate() throws {
        try metadata.validate()
        if let payload {
            try payload.validate()
            guard payload.metadata == metadata else {
                throw MeshKitValidationError.signatureMismatch("request anchor payload metadata mismatch")
            }
        }
        try identifier.validate()
        try requireAnchorField("submittedAt", submittedAt)
        if let observedAt {
            try requireAnchorField("observedAt", observedAt)
        }
        if let message {
            try requireAnchorField("message", message)
        }
    }
}

public enum MeshRequestAnchorSerialization {
    public static func canonicalData(for anchor: MeshRequestAnchor) throws -> Data {
        try anchor.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(anchor)
    }

    public static func canonicalString(for anchor: MeshRequestAnchor) throws -> String {
        let data = try canonicalData(for: anchor)
        guard let string = String(data: data, encoding: .utf8) else {
            throw MeshKitValidationError.invalidChainProviderIdentity("requestAnchorSerialization")
        }
        return string
    }

    public static func decode(_ data: Data) throws -> MeshRequestAnchor {
        let anchor = try JSONDecoder().decode(MeshRequestAnchor.self, from: data)
        try anchor.validate()
        return anchor
    }

    public static func decode(_ string: String) throws -> MeshRequestAnchor {
        try decode(Data(string.utf8))
    }
}

public protocol MeshRequestAnchorProvider: Sendable {
    var identity: MeshChainProviderIdentity { get }
    var capabilities: [MeshChainProviderCapability] { get }

    func anchorSignedRequest(
        payload: MeshRequestAnchorPayload,
        submittedAt: String
    ) async throws -> MeshRequestAnchor

    func anchorSignedRequest(
        metadata: MeshSignedRequestAnchorMetadata,
        submittedAt: String
    ) async throws -> MeshRequestAnchor

    func requestAnchorStatus(
        identifier: MeshRequestAnchorIdentifier,
        checkedAt: String
    ) async throws -> MeshRequestAnchor

    func requestAnchorResolutionResponse(
        identifier: MeshRequestAnchorIdentifier,
        checkedAt: String
    ) async throws -> MeshRequestAnchorResolutionResponse
}

public struct MeshDemoRequestAnchorProvider: MeshRequestAnchorProvider {
    public let identity: MeshChainProviderIdentity
    public let capabilities: [MeshChainProviderCapability]
    public let status: MeshRequestAnchorStatus
    public let transactionHash: String?
    public let message: String?

    public init(
        identity: MeshChainProviderIdentity,
        capabilities: [MeshChainProviderCapability] = [.anchorSignedRequest, .createRequestAnchorReference, .signRequestAnchorReference, .lookupRequestAnchorStatus, .resolveRequestAnchorHash, .constructExplorerURL],
        status: MeshRequestAnchorStatus = .submitted,
        transactionHash: String? = nil,
        message: String? = nil
    ) throws {
        self.identity = identity
        self.capabilities = Array(Set(capabilities)).sorted()
        self.status = status
        self.transactionHash = try transactionHash.map { try normalizedAnchorField("transactionHash", $0) }
        self.message = try message.map { try normalizedAnchorField("message", $0) }
        try MeshChainProviderConfiguration(identity: identity, capabilities: self.capabilities).validate()
    }

    public func anchorSignedRequest(
        metadata: MeshSignedRequestAnchorMetadata,
        submittedAt: String
    ) async throws -> MeshRequestAnchor {
        try MeshChainProviderConfiguration(identity: identity, capabilities: capabilities).require(.anchorSignedRequest)
        try metadata.validate()

        return try MeshRequestAnchor(
            metadata: metadata,
            identifier: MeshRequestAnchorIdentifier(
                identity: identity,
                anchorId: "anchor-\(metadata.requestId)",
                transactionHash: transactionHash ?? Self.deterministicTransactionHash(metadata: metadata)
            ),
            status: status,
            submittedAt: submittedAt,
            observedAt: submittedAt,
            message: messageForSubmission
        )
    }

    public func requestAnchorStatus(
        identifier: MeshRequestAnchorIdentifier,
        checkedAt: String
    ) async throws -> MeshRequestAnchor {
        try MeshChainProviderConfiguration(identity: identity, capabilities: capabilities).require(.lookupRequestAnchorStatus)
        try identifier.validate()
        guard identifier.identity.metadata == identity.metadata else {
            throw MeshKitValidationError.signatureMismatch("request anchor provider metadata mismatch")
        }

        let metadata = try MeshSignedRequestAnchorMetadata(
            requestId: "status-\(identifier.anchorId)",
            nonce: "nonce-\(identifier.anchorId)",
            timestamp: checkedAt,
            callerAppId: "app.meshkit.demo",
            callerBundleId: "ai.meshkit.demo.caller",
            targetBundleId: "ai.meshkit.demo.target",
            capabilityId: "demo.anchor_status",
            payloadHash: MeshPayloadHash(value: String(repeating: "a", count: 64)),
            signature: MeshSignature(algorithm: "Ed25519", keyId: "demo-key", value: "signature"),
            signedRequestHash: MeshPayloadHash(value: String(repeating: "b", count: 64))
        )
        return try MeshRequestAnchor(
            metadata: metadata,
            identifier: identifier,
            status: status,
            submittedAt: checkedAt,
            observedAt: checkedAt,
            message: messageForSubmission
        )
    }

    private var messageForSubmission: String? {
        if let message {
            return message
        }
        return status == .failed ? "demo request anchor submission failed" : nil
    }

    private static func deterministicTransactionHash(metadata: MeshSignedRequestAnchorMetadata) -> String {
        let data = Data("\(metadata.requestId):\(metadata.nonce):\(metadata.signedRequestHash.value)".utf8)
        let digest = SHA256.hash(data: data)
        return "0x" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

public struct MeshMarooTestnetRequestAnchorAdapter: MeshRequestAnchorProvider {
    public static let adapterId = "maroo-testnet-request-anchor-demo-adapter"
    public static let defaultCapabilities: [MeshChainProviderCapability] = [
        .anchorSignedRequest,
        .constructExplorerURL,
        .createRequestAnchorReference,
        .identifyNetwork,
        .loadProviderConfiguration,
        .lookupRequestAnchorStatus,
        .resolveRequestAnchorHash,
        .signRequestAnchorReference
    ]

    public let chainProvider: MeshMarooTestnetChainProvider
    public let capabilities: [MeshChainProviderCapability]
    public let status: MeshRequestAnchorStatus
    public let transactionHash: String?
    public let message: String?
    public let submissionClient: any MeshMarooTestnetRequestAnchorSubmissionClient
    private let submittedAnchorStore: MeshMarooTestnetSubmittedRequestAnchorStore

    public var identity: MeshChainProviderIdentity { chainProvider.identity }
    public var providerMetadata: MeshChainProviderMetadata { chainProvider.metadata }
    public var endpointConfiguration: MeshChainProviderEndpointConfiguration {
        chainProvider.identity.endpointConfiguration
    }
    public var capabilityMetadata: MeshRequestAnchorProviderCapabilityMetadata {
        get throws {
            try MeshRequestAnchorProviderCapabilityMetadata(
                adapterId: Self.adapterId,
                providerIdentity: identity,
                capabilities: capabilities
            )
        }
    }

    public init(
        chainProvider: MeshMarooTestnetChainProvider = try! MeshMarooTestnetChainProvider(
            capabilities: MeshMarooTestnetRequestAnchorAdapter.defaultCapabilities
        ),
        capabilities: [MeshChainProviderCapability] = MeshMarooTestnetRequestAnchorAdapter.defaultCapabilities,
        status: MeshRequestAnchorStatus = .submitted,
        transactionHash: String? = nil,
        message: String? = nil,
        submissionClient: (any MeshMarooTestnetRequestAnchorSubmissionClient)? = nil
    ) throws {
        self.chainProvider = chainProvider
        self.capabilities = Array(Set(capabilities)).sorted()
        self.status = status
        self.transactionHash = try transactionHash.map { try normalizedAnchorField("transactionHash", $0) }
        self.message = try message.map { try normalizedAnchorField("message", $0) }
        self.submissionClient = try submissionClient ?? MeshMarooTestnetDeterministicRequestAnchorSubmissionClient(
            status: status,
            transactionHash: transactionHash,
            message: message
        )
        self.submittedAnchorStore = MeshMarooTestnetSubmittedRequestAnchorStore()
        try MeshChainProviderConfiguration(identity: chainProvider.identity, capabilities: self.capabilities).validate()
        try MeshChainProviderConfiguration(identity: chainProvider.identity, capabilities: chainProvider.capabilities)
            .require(.loadProviderConfiguration)
        try capabilityMetadata.validate()
    }

    public func anchorSignedRequest(
        metadata: MeshSignedRequestAnchorMetadata,
        submittedAt: String
    ) async throws -> MeshRequestAnchor {
        try MeshChainProviderConfiguration(identity: identity, capabilities: capabilities).require(.anchorSignedRequest)
        try metadata.validate()

        let anchor = try MeshRequestAnchor(
            metadata: metadata,
            identifier: MeshRequestAnchorIdentifier(
                identity: identity,
                anchorId: "maroo-anchor-\(metadata.requestId)",
                transactionHash: transactionHash ?? Self.deterministicAnchorTransactionHash(metadata: metadata)
            ),
            status: status,
            submittedAt: submittedAt,
            observedAt: submittedAt,
            message: messageForStatus
        )
        await submittedAnchorStore.record(anchor)
        return anchor
    }

    public func anchorSignedRequest(
        payload: MeshRequestAnchorPayload,
        submittedAt: String
    ) async throws -> MeshRequestAnchor {
        try MeshChainProviderConfiguration(identity: identity, capabilities: capabilities).require(.anchorSignedRequest)
        let input = try MeshRequestAnchorProviderInput(
            payload: payload,
            providerIdentity: identity,
            submittedAt: submittedAt
        )
        try input.validate(providerIdentity: identity)
        let response = try await submissionClient.submitRequestAnchor(input)
        try response.validate(providerIdentity: identity, submittedAt: input.submittedAt)

        let anchor = try response.normalizedRequestAnchor(
            payload: input.payload,
            identity: identity,
            submittedAt: input.submittedAt
        )
        await submittedAnchorStore.record(anchor)
        return anchor
    }

    public func requestAnchorStatus(
        identifier: MeshRequestAnchorIdentifier,
        checkedAt: String
    ) async throws -> MeshRequestAnchor {
        try MeshChainProviderConfiguration(identity: identity, capabilities: capabilities).require(.lookupRequestAnchorStatus)
        try identifier.validate()
        guard identifier.identity.metadata == identity.metadata else {
            throw MeshKitValidationError.signatureMismatch("request anchor provider metadata mismatch")
        }
        guard let anchor = try await submittedAnchorStore.anchor(
            for: identifier,
            observedAt: checkedAt
        ) else {
            throw MeshKitValidationError.requestAnchorReferenceNotFound(identifier.anchorId)
        }
        return anchor
    }

    public func requestAnchorResolutionResponse(
        identifier: MeshRequestAnchorIdentifier,
        checkedAt: String
    ) async throws -> MeshRequestAnchorResolutionResponse {
        try MeshChainProviderConfiguration(identity: identity, capabilities: capabilities).require(.resolveRequestAnchorHash)
        try identifier.validate()
        guard identifier.identity.metadata == identity.metadata else {
            throw MeshKitValidationError.signatureMismatch("request anchor provider metadata mismatch")
        }

        guard let resolution = await submittedAnchorStore.resolution(for: identifier) else {
            return try .unknownReference(identifier: identifier, checkedAt: checkedAt)
        }
        return try .known(
            identifier: identifier,
            requestHash: resolution.requestHash,
            anchorStatus: resolution.status,
            checkedAt: checkedAt
        )
    }

    private var messageForStatus: String? {
        if let message {
            return message
        }
        return status == .failed ? "maroo testnet request anchor submission failed" : nil
    }

    private static func deterministicAnchorTransactionHash(metadata: MeshSignedRequestAnchorMetadata) -> String {
        let data = Data("\(adapterId):\(metadata.requestId):\(metadata.nonce):\(metadata.signedRequestHash.value)".utf8)
        let digest = SHA256.hash(data: data)
        return "0x" + digest.map { String(format: "%02x", $0) }.joined()
    }

}

private actor MeshMarooTestnetSubmittedRequestAnchorStore {
    private var anchorsByAnchorId: [String: MeshRequestAnchor] = [:]

    func record(_ anchor: MeshRequestAnchor) {
        anchorsByAnchorId[anchor.identifier.anchorId] = anchor
    }

    func anchor(
        for identifier: MeshRequestAnchorIdentifier,
        observedAt: String
    ) throws -> MeshRequestAnchor? {
        guard let anchor = anchorsByAnchorId[identifier.anchorId],
              anchor.identifier == identifier else {
            return nil
        }
        return try MeshRequestAnchor(
            metadata: anchor.metadata,
            payload: anchor.payload,
            identifier: anchor.identifier,
            status: anchor.status,
            submittedAt: anchor.submittedAt,
            observedAt: observedAt,
            message: anchor.message
        )
    }

    func resolution(for identifier: MeshRequestAnchorIdentifier) -> (requestHash: MeshPayloadHash, status: MeshRequestAnchorStatus)? {
        guard let anchor = anchorsByAnchorId[identifier.anchorId],
              anchor.identifier == identifier else {
            return nil
        }
        return (anchor.metadata.signedRequestHash, anchor.status)
    }
}

public extension MeshRequestAnchorProvider {
    func anchorSignedRequest(
        payload: MeshRequestAnchorPayload,
        submittedAt: String
    ) async throws -> MeshRequestAnchor {
        let input = try MeshRequestAnchorProviderInput(
            payload: payload,
            providerIdentity: identity,
            submittedAt: submittedAt
        )
        let anchor = try await anchorSignedRequest(metadata: payload.metadata, submittedAt: submittedAt)
        return try MeshRequestAnchor(
            metadata: anchor.metadata,
            payload: input.payload,
            identifier: anchor.identifier,
            status: anchor.status,
            submittedAt: input.submittedAt,
            observedAt: anchor.observedAt,
            message: anchor.message
        )
    }

    func anchorSignedRequestIdentifier(
        metadata: MeshSignedRequestAnchorMetadata,
        submittedAt: String
    ) async throws -> MeshRequestAnchorIdentifier {
        let anchor = try await anchorSignedRequest(metadata: metadata, submittedAt: submittedAt)
        return anchor.identifier
    }

    func requestAnchorStatusValue(
        identifier: MeshRequestAnchorIdentifier,
        checkedAt: String
    ) async throws -> MeshRequestAnchorStatus {
        let anchor = try await requestAnchorStatus(identifier: identifier, checkedAt: checkedAt)
        return anchor.status
    }

    func requestAnchorStatusResponse(
        identifier: MeshRequestAnchorIdentifier,
        checkedAt: String
    ) async throws -> MeshRequestAnchorStatusLookupResponse {
        do {
            let anchor = try await requestAnchorStatus(identifier: identifier, checkedAt: checkedAt)
            return try .known(anchor: anchor, checkedAt: checkedAt)
        } catch MeshKitValidationError.requestAnchorReferenceNotFound {
            return try .unknownReference(identifier: identifier, checkedAt: checkedAt)
        }
    }

    func requestAnchorResolutionResponse(
        identifier: MeshRequestAnchorIdentifier,
        checkedAt: String
    ) async throws -> MeshRequestAnchorResolutionResponse {
        do {
            let anchor = try await requestAnchorStatus(identifier: identifier, checkedAt: checkedAt)
            return try .known(
                identifier: identifier,
                requestHash: anchor.metadata.signedRequestHash,
                anchorStatus: anchor.status,
                checkedAt: checkedAt
            )
        } catch MeshKitValidationError.requestAnchorReferenceNotFound {
            return try .unknownReference(identifier: identifier, checkedAt: checkedAt)
        }
    }
}

private func requireAnchorField(_ field: String, _ value: String) throws {
    _ = try normalizedAnchorField(field, value)
}

private func normalizedAnchorField(_ field: String, _ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed == value else {
        throw MeshKitValidationError.invalidChainProviderIdentity(field)
    }
    guard trimmed.rangeOfCharacter(from: CharacterSet.newlines.union(.controlCharacters)) == nil else {
        throw MeshKitValidationError.invalidChainProviderIdentity(field)
    }
    return trimmed
}

private func validateHash(_ field: String, _ hash: MeshPayloadHash) throws {
    guard hash.algorithm.lowercased() == "sha256" else {
        throw MeshKitValidationError.unsupportedPayloadHashAlgorithm
    }
    guard hash.value.count == 64,
          hash.value.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdefABCDEF").inverted) == nil else {
        throw MeshKitValidationError.invalidChainProviderIdentity("\(field).value")
    }
}

private func validateAnchorIdentifierFormat(_ field: String, _ value: String) throws {
    let normalized = try normalizedAnchorField(field, value)
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-")
    guard normalized.rangeOfCharacter(from: allowed.inverted) == nil else {
        throw MeshKitValidationError.invalidChainProviderIdentity(field)
    }
}

private extension KeyedDecodingContainer {
    func decodeOptionalString(_ preferred: Key, fallback: Key) throws -> String? {
        try decodeIfPresent(String.self, forKey: preferred)
            ?? decodeIfPresent(String.self, forKey: fallback)
    }
}

private func sanitizedMarooAnchorMessage(_ message: String) -> String {
    let scalars = message.unicodeScalars.map { scalar -> Character in
        if CharacterSet.newlines.union(.controlCharacters).contains(scalar) {
            return " "
        }
        return Character(scalar)
    }
    let collapsed = String(scalars)
        .split(separator: " ", omittingEmptySubsequences: true)
        .joined(separator: " ")
    return collapsed.isEmpty ? "maroo testnet request anchor submission failed" : collapsed
}
