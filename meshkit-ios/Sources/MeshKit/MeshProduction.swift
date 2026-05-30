import CryptoKit
import Foundation

/// High-level production target facade: secure defaults, one validation call.
/// Keep low-level MeshTarget APIs available for advanced integrations, but steer app
/// developers toward this wrapper so they do not forget caller binding, payload hash,
/// timestamp, replay, request signature, consent, budget, and audit checks.
public struct MeshProductionTarget: Sendable {
    public let policy: MeshTargetPolicy
    public let trust: MeshSenderTrust
    public let invocationPolicy: MeshInvocationPolicy
    public let maxAgeSeconds: TimeInterval
    private let replayCache: MeshReplayCache

    public init(
        policy: MeshTargetPolicy,
        trust: MeshSenderTrust,
        invocationPolicy: MeshInvocationPolicy,
        replayCache: MeshReplayCache,
        maxAgeSeconds: TimeInterval = 300
    ) throws {
        try Self.validateProductionTrust(policy: policy, trust: trust, invocationPolicy: invocationPolicy, maxAgeSeconds: maxAgeSeconds)
        self.policy = policy
        self.trust = trust
        self.invocationPolicy = invocationPolicy
        self.replayCache = replayCache
        self.maxAgeSeconds = maxAgeSeconds
    }

    private static func validateProductionTrust(
        policy: MeshTargetPolicy,
        trust: MeshSenderTrust,
        invocationPolicy: MeshInvocationPolicy,
        maxAgeSeconds: TimeInterval
    ) throws {
        if maxAgeSeconds <= 0 || maxAgeSeconds > 300 { throw MeshKitValidationError.staleTimestamp }
        if policy.allowedCallerAppId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MeshKitValidationError.callerIdentityMismatch }
        if policy.targetBundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MeshKitValidationError.targetIdentityMismatch }
        if policy.capabilityId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MeshKitValidationError.unsupportedCapability }
        if trust.callerAppId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MeshKitValidationError.trustedCallerMismatch }
        guard policy.allowedCallerAppId == trust.callerAppId else {
            throw MeshKitValidationError.signatureMismatch("production target trust callerAppId must match policy allowedCallerAppId")
        }
        if trust.callerBundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MeshKitValidationError.callerBundleClaimMismatch }
        guard trust.callerBundleId != policy.targetBundleId else {
            throw MeshKitValidationError.signatureMismatch("production target trust callerBundleId must be distinct from targetBundleId")
        }
        if trust.teamId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MeshKitValidationError.teamIdRequired }
        if !invocationPolicy.productionEnabled {
            throw MeshKitValidationError.productionDisabled(invocationPolicy.killSwitchReason ?? "production invocation disabled")
        }
        guard trust.requestSigningAlgorithm == "Ed25519",
              let keyId = trust.requestSigningKeyId, !keyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let publicKey = trust.publicKey, !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw MeshKitValidationError.signatureRequired
        }
        if !invocationPolicy.registrySignatureVerified { throw MeshKitValidationError.registryTrustRequired }
        if invocationPolicy.requiresPerInvocationConsent && !invocationPolicy.userApproved {
            throw MeshKitValidationError.consentRequired(invocationPolicy.risk)
        }
        if invocationPolicy.risk == "spend:money", invocationPolicy.approvedBudget == nil {
            throw MeshKitValidationError.signatureMismatch("spend:money production targets require an explicit approved budget")
        }
    }

    public func validate(_ request: MeshRequest, observedCallerBundleId: String?) throws -> MeshAuditEvent {
        try MeshTarget.validatePublicMesh(
            request: request,
            policy: policy,
            trust: trust,
            invocationPolicy: invocationPolicy,
            observedCallerBundleId: observedCallerBundleId,
            replayCache: replayCache,
            maxAgeSeconds: maxAgeSeconds
        )
    }
}

/// Production caller-side signer helper.
/// The caller supplies a platform-protected private key; MeshKit handles payload hash,
/// deterministic signing input, signature envelope, and request construction.
public struct MeshRequestSigner: Sendable {
    public let algorithm: String
    public let keyId: String
    private let signData: @Sendable (Data) throws -> Data

    public init(algorithm: String, keyId: String, signData: @escaping @Sendable (Data) throws -> Data) {
        self.algorithm = algorithm
        self.keyId = keyId
        self.signData = signData
    }

    public static func ed25519(keyId: String, privateKey: Curve25519.Signing.PrivateKey) -> MeshRequestSigner {
        MeshRequestSigner(algorithm: "Ed25519", keyId: keyId) { data in
            try privateKey.signature(for: data)
        }
    }

    public func sign(_ request: MeshRequest) throws -> MeshRequest {
        let signature = try signData(request.signingInputData()).base64EncodedString()
        return MeshRequest(
            requestId: request.requestId,
            caller: request.caller,
            target: request.target,
            payload: request.payload,
            payloadHash: request.payloadHash,
            nonce: request.nonce,
            timestamp: request.timestamp,
            signature: MeshSignature(algorithm: algorithm, keyId: keyId, value: signature)
        )
    }
}

/// Easy caller-side builder: no manual hash/signature glue in app code.
public struct MeshSignedRequestBuilder: Sendable {
    public let caller: MeshIdentity
    public let target: MeshCapability
    public let signer: MeshRequestSigner

    public init(caller: MeshIdentity, target: MeshCapability, signer: MeshRequestSigner) {
        self.caller = caller
        self.target = target
        self.signer = signer
    }

    public func makeRequest(
        requestId: String,
        payload: [String: String],
        nonce: String = UUID().uuidString,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) throws -> MeshRequest {
        guard caller.publicKeyId == signer.keyId else {
            throw MeshKitValidationError.signatureMismatch("caller publicKeyId must match signer keyId")
        }
        let unsigned = MeshRequest(
            requestId: requestId,
            caller: caller,
            target: target,
            payload: payload,
            nonce: nonce,
            timestamp: timestamp,
            signature: MeshSignature(algorithm: signer.algorithm, keyId: signer.keyId, value: "")
        )
        return try signer.sign(unsigned)
    }
}
