import Foundation

/// Target-side verifier for signed App-to-App MCP requests.
///
/// This intentionally verifies only the signed request trust object: target
/// policy, caller/signer binding, payload hash, and cryptographic signature.
/// Replay, consent, delegated budget, and execution policy stay in the target
/// invocation layer.
public struct MeshSignedMCPRequestVerifier: Sendable {
    public let policy: MeshTargetPolicy
    public let trust: MeshSenderTrust

    public init(policy: MeshTargetPolicy, trust: MeshSenderTrust) {
        self.policy = policy
        self.trust = trust
    }

    public func verify(_ request: MeshRequest) throws {
        try MeshTarget.validate(request, policy: policy)
        if request.caller.appId != trust.callerAppId { throw MeshKitValidationError.trustedCallerMismatch }
        if request.caller.bundleId != trust.callerBundleId { throw MeshKitValidationError.callerBundleClaimMismatch }
        if let expectedKeyId = trust.requestSigningKeyId, request.caller.publicKeyId != expectedKeyId {
            throw MeshKitValidationError.signatureMismatch("caller publicKeyId must match expected request signer")
        }
        if let expectedAlgorithm = trust.requestSigningAlgorithm, request.signature.algorithm != expectedAlgorithm {
            throw MeshKitValidationError.signatureMismatch("request signing algorithm mismatch")
        }
        if let expectedKeyId = trust.requestSigningKeyId, request.signature.keyId != expectedKeyId {
            throw MeshKitValidationError.signatureMismatch("request signing key id mismatch")
        }
        try MeshTarget.verifyPayloadHash(request)
        try MeshTarget.verifyRequiredSignature(request, trust: trust)
    }
}

/// Demo adapter for the DailyMart grocery target. The signer remains provider
/// neutral: DailyMart expects the Hermes/agent request signer from OCG trust
/// metadata, not a maroo-specific chain proof.
public struct DailyMartSignedMCPRequestVerifier: Sendable {
    public let verifier: MeshSignedMCPRequestVerifier
    public let payloadHashValidator: DailyMartRequestPayloadHashValidator

    public init(expectedHermesAgentSigner trust: MeshSenderTrust) throws {
        self.payloadHashValidator = DailyMartRequestPayloadHashValidator()
        self.verifier = MeshSignedMCPRequestVerifier(
            policy: MeshTargetPolicy(
                allowedCallerAppId: "app.hermes-chat",
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials"
            ),
            trust: trust
        )
    }

    public func verify(_ request: MeshRequest) throws {
        try payloadHashValidator.validate(request)
        try verifier.verify(request)
    }
}

/// DailyMart pre-execution guard for signed App-to-App MCP requests.
///
/// DailyMart must reject malformed, tampered, stale, or replayed requests
/// before request anchoring, delegated wallet authorization, or OKRW payment
/// execution is attempted. Wallet policy validation is exposed as a second
/// target-side step so maroo anchoring and payment proofs can augment the
/// accepted request later, but cannot replace this signed MCP trust object.
public struct DailyMartPreExecutionMCPGuard: Sendable {
    public let signedRequestVerifier: DailyMartSignedMCPRequestVerifier
    public let freshnessStore: DailyMartRequestNonceFreshnessStore
    public let consentGuard: DailyMartPreExecutionConsentGuard?
    public let walletPolicyGuard: DailyMartPreExecutionWalletPolicyGuard?

    public init(
        expectedHermesAgentSigner trust: MeshSenderTrust,
        freshnessStore: DailyMartRequestNonceFreshnessStore = DailyMartRequestNonceFreshnessStore(),
        consentGuard: DailyMartPreExecutionConsentGuard? = nil,
        walletPolicyGuard: DailyMartPreExecutionWalletPolicyGuard? = nil
    ) throws {
        self.signedRequestVerifier = try DailyMartSignedMCPRequestVerifier(expectedHermesAgentSigner: trust)
        self.freshnessStore = freshnessStore
        self.consentGuard = consentGuard
        self.walletPolicyGuard = walletPolicyGuard
    }

    public init(
        signedRequestVerifier: DailyMartSignedMCPRequestVerifier,
        freshnessStore: DailyMartRequestNonceFreshnessStore = DailyMartRequestNonceFreshnessStore(),
        consentGuard: DailyMartPreExecutionConsentGuard? = nil,
        walletPolicyGuard: DailyMartPreExecutionWalletPolicyGuard? = nil
    ) {
        self.signedRequestVerifier = signedRequestVerifier
        self.freshnessStore = freshnessStore
        self.consentGuard = consentGuard
        self.walletPolicyGuard = walletPolicyGuard
    }

    @discardableResult
    public func acceptForPreExecution(
        _ request: MeshRequest,
        now: Date = Date()
    ) throws -> MeshRequest {
        try signedRequestVerifier.verify(request)
        let verifiedAt = ISO8601DateFormatter().string(from: now)
        _ = try (consentGuard ?? DailyMartPreExecutionConsentGuard()).requireApproved(
            request,
            verifiedAt: verifiedAt
        )
        _ = try freshnessStore.acceptFreshNonce(for: request, now: now)
        return request
    }

    @discardableResult
    public func acceptForWalletExecution(
        _ request: MeshRequest,
        executionKind: MeshAgentWalletExecutionKind = .payment,
        executionId: String? = nil,
        now: Date = Date(),
        verifiedAt: String? = nil
    ) throws -> DailyMartPreExecutionWalletPolicyGuardResult {
        let accepted = try acceptForPreExecution(request, now: now)
        let guardModule = try walletPolicyGuard ?? DailyMartPreExecutionWalletPolicyGuard()
        return try guardModule.evaluate(
            accepted,
            executionKind: executionKind,
            executionId: executionId,
            verifiedAt: verifiedAt ?? ISO8601DateFormatter().string(from: now)
        )
    }
}

/// DailyMart target-side nonce freshness gate for signed MCP requests.
///
/// This module is intentionally target-scoped instead of chain-provider
/// scoped: the nonce belongs to the app-to-app signed MCP trust object, while
/// anchoring and payment proofs only augment the verified request.
public final class DailyMartRequestNonceFreshnessStore: @unchecked Sendable {
    private let replayCache: MeshReplayCache
    private let nonceShapeValidator: DailyMartRequestNonceShapeValidator
    private let expirationValidator: DailyMartRequestNonceExpirationValidator

    public init(
        replayCache: MeshReplayCache = MeshReplayCache(),
        nonceShapeValidator: DailyMartRequestNonceShapeValidator = DailyMartRequestNonceShapeValidator(),
        expirationValidator: DailyMartRequestNonceExpirationValidator = DailyMartRequestNonceExpirationValidator()
    ) {
        self.replayCache = replayCache
        self.nonceShapeValidator = nonceShapeValidator
        self.expirationValidator = expirationValidator
    }

    @discardableResult
    public func acceptFreshNonce(
        for request: MeshRequest,
        now: Date = Date()
    ) throws -> String {
        try nonceShapeValidator.validate(request.nonce)
        try expirationValidator.validate(request, now: now)
        let scope = Self.freshnessScope(for: request)
        guard replayCache.acceptOnce(scope: scope, nonce: request.nonce) else {
            throw MeshKitValidationError.replayDetected(request.nonce)
        }
        return request.nonce
    }

    public static func freshnessScope(for request: MeshRequest) -> String {
        [
            "dailymart",
            request.caller.appId,
            request.caller.bundleId,
            request.target.targetBundleId,
            request.target.capabilityId
        ].joined(separator: ":")
    }
}

/// DailyMart target-side nonce shape gate for signed MCP requests.
///
/// The signed request nonce is an app-to-app trust primitive, so DailyMart
/// validates its shape before timestamp freshness, replay reservation,
/// anchoring, wallet authorization, or OKRW execution can observe it.
public struct DailyMartRequestNonceShapeValidator: Sendable {
    public let minimumLength: Int
    public let maximumLength: Int

    public init(minimumLength: Int = 16, maximumLength: Int = 128) {
        self.minimumLength = minimumLength
        self.maximumLength = maximumLength
    }

    public func validate(_ nonce: String) throws {
        try Self.validate(
            nonce,
            minimumLength: minimumLength,
            maximumLength: maximumLength
        )
    }

    public static func validate(
        _ nonce: String,
        minimumLength: Int = 16,
        maximumLength: Int = 128
    ) throws {
        guard nonce.count >= minimumLength, nonce.count <= maximumLength else {
            throw MeshKitValidationError.invalidSecurityField("nonce")
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard nonce.rangeOfCharacter(from: allowed.inverted) == nil else {
            throw MeshKitValidationError.invalidSecurityField("nonce")
        }
    }
}

/// DailyMart target-side nonce expiration gate for signed MCP requests.
///
/// Expiration is evaluated from the signed request timestamp so every saved
/// grant call must present a current signed MCP request with a fresh nonce.
public struct DailyMartRequestNonceExpirationValidator: Sendable {
    public let maxAgeSeconds: TimeInterval

    public init(maxAgeSeconds: TimeInterval = 300) {
        self.maxAgeSeconds = maxAgeSeconds
    }

    public func validate(_ request: MeshRequest, now: Date = Date()) throws {
        try Self.validate(request, maxAgeSeconds: maxAgeSeconds, now: now)
    }

    public static func validate(
        _ request: MeshRequest,
        maxAgeSeconds: TimeInterval = 300,
        now: Date = Date()
    ) throws {
        guard let timestamp = ISO8601DateFormatter().date(from: request.timestamp) else {
            throw MeshKitValidationError.staleTimestamp
        }
        if abs(timestamp.timeIntervalSince(now)) > maxAgeSeconds {
            throw MeshKitValidationError.staleTimestamp
        }
    }
}

/// DailyMart target-side request payload hash validator.
///
/// DailyMart exposes this separately from signature verification so its MCP
/// invocation pipeline can fail closed on request body tampering before policy
/// anchoring, wallet authorization, or OKRW execution is attempted.
public struct DailyMartRequestPayloadHashValidator: Sendable {
    public init() {}

    public func validate(_ request: MeshRequest) throws {
        try Self.validate(request)
    }

    public static func validate(_ request: MeshRequest) throws {
        try MeshTarget.verifyPayloadHash(request)
    }

    public static func expectedPayloadHash(for payload: [String: String]) -> MeshPayloadHash {
        MeshPayloadHash(value: MeshRequest.sha256HexForPayload(payload))
    }

    public static func expectedPayloadHash(for request: MeshRequest) -> MeshPayloadHash {
        MeshRequestPayloadHasher.hash(for: request)
    }
}
