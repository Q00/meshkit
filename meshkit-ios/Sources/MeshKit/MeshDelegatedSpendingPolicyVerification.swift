import Foundation

public enum MeshDelegatedSpendingPolicyVerificationStatus: String, Codable, Equatable, Sendable {
    case approved
    case denied
}

public struct MeshDelegatedSpendingPolicyVerificationResult: Codable, Equatable, Sendable {
    public let policyId: String
    public let policyHash: MeshPayloadHash
    public let status: MeshDelegatedSpendingPolicyVerificationStatus
    public let reason: String?
    public let verifiedAt: String

    public init(
        policyId: String,
        policyHash: MeshPayloadHash,
        status: MeshDelegatedSpendingPolicyVerificationStatus,
        reason: String? = nil,
        verifiedAt: String
    ) throws {
        self.policyId = try MeshAgentWalletProviderMetadata.stableValue("policyId", policyId)
        self.policyHash = policyHash
        self.status = status
        self.reason = try reason.map { try MeshAgentWalletProviderMetadata.stableValue("reason", $0) }
        self.verifiedAt = try MeshAgentWalletProviderMetadata.stableValue("verifiedAt", verifiedAt)
        try validate()
    }

    public func validate() throws {
        try MeshAgentWalletProviderMetadata.validateIdentifier("policyId", policyId)
        try validateAgentWalletHash("policyHash", policyHash)
        try MeshAgentWalletProviderMetadata.validateIdentifier("verifiedAt", verifiedAt)
        switch status {
        case .approved:
            guard reason == nil else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("reason")
            }
        case .denied:
            guard let reason, !reason.isEmpty else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("reason")
            }
            try MeshAgentWalletProviderMetadata.validateIdentifier("reason", reason)
        }
    }
}

public struct MeshDelegatedSpendingPolicyVerifier: Sendable {
    public let expectedPolicy: MeshAgentWalletDelegatedSpendingPolicy

    public init(expectedPolicy: MeshAgentWalletDelegatedSpendingPolicy) throws {
        try expectedPolicy.validate()
        self.expectedPolicy = expectedPolicy
    }

    public func verify(
        policyId requestPolicyId: String,
        policyHash requestPolicyHash: MeshPayloadHash,
        verifiedAt: String
    ) throws -> MeshDelegatedSpendingPolicyVerificationResult {
        let normalizedPolicyId = try MeshAgentWalletProviderMetadata.stableValue("policyId", requestPolicyId)
        try validateAgentWalletHash("policyHash", requestPolicyHash)
        let normalizedVerifiedAt = try MeshAgentWalletProviderMetadata.stableValue("verifiedAt", verifiedAt)

        if normalizedPolicyId != expectedPolicy.policyId {
            return try MeshDelegatedSpendingPolicyVerificationResult(
                policyId: normalizedPolicyId,
                policyHash: requestPolicyHash,
                status: .denied,
                reason: "policy-id-mismatch",
                verifiedAt: normalizedVerifiedAt
            )
        }
        if requestPolicyHash != expectedPolicy.policyHash {
            return try MeshDelegatedSpendingPolicyVerificationResult(
                policyId: normalizedPolicyId,
                policyHash: requestPolicyHash,
                status: .denied,
                reason: "policy-hash-mismatch",
                verifiedAt: normalizedVerifiedAt
            )
        }
        return try MeshDelegatedSpendingPolicyVerificationResult(
            policyId: normalizedPolicyId,
            policyHash: requestPolicyHash,
            status: .approved,
            verifiedAt: normalizedVerifiedAt
        )
    }
}

public struct DailyMartMerchantScopeValidator: Sendable {
    public let authorizedMerchantScope: String

    public init(authorizedMerchantScope: String = DailyMartDelegatedSpendingPolicy.merchantScope) throws {
        self.authorizedMerchantScope = try MeshAgentWalletProviderMetadata.stableValue(
            "authorizedMerchantScope",
            authorizedMerchantScope
        )
        try MeshAgentWalletProviderMetadata.validateIdentifier("authorizedMerchantScope", self.authorizedMerchantScope)
    }

    public func validate(_ request: MeshRequest) throws {
        guard let merchantScope = request.payload["merchantScope"] else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("merchantScope")
        }
        let normalizedMerchantScope = try MeshAgentWalletProviderMetadata.stableValue(
            "merchantScope",
            merchantScope
        )
        guard normalizedMerchantScope == authorizedMerchantScope else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("merchantScope")
        }
    }
}

public struct DailyMartCapabilityScopeValidator: Sendable {
    public let consentGrantId: String
    public let consentedCapabilities: Set<String>

    public init(
        consentGrantId: String = DailyMartDelegatedSpendingPolicy.consentGrantId,
        consentedCapabilities: Set<String> = [DailyMartDelegatedSpendingPolicy.capabilityScope]
    ) throws {
        self.consentGrantId = try MeshAgentWalletProviderMetadata.stableValue(
            "consentGrantId",
            consentGrantId
        )
        try MeshAgentWalletProviderMetadata.validateIdentifier("consentGrantId", self.consentGrantId)
        guard !consentedCapabilities.isEmpty else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("capabilityScope")
        }
        self.consentedCapabilities = try Set(consentedCapabilities.map { capability in
            let normalizedCapability = try MeshAgentWalletProviderMetadata.stableValue(
                "capabilityScope",
                capability
            )
            try MeshAgentWalletProviderMetadata.validateIdentifier("capabilityScope", normalizedCapability)
            return normalizedCapability
        })
    }

    public init(consentGrant: DailyMartConsentGrant) throws {
        try self.init(
            consentGrantId: consentGrant.consentGrantId,
            consentedCapabilities: [consentGrant.capabilityId]
        )
    }

    public func validate(
        requestedCapabilities: [String],
        consentGrantId requestConsentGrantId: String
    ) throws {
        let normalizedConsentGrantId = try MeshAgentWalletProviderMetadata.stableValue(
            "consentGrantId",
            requestConsentGrantId
        )
        guard normalizedConsentGrantId == consentGrantId else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("consentGrantId")
        }

        var requested = Set<String>()
        for capability in requestedCapabilities {
            let normalizedCapability = try MeshAgentWalletProviderMetadata.stableValue(
                "capabilityScope",
                capability
            )
            try MeshAgentWalletProviderMetadata.validateIdentifier("capabilityScope", normalizedCapability)
            requested.insert(normalizedCapability)
        }
        guard !requested.isEmpty else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("capabilityScope")
        }
        guard requested.isSubset(of: consentedCapabilities) else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("capabilityScope")
        }
    }

    public func validate(_ request: MeshRequest) throws {
        let requestedCapability = try MeshAgentWalletProviderMetadata.stableValue(
            "target.capabilityId",
            request.target.capabilityId
        )
        guard consentedCapabilities.contains(requestedCapability) else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("capabilityScope")
        }
        guard let capabilityScope = request.payload["capabilityScope"] else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("capabilityScope")
        }
        let normalizedCapabilityScope = try MeshAgentWalletProviderMetadata.stableValue(
            "capabilityScope",
            capabilityScope
        )
        guard normalizedCapabilityScope == requestedCapability,
              consentedCapabilities.contains(normalizedCapabilityScope) else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("capabilityScope")
        }
        guard let requestConsentGrantId = request.payload["consentGrantId"] else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("consentGrantId")
        }
        let normalizedConsentGrantId = try MeshAgentWalletProviderMetadata.stableValue(
            "consentGrantId",
            requestConsentGrantId
        )
        try validate(
            requestedCapabilities: [requestedCapability, normalizedCapabilityScope],
            consentGrantId: normalizedConsentGrantId
        )
    }
}

public struct DailyMartConsentGrant: Codable, Equatable, Sendable {
    public let consentGrantId: String
    public let callerAppId: String
    public let callerBundleId: String
    public let requestContextSubject: String
    public let walletSessionId: String
    public let principalId: String
    public let targetBundleId: String
    public let capabilityId: String
    public let merchantScope: String
    public let policyId: String
    public let signerKeyId: String?
    public let walletAddress: String?
    public let startsAt: String?
    public let expiresAt: String
    public let status: DailyMartConsentGrantStatus

    public init(
        consentGrantId: String,
        callerAppId: String,
        callerBundleId: String,
        requestContextSubject: String? = nil,
        walletSessionId: String,
        principalId: String,
        targetBundleId: String,
        capabilityId: String,
        merchantScope: String,
        policyId: String,
        signerKeyId: String? = nil,
        walletAddress: String? = nil,
        startsAt: String? = nil,
        expiresAt: String,
        status: DailyMartConsentGrantStatus = .active
    ) throws {
        self.consentGrantId = try MeshAgentWalletProviderMetadata.stableValue("consentGrantId", consentGrantId)
        self.callerAppId = try MeshAgentWalletProviderMetadata.stableValue("callerAppId", callerAppId)
        self.callerBundleId = try MeshAgentWalletProviderMetadata.stableValue("callerBundleId", callerBundleId)
        self.requestContextSubject = try MeshAgentWalletProviderMetadata.stableValue("requestContextSubject", requestContextSubject ?? principalId)
        self.walletSessionId = try MeshAgentWalletProviderMetadata.stableValue("walletSessionId", walletSessionId)
        self.principalId = try MeshAgentWalletProviderMetadata.stableValue("principalId", principalId)
        self.targetBundleId = try MeshAgentWalletProviderMetadata.stableValue("targetBundleId", targetBundleId)
        self.capabilityId = try MeshAgentWalletProviderMetadata.stableValue("capabilityId", capabilityId)
        self.merchantScope = try MeshAgentWalletProviderMetadata.stableValue("merchantScope", merchantScope)
        self.policyId = try MeshAgentWalletProviderMetadata.stableValue("policyId", policyId)
        self.signerKeyId = try signerKeyId.map { try MeshAgentWalletProviderMetadata.stableValue("signerKeyId", $0) }
        self.walletAddress = try walletAddress.map { try MeshAgentWalletProviderMetadata.stableValue("walletAddress", $0) }
        self.startsAt = try startsAt.map { try MeshAgentWalletProviderMetadata.stableValue("startsAt", $0) }
        self.expiresAt = try MeshAgentWalletProviderMetadata.stableValue("expiresAt", expiresAt)
        self.status = status
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case consentGrantId
        case callerAppId
        case callerBundleId
        case requestContextSubject
        case walletSessionId
        case principalId
        case targetBundleId
        case capabilityId
        case merchantScope
        case policyId
        case signerKeyId
        case walletAddress
        case startsAt
        case expiresAt
        case status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            consentGrantId: container.decode(String.self, forKey: .consentGrantId),
            callerAppId: container.decode(String.self, forKey: .callerAppId),
            callerBundleId: container.decode(String.self, forKey: .callerBundleId),
            requestContextSubject: container.decodeIfPresent(String.self, forKey: .requestContextSubject),
            walletSessionId: container.decode(String.self, forKey: .walletSessionId),
            principalId: container.decode(String.self, forKey: .principalId),
            targetBundleId: container.decode(String.self, forKey: .targetBundleId),
            capabilityId: container.decode(String.self, forKey: .capabilityId),
            merchantScope: container.decode(String.self, forKey: .merchantScope),
            policyId: container.decode(String.self, forKey: .policyId),
            signerKeyId: container.decodeIfPresent(String.self, forKey: .signerKeyId),
            walletAddress: container.decodeIfPresent(String.self, forKey: .walletAddress),
            startsAt: container.decodeIfPresent(String.self, forKey: .startsAt),
            expiresAt: container.decode(String.self, forKey: .expiresAt),
            status: container.decodeIfPresent(DailyMartConsentGrantStatus.self, forKey: .status) ?? .active
        )
    }

    public func validate() throws {
        try MeshAgentWalletProviderMetadata.validateIdentifier("consentGrantId", consentGrantId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("callerAppId", callerAppId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("callerBundleId", callerBundleId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("requestContextSubject", requestContextSubject)
        try MeshAgentWalletProviderMetadata.validateIdentifier("walletSessionId", walletSessionId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("principalId", principalId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("targetBundleId", targetBundleId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("capabilityId", capabilityId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("merchantScope", merchantScope)
        try MeshAgentWalletProviderMetadata.validateIdentifier("policyId", policyId)
        if let signerKeyId {
            try MeshAgentWalletProviderMetadata.validateIdentifier("signerKeyId", signerKeyId)
        }
        if let walletAddress {
            try MeshAgentWalletProviderMetadata.validateIdentifier("walletAddress", walletAddress)
        }
        if let startsAt {
            try MeshAgentWalletProviderMetadata.validateIdentifier("startsAt", startsAt)
            guard ISO8601DateFormatter().date(from: startsAt) != nil else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("startsAt")
            }
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("expiresAt", expiresAt)
        guard let expirationDate = ISO8601DateFormatter().date(from: expiresAt) else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("expiresAt")
        }
        if let startsAt, let startDate = ISO8601DateFormatter().date(from: startsAt) {
            guard startDate <= expirationDate else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("startsAt")
            }
        }
    }

    public func validityStatus(verifiedAt: String) throws -> DailyMartConsentGrantValidityStatus {
        guard let verifiedDate = ISO8601DateFormatter().date(from: verifiedAt) else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("verifiedAt")
        }
        if let startsAt, let startDate = ISO8601DateFormatter().date(from: startsAt), verifiedDate < startDate {
            return .notYetValid
        }
        guard let expirationDate = ISO8601DateFormatter().date(from: expiresAt) else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("expiresAt")
        }
        guard verifiedDate <= expirationDate else {
            return .expired
        }
        return .valid
    }
}

public enum DailyMartConsentGrantValidityStatus: String, Codable, Equatable, Sendable {
    case valid
    case expired
    case notYetValid = "not_yet_valid"
}

public enum DailyMartConsentGrantStatus: String, Codable, Equatable, Sendable {
    case active
    case revoked
}

public struct DailyMartConsentGrantVerifier: Sendable {
    public let grantsById: [String: DailyMartConsentGrant]

    public init(grants: [DailyMartConsentGrant]) throws {
        guard !grants.isEmpty else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("consentGrantId")
        }
        var indexed: [String: DailyMartConsentGrant] = [:]
        for grant in grants {
            try grant.validate()
            guard indexed[grant.consentGrantId] == nil else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("consentGrantId")
            }
            indexed[grant.consentGrantId] = grant
        }
        self.grantsById = indexed
    }

    public func verify(_ request: MeshRequest, verifiedAt: String) throws -> DailyMartConsentGrant {
        guard let requestConsentGrantId = request.payload["consentGrantId"] else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("consentGrantId")
        }
        let normalizedConsentGrantId = try MeshAgentWalletProviderMetadata.stableValue(
            "consentGrantId",
            requestConsentGrantId
        )
        guard let grant = grantsById[normalizedConsentGrantId] else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("consentGrantId.unknown")
        }
        guard grant.status == .active else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("consentGrantId.revoked")
        }
        switch try grant.validityStatus(verifiedAt: verifiedAt) {
        case .valid:
            break
        case .expired:
            throw MeshKitValidationError.invalidAgentWalletIdentity("consentGrantId.expired")
        case .notYetValid:
            throw MeshKitValidationError.invalidAgentWalletIdentity("consentGrantId.notYetValid")
        }
        guard let requestWalletSessionId = request.payload["walletSessionId"] else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("walletSessionId")
        }
        let normalizedWalletSessionId = try MeshAgentWalletProviderMetadata.stableValue(
            "walletSessionId",
            requestWalletSessionId
        )
        guard normalizedWalletSessionId == grant.walletSessionId else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("walletSessionId")
        }
        guard let requestPrincipalId = request.payload["principalId"] else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("principalId")
        }
        let normalizedPrincipalId = try MeshAgentWalletProviderMetadata.stableValue(
            "principalId",
            requestPrincipalId
        )
        guard normalizedPrincipalId == grant.principalId else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("principalId")
        }
        let normalizedRequestContextSubject = try Self.requestContextSubject(from: request)
        guard normalizedRequestContextSubject == grant.requestContextSubject else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("requestContextSubject")
        }
        guard let requestPolicyId = request.payload["policyId"] else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("missing-policy")
        }
        _ = try MeshAgentWalletProviderMetadata.stableValue(
            "policyId",
            requestPolicyId
        )
        guard request.caller.appId == grant.callerAppId,
              request.caller.bundleId == grant.callerBundleId,
              request.target.targetBundleId == grant.targetBundleId,
              request.target.capabilityId == grant.capabilityId,
              request.payload["merchantScope"] == grant.merchantScope else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("consentGrantId.context")
        }
        return grant
    }

    private static func requestContextSubject(from request: MeshRequest) throws -> String {
        let rawSubject = request.payload["requestContextSubject"]
            ?? request.payload["contextSubject"]
            ?? request.payload["subject"]
            ?? request.payload["principalId"]
        guard let rawSubject else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("requestContextSubject")
        }
        return try MeshAgentWalletProviderMetadata.stableValue("requestContextSubject", rawSubject)
    }

    public func verifyBoundRequest(
        _ request: MeshRequest,
        walletAddress requestWalletAddress: String,
        requestAnchorMetadata: MeshSignedRequestAnchorMetadata,
        verifiedAt: String
    ) throws -> DailyMartConsentGrant {
        let grant = try verify(request, verifiedAt: verifiedAt)
        guard let signerKeyId = grant.signerKeyId else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("signerKeyId")
        }
        guard request.signature.keyId == signerKeyId,
              request.caller.publicKeyId == signerKeyId else {
            throw MeshKitValidationError.signatureMismatch("consent grant signer binding mismatch")
        }
        guard let grantWalletAddress = grant.walletAddress else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("walletAddress")
        }
        let normalizedWalletAddress = try MeshAgentWalletProviderMetadata.stableValue(
            "walletAddress",
            requestWalletAddress
        )
        guard normalizedWalletAddress == grantWalletAddress else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("walletAddress")
        }
        try MeshRequestAnchorCanonicalization.validate(metadata: requestAnchorMetadata, boundTo: request)
        return grant
    }
}

public struct DailyMartMerchantConsentScopeValidator: Sendable {
    public let grantsById: [String: DailyMartConsentGrant]

    public init(grants: [DailyMartConsentGrant]) throws {
        guard !grants.isEmpty else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("consentGrantId")
        }
        var indexed: [String: DailyMartConsentGrant] = [:]
        for grant in grants {
            try grant.validate()
            guard indexed[grant.consentGrantId] == nil else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("consentGrantId")
            }
            indexed[grant.consentGrantId] = grant
        }
        self.grantsById = indexed
    }

    public func validate(
        _ request: MeshRequest,
        verifiedAt: String
    ) throws -> DailyMartConsentGrant {
        guard let requestConsentGrantId = request.payload["consentGrantId"] else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("consentGrantId")
        }
        let consentGrantId = try MeshAgentWalletProviderMetadata.stableValue(
            "consentGrantId",
            requestConsentGrantId
        )
        guard let grant = grantsById[consentGrantId] else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("consentGrantId.unknown")
        }
        guard grant.status == .active else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("consentGrantId.revoked")
        }
        switch try grant.validityStatus(verifiedAt: verifiedAt) {
        case .valid:
            break
        case .expired:
            throw MeshKitValidationError.invalidAgentWalletIdentity("consentGrantId.expired")
        case .notYetValid:
            throw MeshKitValidationError.invalidAgentWalletIdentity("consentGrantId.notYetValid")
        }
        guard let requestMerchantScope = request.payload["merchantScope"] else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("merchantScope")
        }
        let merchantScope = try MeshAgentWalletProviderMetadata.stableValue(
            "merchantScope",
            requestMerchantScope
        )
        guard merchantScope == grant.merchantScope else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("merchant-scope-denied")
        }
        return grant
    }
}

public struct DailyMartScopeConsentGateResult: Codable, Equatable, Sendable {
    public let merchantScope: String
    public let capabilityScope: String
    public let consentGrantId: String
    public let status: MeshDelegatedSpendingPolicyVerificationStatus
    public let reason: String?
    public let verifiedAt: String

    public init(
        merchantScope: String,
        capabilityScope: String,
        consentGrantId: String,
        status: MeshDelegatedSpendingPolicyVerificationStatus,
        reason: String? = nil,
        verifiedAt: String
    ) throws {
        self.merchantScope = try MeshAgentWalletProviderMetadata.stableValue("merchantScope", merchantScope)
        self.capabilityScope = try MeshAgentWalletProviderMetadata.stableValue("capabilityScope", capabilityScope)
        self.consentGrantId = try MeshAgentWalletProviderMetadata.stableValue("consentGrantId", consentGrantId)
        self.status = status
        self.reason = try reason.map { try MeshAgentWalletProviderMetadata.stableValue("reason", $0) }
        self.verifiedAt = try MeshAgentWalletProviderMetadata.stableValue("verifiedAt", verifiedAt)
        try validate()
    }

    public func validate() throws {
        try MeshAgentWalletProviderMetadata.validateIdentifier("merchantScope", merchantScope)
        try MeshAgentWalletProviderMetadata.validateIdentifier("capabilityScope", capabilityScope)
        try MeshAgentWalletProviderMetadata.validateIdentifier("consentGrantId", consentGrantId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("verifiedAt", verifiedAt)
        switch status {
        case .approved:
            guard reason == nil else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("reason")
            }
        case .denied:
            guard let reason, !reason.isEmpty else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("reason")
            }
            try MeshAgentWalletProviderMetadata.validateIdentifier("reason", reason)
        }
    }
}

public struct DailyMartScopeConsentGate: Sendable {
    public let merchantScopeValidator: DailyMartMerchantScopeValidator
    public let capabilityScopeValidator: DailyMartCapabilityScopeValidator
    public let consentGrantVerifier: DailyMartConsentGrantVerifier

    public init(
        merchantScopeValidator: DailyMartMerchantScopeValidator,
        capabilityScopeValidator: DailyMartCapabilityScopeValidator,
        consentGrantVerifier: DailyMartConsentGrantVerifier
    ) {
        self.merchantScopeValidator = merchantScopeValidator
        self.capabilityScopeValidator = capabilityScopeValidator
        self.consentGrantVerifier = consentGrantVerifier
    }

    public init(expiresAt: String = "2026-12-31T23:59:59Z") throws {
        self.init(
            merchantScopeValidator: try DailyMartMerchantScopeValidator(),
            capabilityScopeValidator: try DailyMartCapabilityScopeValidator(),
            consentGrantVerifier: try DailyMartDelegatedSpendingPolicy.consentGrantVerifier(expiresAt: expiresAt)
        )
    }

    public func evaluate(
        _ request: MeshRequest,
        verifiedAt: String
    ) throws -> DailyMartScopeConsentGateResult {
        let normalizedVerifiedAt = try MeshAgentWalletProviderMetadata.stableValue("verifiedAt", verifiedAt)
        do {
            try merchantScopeValidator.validate(request)
            try capabilityScopeValidator.validate(request)
            let grant = try consentGrantVerifier.verify(request, verifiedAt: normalizedVerifiedAt)
            return try DailyMartScopeConsentGateResult(
                merchantScope: grant.merchantScope,
                capabilityScope: grant.capabilityId,
                consentGrantId: grant.consentGrantId,
                status: .approved,
                verifiedAt: normalizedVerifiedAt
            )
        } catch {
            return try DailyMartScopeConsentGateResult(
                merchantScope: request.payload["merchantScope"] ?? merchantScopeValidator.authorizedMerchantScope,
                capabilityScope: request.payload["capabilityScope"] ?? request.target.capabilityId,
                consentGrantId: request.payload["consentGrantId"] ?? capabilityScopeValidator.consentGrantId,
                status: .denied,
                reason: Self.denialReason(for: error),
                verifiedAt: normalizedVerifiedAt
            )
        }
    }

    public func requireApproved(
        _ request: MeshRequest,
        verifiedAt: String
    ) throws -> DailyMartScopeConsentGateResult {
        let result = try evaluate(request, verifiedAt: verifiedAt)
        guard result.status == .approved else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(result.reason ?? "scope-consent-denied")
        }
        return result
    }

    private static func denialReason(for error: Error) -> String {
        guard case MeshKitValidationError.invalidAgentWalletIdentity(let field) = error else {
            return "scope-consent-denied"
        }
        return denialReasonCode(for: field)
    }

    static func denialReasonCode(for field: String) -> String {
        switch field {
        case "merchant-scope-denied", "merchantScope", "authorizedMerchantScope":
            return "merchant-scope-denied"
        case "capability-scope-denied", "capabilityScope", "target.capabilityId":
            return "capability-scope-denied"
        case "consent-grant-denied", "consentGrantId":
            return "consent-grant-denied"
        case "consent-grant-unknown", "consentGrantId.unknown":
            return "consent-grant-unknown"
        case "consent-grant-expired", "consentGrantId.expired":
            return "consent-grant-expired"
        case "consent-grant-not-yet-valid", "consentGrantId.notYetValid":
            return "consent-grant-not-yet-valid"
        case "consent-grant-revoked", "consentGrantId.revoked":
            return "consent-grant-revoked"
        case "consent-grant-context", "consentGrantId.context":
            return "consent-grant-context"
        case "missing-policy", "policyId", "policyHash":
            return "missing-policy"
        case "policy-id-mismatch":
            return "policy-id-mismatch"
        case "policy-hash-mismatch":
            return "policy-hash-mismatch"
        case "walletSessionId", "principalId", "requestContextSubject":
            return "consent-grant-context"
        default:
            return "scope-consent-denied"
        }
    }
}

/// DailyMart pre-execution authorization gate.
///
/// This combines merchant consent scope and capability consent scope before the
/// wallet policy is evaluated. The payment adapter is never reached when the
/// merchant, target capability, payload capability, or requested payment
/// capability falls outside the delegated grant.
public struct DailyMartPreExecutionAuthorizationGate: Sendable {
    public let scopeConsentGate: DailyMartScopeConsentGate

    public init(scopeConsentGate: DailyMartScopeConsentGate) {
        self.scopeConsentGate = scopeConsentGate
    }

    public init(expiresAt: String = "2026-12-31T23:59:59Z") throws {
        self.scopeConsentGate = try DailyMartDelegatedSpendingPolicy.scopeConsentGate(expiresAt: expiresAt)
    }

    public func evaluate(
        _ request: MeshRequest,
        verifiedAt: String
    ) throws -> DailyMartScopeConsentGateResult {
        let normalizedVerifiedAt = try MeshAgentWalletProviderMetadata.stableValue("verifiedAt", verifiedAt)
        do {
            try scopeConsentGate.merchantScopeValidator.validate(request)
            try scopeConsentGate.capabilityScopeValidator.validate(
                requestedCapabilities: requestedCapabilities(from: request),
                consentGrantId: requestConsentGrantId(from: request)
            )
            let grant = try scopeConsentGate.consentGrantVerifier.verify(request, verifiedAt: normalizedVerifiedAt)
            return try DailyMartScopeConsentGateResult(
                merchantScope: grant.merchantScope,
                capabilityScope: grant.capabilityId,
                consentGrantId: grant.consentGrantId,
                status: .approved,
                verifiedAt: normalizedVerifiedAt
            )
        } catch {
            return try DailyMartScopeConsentGateResult(
                merchantScope: request.payload["merchantScope"] ?? scopeConsentGate.merchantScopeValidator.authorizedMerchantScope,
                capabilityScope: request.payload["capabilityScope"] ?? request.target.capabilityId,
                consentGrantId: request.payload["consentGrantId"] ?? scopeConsentGate.capabilityScopeValidator.consentGrantId,
                status: .denied,
                reason: Self.denialReason(for: error),
                verifiedAt: normalizedVerifiedAt
            )
        }
    }

    public func requireApproved(
        _ request: MeshRequest,
        verifiedAt: String
    ) throws -> DailyMartScopeConsentGateResult {
        let result = try evaluate(request, verifiedAt: verifiedAt)
        guard result.status == .approved else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(result.reason ?? "pre-execution-authorization-denied")
        }
        return result
    }

    private func requestedCapabilities(from request: MeshRequest) throws -> [String] {
        var requested: [String] = [
            request.target.capabilityId
        ]
        if let capabilityScope = request.payload["capabilityScope"] {
            requested.append(capabilityScope)
        }
        requested.append(try requestedPaymentCapability(from: request))
        return requested
    }

    private func requestConsentGrantId(from request: MeshRequest) throws -> String {
        guard let consentGrantId = request.payload["consentGrantId"] else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("consentGrantId")
        }
        return try MeshAgentWalletProviderMetadata.stableValue("consentGrantId", consentGrantId)
    }

    private func requestedPaymentCapability(from request: MeshRequest) throws -> String {
        let rawCapability = request.payload["paymentCapability"]
            ?? request.payload["paymentCapabilityScope"]
            ?? request.payload["payment_capability"]
            ?? request.payload["capabilityScope"]
            ?? request.target.capabilityId
        return try MeshAgentWalletProviderMetadata.stableValue("paymentCapability", rawCapability)
    }

    private static func denialReason(for error: Error) -> String {
        guard case MeshKitValidationError.invalidAgentWalletIdentity(let field) = error else {
            return "pre-execution-authorization-denied"
        }
        return DailyMartScopeConsentGate.denialReasonCode(for: field)
    }
}

public struct DailyMartDelegatedPolicyScopeValidationResult: Codable, Equatable, Sendable {
    public let policyId: String
    public let merchantScope: String
    public let requestedCapabilities: [String]
    public let status: MeshDelegatedSpendingPolicyVerificationStatus
    public let reason: String?
    public let verifiedAt: String

    public init(
        policyId: String,
        merchantScope: String,
        requestedCapabilities: [String],
        status: MeshDelegatedSpendingPolicyVerificationStatus,
        reason: String? = nil,
        verifiedAt: String
    ) throws {
        self.policyId = try MeshAgentWalletProviderMetadata.stableValue("policyId", policyId)
        self.merchantScope = try MeshAgentWalletProviderMetadata.stableValue("merchantScope", merchantScope)
        guard !requestedCapabilities.isEmpty else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("capabilityScope")
        }
        self.requestedCapabilities = try requestedCapabilities.map { capability in
            let normalized = try MeshAgentWalletProviderMetadata.stableValue("capabilityScope", capability)
            try MeshAgentWalletProviderMetadata.validateIdentifier("capabilityScope", normalized)
            return normalized
        }
        self.status = status
        self.reason = try reason.map { try MeshAgentWalletProviderMetadata.stableValue("reason", $0) }
        self.verifiedAt = try MeshAgentWalletProviderMetadata.stableValue("verifiedAt", verifiedAt)
        try validate()
    }

    public func validate() throws {
        try MeshAgentWalletProviderMetadata.validateIdentifier("policyId", policyId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("merchantScope", merchantScope)
        guard !requestedCapabilities.isEmpty else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("capabilityScope")
        }
        for capability in requestedCapabilities {
            try MeshAgentWalletProviderMetadata.validateIdentifier("capabilityScope", capability)
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("verifiedAt", verifiedAt)
        switch status {
        case .approved:
            guard reason == nil else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("reason")
            }
        case .denied:
            guard let reason, !reason.isEmpty else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("reason")
            }
            try MeshAgentWalletProviderMetadata.validateIdentifier("reason", reason)
        }
    }
}

/// DailyMart policy-scope validator for delegated agent wallet execution.
///
/// This is intentionally bound to the delegated policy, not to provider or
/// maroo-specific execution details. It runs before request anchoring or OKRW
/// execution so a wider app-to-app request cannot be converted into a chain
/// attempt.
public struct DailyMartDelegatedPolicyScopeValidator: Sendable {
    public let policy: MeshAgentWalletDelegatedSpendingPolicy

    public init(policy: MeshAgentWalletDelegatedSpendingPolicy) throws {
        try policy.validate()
        self.policy = policy
    }

    public func evaluate(
        _ request: MeshRequest,
        verifiedAt: String
    ) throws -> DailyMartDelegatedPolicyScopeValidationResult {
        let normalizedVerifiedAt = try MeshAgentWalletProviderMetadata.stableValue("verifiedAt", verifiedAt)
        let merchantScope = try requestMerchantScope(from: request)
        let requestedCapabilities = try Self.requestedCapabilities(from: request)

        guard merchantScope == policy.merchantScope else {
            return try DailyMartDelegatedPolicyScopeValidationResult(
                policyId: policy.policyId,
                merchantScope: merchantScope,
                requestedCapabilities: requestedCapabilities,
                status: .denied,
                reason: MeshAgentWalletDelegatedSpendingPolicy.denialReason(forPolicyViolationField: "merchantScope"),
                verifiedAt: normalizedVerifiedAt
            )
        }

        guard requestedCapabilities.allSatisfy({ $0 == policy.capabilityScope }) else {
            return try DailyMartDelegatedPolicyScopeValidationResult(
                policyId: policy.policyId,
                merchantScope: merchantScope,
                requestedCapabilities: requestedCapabilities,
                status: .denied,
                reason: MeshAgentWalletDelegatedSpendingPolicy.denialReason(forPolicyViolationField: "capabilityScope"),
                verifiedAt: normalizedVerifiedAt
            )
        }

        return try DailyMartDelegatedPolicyScopeValidationResult(
            policyId: policy.policyId,
            merchantScope: merchantScope,
            requestedCapabilities: requestedCapabilities,
            status: .approved,
            verifiedAt: normalizedVerifiedAt
        )
    }

    public func requireApproved(
        _ request: MeshRequest,
        verifiedAt: String
    ) throws -> DailyMartDelegatedPolicyScopeValidationResult {
        let result = try evaluate(request, verifiedAt: verifiedAt)
        guard result.status == .approved else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(result.reason ?? "policy-scope-denied")
        }
        return result
    }

    private func requestMerchantScope(from request: MeshRequest) throws -> String {
        guard let merchantScope = request.payload["merchantScope"] else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("merchantScope")
        }
        return try MeshAgentWalletProviderMetadata.stableValue("merchantScope", merchantScope)
    }

    private static func requestedCapabilities(from request: MeshRequest) throws -> [String] {
        var capabilities: [String] = []
        try appendCapabilities(from: request.target.capabilityId, to: &capabilities)
        if let capabilityScope = request.payload["capabilityScope"] {
            try appendCapabilities(from: capabilityScope, to: &capabilities)
        }
        if let paymentCapability = request.payload["paymentCapability"]
            ?? request.payload["paymentCapabilityScope"]
            ?? request.payload["payment_capability"] {
            try appendCapabilities(from: paymentCapability, to: &capabilities)
        }
        guard !capabilities.isEmpty else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("capabilityScope")
        }
        return capabilities
    }

    private static func appendCapabilities(
        from rawValue: String,
        to capabilities: inout [String]
    ) throws {
        let rawCapabilities = rawValue.split(separator: ",", omittingEmptySubsequences: true)
        guard !rawCapabilities.isEmpty else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("capabilityScope")
        }
        for rawCapability in rawCapabilities {
            let capability = String(rawCapability).trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = try MeshAgentWalletProviderMetadata.stableValue("capabilityScope", capability)
            try MeshAgentWalletProviderMetadata.validateIdentifier("capabilityScope", normalized)
            capabilities.append(normalized)
        }
    }
}

public enum DailyMartConsentValidationSource: String, Codable, Equatable, Sendable {
    case user
    case delegatedAgent
}

public struct DailyMartConsentValidationResult: Codable, Equatable, Sendable {
    public let targetBundleId: String
    public let capabilityId: String
    public let source: DailyMartConsentValidationSource?
    public let consentGrantId: String?
    public let userConsentId: String?
    public let status: MeshDelegatedSpendingPolicyVerificationStatus
    public let reason: String?
    public let verifiedAt: String

    public init(
        targetBundleId: String,
        capabilityId: String,
        source: DailyMartConsentValidationSource?,
        consentGrantId: String? = nil,
        userConsentId: String? = nil,
        status: MeshDelegatedSpendingPolicyVerificationStatus,
        reason: String? = nil,
        verifiedAt: String
    ) throws {
        self.targetBundleId = try MeshAgentWalletProviderMetadata.stableValue("targetBundleId", targetBundleId)
        self.capabilityId = try MeshAgentWalletProviderMetadata.stableValue("capabilityId", capabilityId)
        self.source = source
        self.consentGrantId = try consentGrantId.map { try MeshAgentWalletProviderMetadata.stableValue("consentGrantId", $0) }
        self.userConsentId = try userConsentId.map { try MeshAgentWalletProviderMetadata.stableValue("userConsentId", $0) }
        self.status = status
        self.reason = try reason.map { try MeshAgentWalletProviderMetadata.stableValue("reason", $0) }
        self.verifiedAt = try MeshAgentWalletProviderMetadata.stableValue("verifiedAt", verifiedAt)
        try validate()
    }

    public func validate() throws {
        try MeshAgentWalletProviderMetadata.validateIdentifier("targetBundleId", targetBundleId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("capabilityId", capabilityId)
        if let consentGrantId {
            try MeshAgentWalletProviderMetadata.validateIdentifier("consentGrantId", consentGrantId)
        }
        if let userConsentId {
            try MeshAgentWalletProviderMetadata.validateIdentifier("userConsentId", userConsentId)
        }
        try MeshAgentWalletProviderMetadata.validateIdentifier("verifiedAt", verifiedAt)
        switch status {
        case .approved:
            guard source != nil else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("consentSource")
            }
            guard reason == nil else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("reason")
            }
        case .denied:
            guard source == nil else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("consentSource")
            }
            guard let reason, !reason.isEmpty else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("reason")
            }
            try MeshAgentWalletProviderMetadata.validateIdentifier("reason", reason)
        }
    }
}

/// DailyMart target-side consent guard for the exact action being executed.
///
/// This runs before anchoring or wallet/payment execution. It accepts either
/// an explicit foreground user consent carried by DailyMart for this target
/// action, or a delegated-agent consent grant that is bound to the caller,
/// target bundle, capability, merchant scope, policy, and expiry window.
public struct DailyMartPreExecutionConsentGuard: Sendable {
    public let targetBundleId: String
    public let capabilityId: String
    public let delegatedConsentGate: DailyMartScopeConsentGate

    public init(
        targetBundleId: String = "ai.meshkit.sample.dailymart",
        capabilityId: String = DailyMartDelegatedSpendingPolicy.capabilityScope,
        delegatedConsentGate: DailyMartScopeConsentGate? = nil
    ) throws {
        self.targetBundleId = try MeshAgentWalletProviderMetadata.stableValue("targetBundleId", targetBundleId)
        self.capabilityId = try MeshAgentWalletProviderMetadata.stableValue("capabilityId", capabilityId)
        self.delegatedConsentGate = try delegatedConsentGate ?? DailyMartDelegatedSpendingPolicy.scopeConsentGate()
        try MeshAgentWalletProviderMetadata.validateIdentifier("targetBundleId", self.targetBundleId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("capabilityId", self.capabilityId)
    }

    public func evaluate(
        _ request: MeshRequest,
        verifiedAt: String
    ) throws -> DailyMartConsentValidationResult {
        let normalizedVerifiedAt = try MeshAgentWalletProviderMetadata.stableValue("verifiedAt", verifiedAt)
        guard request.target.targetBundleId == targetBundleId,
              request.target.capabilityId == capabilityId else {
            return try deniedResult(
                request,
                reason: "target-action-denied",
                verifiedAt: normalizedVerifiedAt
            )
        }

        if let userConsent = try validUserConsent(in: request) {
            return try DailyMartConsentValidationResult(
                targetBundleId: targetBundleId,
                capabilityId: capabilityId,
                source: .user,
                userConsentId: userConsent,
                status: .approved,
                verifiedAt: normalizedVerifiedAt
            )
        }

        do {
            let delegated = try delegatedConsentGate.requireApproved(request, verifiedAt: normalizedVerifiedAt)
            return try DailyMartConsentValidationResult(
                targetBundleId: targetBundleId,
                capabilityId: capabilityId,
                source: .delegatedAgent,
                consentGrantId: delegated.consentGrantId,
                status: .approved,
                verifiedAt: normalizedVerifiedAt
            )
        } catch {
            let delegatedDenialReason: String
            if request.payload["consentGrantId"] != nil {
                delegatedDenialReason = Self.denialReason(forDelegatedConsentError: error)
            } else if Self.hasUserConsentAttempt(request) {
                delegatedDenialReason = "consent-required"
            } else if Self.hasDelegatedWalletIntent(request) {
                delegatedDenialReason = "consent-grant-denied"
            } else {
                delegatedDenialReason = "consent-required"
            }
            return try deniedResult(
                request,
                reason: delegatedDenialReason,
                verifiedAt: normalizedVerifiedAt
            )
        }
    }

    public func requireApproved(
        _ request: MeshRequest,
        verifiedAt: String
    ) throws -> DailyMartConsentValidationResult {
        let result = try evaluate(request, verifiedAt: verifiedAt)
        guard result.status == .approved else {
            throw MeshKitValidationError.consentRequired(result.reason ?? "DailyMart target action")
        }
        return result
    }

    private func validUserConsent(in request: MeshRequest) throws -> String? {
        guard let rawStatus = request.payload["userConsentStatus"] else { return nil }
        let status = try MeshAgentWalletProviderMetadata.stableValue("userConsentStatus", rawStatus)
        guard status == "approved" else { return nil }
        guard let rawUserConsentId = request.payload["userConsentId"] else { return nil }
        let userConsentId = try MeshAgentWalletProviderMetadata.stableValue("userConsentId", rawUserConsentId)
        guard request.payload["userConsentTargetBundleId"] == targetBundleId,
              request.payload["userConsentCapabilityId"] == capabilityId else {
            return nil
        }
        return userConsentId
    }

    private static func hasUserConsentAttempt(_ request: MeshRequest) -> Bool {
        request.payload["userConsentStatus"] != nil
            || request.payload["userConsentId"] != nil
            || request.payload["userConsentTargetBundleId"] != nil
            || request.payload["userConsentCapabilityId"] != nil
    }

    private static func hasDelegatedWalletIntent(_ request: MeshRequest) -> Bool {
        let delegatedWalletKeys = [
            "walletSessionId",
            "principalId",
            "policyId",
            "policyHash",
            "merchantScope",
            "paymentCapability",
            "paymentCapabilityScope",
            "payment_capability",
            "payment_asset",
            "asset",
            "tokenSymbol",
            "recipientAddress",
            "recipient"
        ]
        return delegatedWalletKeys.contains { request.payload[$0] != nil }
    }

    private static func denialReason(forDelegatedConsentError error: Error) -> String {
        guard case MeshKitValidationError.invalidAgentWalletIdentity(let reason) = error else {
            return "consent-required"
        }
        switch reason {
        case "merchant-scope-denied",
             "merchantScope",
             "authorizedMerchantScope",
             "capability-scope-denied",
             "capabilityScope",
             "target.capabilityId",
             "consent-grant-denied",
             "consentGrantId",
             "consent-grant-unknown",
             "consent-grant-expired",
             "consent-grant-not-yet-valid",
             "consent-grant-context",
             "missing-policy",
             "policy-id-mismatch",
             "policyId",
             "policyHash",
             "walletSessionId",
             "principalId",
             "requestContextSubject":
            return DailyMartScopeConsentGate.denialReasonCode(for: reason)
        default:
            return "consent-required"
        }
    }

    private func deniedResult(
        _ request: MeshRequest,
        reason: String,
        verifiedAt: String
    ) throws -> DailyMartConsentValidationResult {
        try DailyMartConsentValidationResult(
            targetBundleId: request.target.targetBundleId,
            capabilityId: request.target.capabilityId,
            source: nil,
            status: .denied,
            reason: reason,
            verifiedAt: verifiedAt
        )
    }
}

public struct DailyMartPreExecutionWalletPolicyGuardResult: Equatable, Sendable {
    public let requestId: String
    public let nonce: String
    public let scopeConsent: DailyMartScopeConsentGateResult
    public let policyVerification: MeshDelegatedSpendingPolicyVerificationResult
    public let executionRequest: MeshAgentWalletExecutionRequest
    public let policyEvaluation: MeshAgentWalletPolicyEvaluationResult
    public let availableLimitBeforeExecution: Decimal

    public init(
        requestId: String,
        nonce: String,
        scopeConsent: DailyMartScopeConsentGateResult,
        policyVerification: MeshDelegatedSpendingPolicyVerificationResult,
        executionRequest: MeshAgentWalletExecutionRequest,
        policyEvaluation: MeshAgentWalletPolicyEvaluationResult,
        availableLimitBeforeExecution: Decimal
    ) throws {
        self.requestId = try MeshAgentWalletProviderMetadata.stableValue("requestId", requestId)
        self.nonce = try MeshAgentWalletProviderMetadata.stableValue("nonce", nonce)
        self.scopeConsent = scopeConsent
        self.policyVerification = policyVerification
        self.executionRequest = executionRequest
        self.policyEvaluation = policyEvaluation
        self.availableLimitBeforeExecution = availableLimitBeforeExecution
        try validate()
    }

    public func validate() throws {
        try MeshAgentWalletProviderMetadata.validateIdentifier("requestId", requestId)
        try MeshAgentWalletProviderMetadata.validateIdentifier("nonce", nonce)
        try scopeConsent.validate()
        try policyVerification.validate()
        try executionRequest.validate()
        try policyEvaluation.validate()
        guard scopeConsent.status == .approved else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(scopeConsent.reason ?? "scope-consent-denied")
        }
        guard policyVerification.status == .approved else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(policyVerification.reason ?? "policy-verification-denied")
        }
        guard policyEvaluation.status == .allowed else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(policyEvaluation.reason ?? "policy-evaluation-denied")
        }
        guard availableLimitBeforeExecution >= executionRequest.amount else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("availableLimit")
        }
    }
}

/// DailyMart target-side wallet policy guard.
///
/// This module composes the provider-neutral wallet policy model with the
/// DailyMart consent grant and signed request metadata. It runs before anchor
/// submission or OKRW payment/transfer execution, so policy denials cannot be
/// misrepresented as chain execution results.
public struct DailyMartPreExecutionWalletPolicyGuard: Sendable {
    public let policy: MeshAgentWalletDelegatedSpendingPolicy
    public let accounting: MeshAgentWalletDelegatedSpendAccounting
    public let authorizationGate: DailyMartPreExecutionAuthorizationGate
    public let allowedExecutionKinds: Set<MeshAgentWalletExecutionKind>

    public var scopeConsentGate: DailyMartScopeConsentGate {
        authorizationGate.scopeConsentGate
    }

    public init(
        policy: MeshAgentWalletDelegatedSpendingPolicy,
        accounting: MeshAgentWalletDelegatedSpendAccounting? = nil,
        scopeConsentGate: DailyMartScopeConsentGate? = nil,
        allowedExecutionKinds: Set<MeshAgentWalletExecutionKind> = [.payment, .transfer]
    ) throws {
        try policy.validate()
        guard !allowedExecutionKinds.isEmpty else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("executionKind")
        }
        self.policy = policy
        self.accounting = try accounting ?? MeshAgentWalletDelegatedSpendAccounting(policy: policy)
        self.authorizationGate = try DailyMartPreExecutionAuthorizationGate(
            scopeConsentGate: scopeConsentGate ?? DailyMartDelegatedSpendingPolicy.scopeConsentGate(expiresAt: policy.expiresAt)
        )
        self.allowedExecutionKinds = allowedExecutionKinds
    }

    public init(
        expiresAt: String = "2026-12-31T23:59:59Z",
        accounting: MeshAgentWalletDelegatedSpendAccounting? = nil,
        allowedExecutionKinds: Set<MeshAgentWalletExecutionKind> = [.payment, .transfer]
    ) throws {
        try self.init(
            policy: DailyMartDelegatedSpendingPolicy.expectedPolicy(expiresAt: expiresAt),
            accounting: accounting,
            scopeConsentGate: DailyMartDelegatedSpendingPolicy.scopeConsentGate(expiresAt: expiresAt),
            allowedExecutionKinds: allowedExecutionKinds
        )
    }

    public func evaluate(
        _ request: MeshRequest,
        executionKind: MeshAgentWalletExecutionKind = .payment,
        executionId: String? = nil,
        verifiedAt: String
    ) throws -> DailyMartPreExecutionWalletPolicyGuardResult {
        guard allowedExecutionKinds.contains(executionKind) else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("executionKind")
        }

        let normalizedVerifiedAt = try MeshAgentWalletProviderMetadata.stableValue("verifiedAt", verifiedAt)
        let scopeConsent = try authorizationGate.requireApproved(request, verifiedAt: normalizedVerifiedAt)
        guard scopeConsent.consentGrantId == policy.consentGrantId else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("policy-consent-grant-mismatch")
        }
        _ = try DailyMartDelegatedPolicyScopeValidator(policy: policy).requireApproved(
            request,
            verifiedAt: normalizedVerifiedAt
        )
        let policyVerification = try verifyPolicyReference(from: request, verifiedAt: normalizedVerifiedAt)
        guard policyVerification.status == .approved else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(policyVerification.reason ?? "policy-verification-denied")
        }
        do {
            try MeshAgentWalletDelegatedSpendingPolicyExpiryWindowValidator(
                startsAt: policy.startsAt,
                expiresAt: policy.expiresAt
            ).validateActive(at: normalizedVerifiedAt)
        } catch MeshKitValidationError.invalidAgentWalletIdentity(let field) {
            throw MeshKitValidationError.invalidAgentWalletIdentity(
                MeshAgentWalletDelegatedSpendingPolicy.denialReason(forPolicyViolationField: field)
            )
        }

        let executionRequest = try makeExecutionRequest(
            from: request,
            executionKind: executionKind,
            executionId: executionId
        )
        let policyEvaluation = try policy.evaluateExecutionRequest(
            executionRequest,
            requestedAt: normalizedVerifiedAt
        )
        guard policyEvaluation.status == .allowed else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(policyEvaluation.reason ?? "policy-evaluation-denied")
        }
        guard try accounting.canReserve(executionRequest, requestedAt: normalizedVerifiedAt) else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("availableLimit")
        }

        return try DailyMartPreExecutionWalletPolicyGuardResult(
            requestId: request.requestId,
            nonce: request.nonce,
            scopeConsent: scopeConsent,
            policyVerification: policyVerification,
            executionRequest: executionRequest,
            policyEvaluation: policyEvaluation,
            availableLimitBeforeExecution: accounting.availableLimit
        )
    }

    public func makeExecutionRequest(
        from request: MeshRequest,
        executionKind: MeshAgentWalletExecutionKind = .payment,
        executionId: String? = nil
    ) throws -> MeshAgentWalletExecutionRequest {
        guard allowedExecutionKinds.contains(executionKind) else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("executionKind")
        }
        let amount = try Self.requestedAmount(from: request)
        let asset = try Self.requestedAsset(from: request, defaultAsset: policy.asset)
        let paymentCapability = try Self.requestedPaymentCapability(from: request)
        let recipientAddress = try Self.requestedRecipientAddress(
            from: request,
            defaultRecipientAddress: policy.recipientAddress
        )

        return try MeshAgentWalletExecutionRequest(
            executionId: executionId ?? "exec-\(request.requestId)",
            kind: executionKind,
            requestAnchorMetadata: MeshSignedRequestAnchorMetadata(request: request),
            scope: MeshAgentWalletSpendingScope(
                merchantId: policy.merchantScope,
                targetBundleId: request.target.targetBundleId,
                capabilityId: paymentCapability,
                consentGrantId: policy.consentGrantId
            ),
            amount: amount,
            currencyCode: "KRW",
            tokenSymbol: asset,
            recipientAddress: recipientAddress,
            policyId: policy.policyId,
            policyHash: policy.policyHash
        )
    }

    private func verifyPolicyReference(
        from request: MeshRequest,
        verifiedAt: String
    ) throws -> MeshDelegatedSpendingPolicyVerificationResult {
        let requestPolicy = try DailyMartDelegatedSpendingPolicy.policyReference(from: request)
        return try MeshDelegatedSpendingPolicyVerifier(expectedPolicy: policy).verify(
            policyId: requestPolicy.policyId,
            policyHash: requestPolicy.policyHash,
            verifiedAt: verifiedAt
        )
    }

    private static func requestedAmount(from request: MeshRequest) throws -> Decimal {
        guard let rawAmount = request.payload["budget_krw"] ?? request.payload["amount"] else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("amount")
        }
        let stableAmount = try MeshAgentWalletProviderMetadata.stableValue("amount", rawAmount)
        guard let amount = Decimal(string: stableAmount, locale: Locale(identifier: "en_US_POSIX")),
              amount > 0 else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("amount")
        }
        return amount
    }

    private static func requestedAsset(
        from request: MeshRequest,
        defaultAsset: String
    ) throws -> String {
        let rawAsset = request.payload["payment_asset"]
            ?? request.payload["asset"]
            ?? request.payload["tokenSymbol"]
            ?? defaultAsset
        let stableAsset = try MeshAgentWalletProviderMetadata.stableValue("asset", rawAsset)
        return stableAsset.uppercased()
    }

    private static func requestedPaymentCapability(from request: MeshRequest) throws -> String {
        let rawCapability = request.payload["paymentCapability"]
            ?? request.payload["paymentCapabilityScope"]
            ?? request.payload["payment_capability"]
            ?? request.payload["capabilityScope"]
            ?? request.target.capabilityId
        return try MeshAgentWalletProviderMetadata.stableValue("paymentCapability", rawCapability)
    }

    private static func requestedRecipientAddress(
        from request: MeshRequest,
        defaultRecipientAddress: String?
    ) throws -> String {
        guard let recipientAddress = request.payload["recipientAddress"]
                ?? request.payload["recipient"]
                ?? defaultRecipientAddress else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("recipientAddress")
        }
        return try MeshAgentWalletProviderMetadata.stableValue("recipientAddress", recipientAddress)
    }
}

public enum DailyMartDelegatedSpendingPolicy {
    public static let policyId = "policy-hermes-dailymart-okrw-v1"
    public static let policyHash = MeshPayloadHash(value: String(repeating: "f", count: 64))
    public static let consentGrantId = "grant-hermes-dailymart-001"
    public static let consentGrantSignerKeyId = "sample-ios-ed25519"
    public static let walletSessionId = "wallet-session-hermes-dailymart-001"
    public static let principalId = "principal-hermes-agent-001"
    public static let requestContextSubject = "principal-hermes-agent-001"
    public static let merchantScope = "merchant.dailymart"
    public static let capabilityScope = "grocery.purchase_essentials"
    public static let asset = "OKRW"
    public static let recipientAddress = "0x000000000000000000000000000000000000d417"

    public static func expectedPolicy(
        expiresAt: String = "2026-12-31T23:59:59Z"
    ) throws -> MeshAgentWalletDelegatedSpendingPolicy {
        try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: policyId,
            policyHash: policyHash,
            consentGrantId: consentGrantId,
            merchantScope: merchantScope,
            capabilityScope: capabilityScope,
            singlePaymentMax: Decimal(100),
            sessionTotalLimit: Decimal(100),
            remainingLimit: Decimal(100),
            expiresAt: expiresAt,
            asset: asset,
            recipientAddress: recipientAddress
        )
    }

    public static func verifier(
        expiresAt: String = "2026-12-31T23:59:59Z"
    ) throws -> MeshDelegatedSpendingPolicyVerifier {
        try MeshDelegatedSpendingPolicyVerifier(expectedPolicy: expectedPolicy(expiresAt: expiresAt))
    }

    public static func verifyRequest(
        _ request: MeshRequest,
        verifiedAt: String,
        expiresAt: String = "2026-12-31T23:59:59Z"
    ) throws -> MeshDelegatedSpendingPolicyVerificationResult {
        let scopeConsent = try scopeConsentGate(expiresAt: expiresAt).evaluate(request, verifiedAt: verifiedAt)
        if scopeConsent.status == .denied,
           scopeConsent.reason != "policy-id-mismatch",
           scopeConsent.reason != "policy-hash-mismatch" {
            throw MeshKitValidationError.invalidAgentWalletIdentity(scopeConsent.reason ?? "scope-consent-denied")
        }
        let requestPolicy = try policyReference(from: request)
        return try verifier(expiresAt: expiresAt).verify(
            policyId: requestPolicy.policyId,
            policyHash: requestPolicy.policyHash,
            verifiedAt: verifiedAt
        )
    }

    public static func consentGrant(
        startsAt: String? = nil,
        expiresAt: String = "2026-12-31T23:59:59Z",
        status: DailyMartConsentGrantStatus = .active
    ) throws -> DailyMartConsentGrant {
        try DailyMartConsentGrant(
            consentGrantId: consentGrantId,
            callerAppId: "app.hermes-chat",
            callerBundleId: "ai.meshkit.sample.hermeschat",
            requestContextSubject: requestContextSubject,
            walletSessionId: walletSessionId,
            principalId: principalId,
            targetBundleId: "ai.meshkit.sample.dailymart",
            capabilityId: capabilityScope,
            merchantScope: merchantScope,
            policyId: policyId,
            signerKeyId: consentGrantSignerKeyId,
            walletAddress: "maroo1dailyMartAgentWallet",
            startsAt: startsAt,
            expiresAt: expiresAt,
            status: status
        )
    }

    public static func consentGrantVerifier(
        startsAt: String? = nil,
        expiresAt: String = "2026-12-31T23:59:59Z",
        status: DailyMartConsentGrantStatus = .active
    ) throws -> DailyMartConsentGrantVerifier {
        try DailyMartConsentGrantVerifier(grants: [consentGrant(startsAt: startsAt, expiresAt: expiresAt, status: status)])
    }

    public static func merchantConsentScopeValidator(
        startsAt: String? = nil,
        expiresAt: String = "2026-12-31T23:59:59Z",
        status: DailyMartConsentGrantStatus = .active
    ) throws -> DailyMartMerchantConsentScopeValidator {
        try DailyMartMerchantConsentScopeValidator(grants: [consentGrant(startsAt: startsAt, expiresAt: expiresAt, status: status)])
    }

    public static func scopeConsentGate(
        startsAt: String? = nil,
        expiresAt: String = "2026-12-31T23:59:59Z",
        status: DailyMartConsentGrantStatus = .active
    ) throws -> DailyMartScopeConsentGate {
        DailyMartScopeConsentGate(
            merchantScopeValidator: try DailyMartMerchantScopeValidator(authorizedMerchantScope: merchantScope),
            capabilityScopeValidator: try DailyMartCapabilityScopeValidator(
                consentGrantId: consentGrantId,
                consentedCapabilities: [capabilityScope]
            ),
            consentGrantVerifier: try consentGrantVerifier(startsAt: startsAt, expiresAt: expiresAt, status: status)
        )
    }

    public static func policyReference(from request: MeshRequest) throws -> (policyId: String, policyHash: MeshPayloadHash) {
        guard let policyId = request.payload["policyId"] else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("missing-policy")
        }
        guard let policyHash = request.payload["policyHash"] else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("missing-policy")
        }
        return (
            policyId: try MeshAgentWalletProviderMetadata.stableValue("policyId", policyId),
            policyHash: MeshPayloadHash(value: policyHash)
        )
    }
}
