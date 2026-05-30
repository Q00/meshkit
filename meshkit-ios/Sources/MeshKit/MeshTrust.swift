import Foundation

public struct MeshTargetPolicy: Codable, Equatable, Sendable {
    public let allowedCallerAppId: String
    public let targetBundleId: String
    public let capabilityId: String

    public init(allowedCallerAppId: String, targetBundleId: String, capabilityId: String) {
        self.allowedCallerAppId = allowedCallerAppId
        self.targetBundleId = targetBundleId
        self.capabilityId = capabilityId
    }
}

public struct MeshSenderTrust: Codable, Equatable, Sendable {
    public let callerAppId: String
    public let callerBundleId: String
    public let teamId: String
    public let requestSigningAlgorithm: String?
    public let requestSigningKeyId: String?
    public let publicKey: String?

    public init(
        callerAppId: String,
        callerBundleId: String,
        teamId: String,
        requestSigningAlgorithm: String? = nil,
        requestSigningKeyId: String? = nil,
        publicKey: String? = nil
    ) {
        self.callerAppId = callerAppId
        self.callerBundleId = callerBundleId
        self.teamId = teamId
        self.requestSigningAlgorithm = requestSigningAlgorithm
        self.requestSigningKeyId = requestSigningKeyId
        self.publicKey = publicKey
    }
}

public struct MeshInvocationPolicy: Codable, Equatable, Sendable {
    public let risk: String
    public let consent: String
    public let userApproved: Bool
    public let registrySignatureVerified: Bool
    public let approvedBudget: Decimal?
    public let productionEnabled: Bool
    public let killSwitchReason: String?

    public init(
        risk: String,
        consent: String,
        userApproved: Bool,
        registrySignatureVerified: Bool,
        approvedBudget: Decimal? = nil,
        productionEnabled: Bool = true,
        killSwitchReason: String? = nil
    ) {
        self.risk = risk
        self.consent = consent
        self.userApproved = userApproved
        self.registrySignatureVerified = registrySignatureVerified
        self.approvedBudget = approvedBudget
        self.productionEnabled = productionEnabled
        self.killSwitchReason = killSwitchReason
    }

    public func validateBeforeExecution(request: MeshRequest, trust: MeshSenderTrust) throws {
        if !productionEnabled { throw MeshKitValidationError.productionDisabled(killSwitchReason ?? "production invocation disabled") }
        if !registrySignatureVerified { throw MeshKitValidationError.registryTrustRequired }
        if requiresPerInvocationConsent && !userApproved { throw MeshKitValidationError.consentRequired(risk) }
        if risk == "spend:money" { try validateBudget(request: request) }
        if request.signature.keyId.isEmpty || request.signature.value.isEmpty { throw MeshKitValidationError.signatureRequired }
        if let expectedAlgorithm = trust.requestSigningAlgorithm, expectedAlgorithm != request.signature.algorithm {
            throw MeshKitValidationError.signatureMismatch("request signing algorithm mismatch")
        }
        if let expectedKeyId = trust.requestSigningKeyId, expectedKeyId != request.signature.keyId {
            throw MeshKitValidationError.signatureMismatch("request signing key id mismatch")
        }
    }

    public var requiresPerInvocationConsent: Bool {
        ["write:user_content", "send:external", "spend:money", "identity", "location"].contains(risk)
    }

    private func validateBudget(request: MeshRequest) throws {
        guard let approvedBudget else { throw MeshKitValidationError.budgetRequired }
        guard let raw = request.payload["budget_krw"], let requested = Decimal(string: raw), requested >= 0 else {
            throw MeshKitValidationError.budgetRequired
        }
        if requested > approvedBudget { throw MeshKitValidationError.budgetExceeded }
    }
}

public struct MeshAuditEvent: Codable, Equatable, Sendable {
    public let requestId: String
    public let callerAppId: String
    public let targetBundleId: String
    public let capabilityId: String
    public let risk: String
    public let consent: String
    public let status: String

    public static func accepted(_ request: MeshRequest, policy: MeshInvocationPolicy) -> MeshAuditEvent {
        MeshAuditEvent(
            requestId: request.requestId,
            callerAppId: request.caller.appId,
            targetBundleId: request.target.targetBundleId,
            capabilityId: request.target.capabilityId,
            risk: policy.risk,
            consent: policy.consent,
            status: "accepted"
        )
    }
}

public enum MeshKitValidationError: Error, Equatable, CustomStringConvertible {
    case invalidEncoding(String)
    case callerIdentityMismatch
    case targetIdentityMismatch
    case unsupportedCapability
    case trustedCallerMismatch
    case callerBundleClaimMismatch
    case observedCallerBundleRequired
    case observedCallerBundleMismatch
    case teamIdRequired
    case payloadHashMismatch
    case unsupportedPayloadHashAlgorithm
    case staleTimestamp
    case replayDetected(String)
    case signatureRequired
    case signatureMismatch(String)
    case registryTrustRequired
    case consentRequired(String)
    case budgetRequired
    case budgetExceeded
    case productionDisabled(String)
    case invalidSecurityField(String)
    case receiptCorrelationMismatch

    public var description: String {
        switch self {
        case .invalidEncoding(let reason): return "invalid MeshKit encoding: \(reason)"
        case .callerIdentityMismatch: return "caller identity mismatch"
        case .targetIdentityMismatch: return "target identity mismatch"
        case .unsupportedCapability: return "unsupported capability"
        case .trustedCallerMismatch: return "trusted caller app id mismatch"
        case .callerBundleClaimMismatch: return "caller bundle claim mismatch"
        case .observedCallerBundleRequired: return "observed caller bundle is required"
        case .observedCallerBundleMismatch: return "observed caller bundle mismatch"
        case .teamIdRequired: return "iOS team id trust metadata is required"
        case .payloadHashMismatch: return "payload hash mismatch"
        case .unsupportedPayloadHashAlgorithm: return "unsupported payload hash algorithm"
        case .staleTimestamp: return "stale request timestamp"
        case .replayDetected(let nonce): return "replay detected for nonce: \(nonce)"
        case .signatureRequired: return "request signature is required"
        case .signatureMismatch(let reason): return reason
        case .registryTrustRequired: return "registry signature verification is required"
        case .consentRequired(let risk): return "user consent required for risk: \(risk)"
        case .budgetRequired: return "approved budget required for spend:money"
        case .budgetExceeded: return "requested spend exceeds approved budget"
        case .productionDisabled(let reason): return "production invocation disabled: \(reason)"
        case .invalidSecurityField(let field): return "invalid security field: \(field)"
        case .receiptCorrelationMismatch: return "target receipt does not match a pending request token"
        }
    }
}
