import CryptoKit
import Foundation

public final class MeshReplayCache: @unchecked Sendable {
    private var accepted = Set<String>()
    private let lock = NSLock()

    public init() {}

    public func acceptOnce(scope: String, nonce: String) -> Bool {
        let key = "\(scope):\(nonce)"
        lock.lock()
        defer { lock.unlock() }
        if accepted.contains(key) { return false }
        accepted.insert(key)
        return true
    }
}

public enum MeshTarget {
    public static func validate(_ request: MeshRequest, policy: MeshTargetPolicy) throws {
        try validateRequestEnvelope(request)
        if request.caller.appId != policy.allowedCallerAppId { throw MeshKitValidationError.callerIdentityMismatch }
        if request.target.targetBundleId != policy.targetBundleId { throw MeshKitValidationError.targetIdentityMismatch }
        if request.target.capabilityId != policy.capabilityId { throw MeshKitValidationError.unsupportedCapability }
    }

    public static func validateSecure(
        request: MeshRequest,
        policy: MeshTargetPolicy,
        trust: MeshSenderTrust,
        observedCallerBundleId: String?,
        replayCache: MeshReplayCache,
        maxAgeSeconds: TimeInterval = 300
    ) throws {
        try validate(request, policy: policy)
        if request.caller.appId != trust.callerAppId { throw MeshKitValidationError.trustedCallerMismatch }
        if request.caller.bundleId != trust.callerBundleId { throw MeshKitValidationError.callerBundleClaimMismatch }
        guard let observedCallerBundleId, !observedCallerBundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeshKitValidationError.observedCallerBundleRequired
        }
        if observedCallerBundleId != trust.callerBundleId { throw MeshKitValidationError.observedCallerBundleMismatch }
        if trust.teamId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MeshKitValidationError.teamIdRequired }
        try verifyPayloadHash(request)
        try verifyFreshTimestamp(request, maxAgeSeconds: maxAgeSeconds)
        try verifyIfConfigured(request, trust: trust)
        if !replayCache.acceptOnce(scope: "\(request.caller.appId):\(trust.callerBundleId)", nonce: request.nonce) {
            throw MeshKitValidationError.replayDetected(request.nonce)
        }
    }

    public static func validatePublicMesh(
        request: MeshRequest,
        policy: MeshTargetPolicy,
        trust: MeshSenderTrust,
        invocationPolicy: MeshInvocationPolicy,
        observedCallerBundleId: String?,
        replayCache: MeshReplayCache,
        maxAgeSeconds: TimeInterval = 300
    ) throws -> MeshAuditEvent {
        try validateSecure(
            request: request,
            policy: policy,
            trust: trust,
            observedCallerBundleId: observedCallerBundleId,
            replayCache: replayCache,
            maxAgeSeconds: maxAgeSeconds
        )
        try invocationPolicy.validateBeforeExecution(request: request, trust: trust)
        try verifyRequiredSignature(request, trust: trust)
        return MeshAuditEvent.accepted(request, policy: invocationPolicy)
    }

    public static func verifyPayloadHash(_ request: MeshRequest) throws {
        guard request.payloadHash.algorithm.lowercased() == "sha256" else { throw MeshKitValidationError.unsupportedPayloadHashAlgorithm }
        let actual = MeshRequest.sha256HexForPayload(request.payload)
        if actual.lowercased() != request.payloadHash.value.lowercased() { throw MeshKitValidationError.payloadHashMismatch }
    }

    public static func verifyFreshTimestamp(_ request: MeshRequest, maxAgeSeconds: TimeInterval) throws {
        guard let timestamp = ISO8601DateFormatter().date(from: request.timestamp) else { throw MeshKitValidationError.staleTimestamp }
        if abs(timestamp.timeIntervalSinceNow) > maxAgeSeconds { throw MeshKitValidationError.staleTimestamp }
    }

    public static func verifyIfConfigured(_ request: MeshRequest, trust: MeshSenderTrust) throws {
        if let expectedAlgorithm = trust.requestSigningAlgorithm, expectedAlgorithm != request.signature.algorithm {
            throw MeshKitValidationError.signatureMismatch("request signing algorithm mismatch")
        }
        if let expectedKeyId = trust.requestSigningKeyId, expectedKeyId != request.signature.keyId {
            throw MeshKitValidationError.signatureMismatch("request signing key id mismatch")
        }
        guard trust.requestSigningAlgorithm != nil || trust.requestSigningKeyId != nil || trust.publicKey != nil else { return }
        try verifyRequiredSignature(request, trust: trust)
    }

    public static func verifyRequiredSignature(_ request: MeshRequest, trust: MeshSenderTrust) throws {
        try validateSigningEnvelope(request)
        if request.signature.keyId.isEmpty || request.signature.value.isEmpty { throw MeshKitValidationError.signatureRequired }
        guard request.signature.algorithm == "Ed25519" else {
            throw MeshKitValidationError.signatureMismatch("unsupported request signing algorithm: \(request.signature.algorithm)")
        }
        guard let publicKey = trust.publicKey, let publicKeyData = Data(base64Encoded: publicKey), !publicKeyData.isEmpty else {
            throw MeshKitValidationError.signatureRequired
        }
        guard let signatureData = Data(base64Encoded: request.signature.value), !signatureData.isEmpty else {
            throw MeshKitValidationError.signatureMismatch("request signature is not valid base64")
        }
        do {
            let verifier = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
            if !verifier.isValidSignature(signatureData, for: request.signingInputData()) {
                throw MeshKitValidationError.signatureMismatch("invalid request signature")
            }
        } catch let error as MeshKitValidationError {
            throw error
        } catch {
            throw MeshKitValidationError.signatureMismatch("invalid request signing public key")
        }
    }

    public static func validateRequestEnvelope(_ request: MeshRequest) throws {
        try requireSecurityField("requestId", request.requestId)
        try requireSecurityField("caller.appId", request.caller.appId)
        try requireSecurityField("caller.installId", request.caller.installId)
        try requireSecurityField("caller.bundleId", request.caller.bundleId)
        try requireSecurityField("caller.publicKeyId", request.caller.publicKeyId)
        try requireSecurityField("target.targetBundleId", request.target.targetBundleId)
        try requireSecurityField("target.capabilityId", request.target.capabilityId)
        try requireSecurityField("target.version", request.target.version)
        try requireSecurityField("payloadHash.algorithm", request.payloadHash.algorithm)
        try requireSecurityField("payloadHash.value", request.payloadHash.value)
        try requireSecurityField("timestamp", request.timestamp)
        try requireSecurityField("nonce", request.nonce)
        try requireHexSha256(request.payloadHash.value)
        try validateSigningEnvelope(request)
    }

    private static func validateSigningEnvelope(_ request: MeshRequest) throws {
        if !request.signature.algorithm.isEmpty { try requireSecurityField("signature.algorithm", request.signature.algorithm) }
        if !request.signature.keyId.isEmpty { try requireSecurityField("signature.keyId", request.signature.keyId) }
    }

    private static func requireSecurityField(_ field: String, _ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == value else { throw MeshKitValidationError.invalidSecurityField(field) }
        guard value.rangeOfCharacter(from: CharacterSet.newlines.union(.controlCharacters)) == nil else {
            throw MeshKitValidationError.invalidSecurityField(field)
        }
    }

    private static func requireHexSha256(_ value: String) throws {
        guard value.count == 64,
              value.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdefABCDEF").inverted) == nil
        else {
            throw MeshKitValidationError.invalidSecurityField("payloadHash.value")
        }
    }
}
