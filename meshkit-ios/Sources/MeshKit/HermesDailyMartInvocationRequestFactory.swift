import Foundation

public struct HermesDailyMartAnchoredInvocation: Codable, Equatable, Sendable {
    public let request: MeshRequest
    public let metadata: MeshSignedRequestAnchorMetadata
    public let anchoringReference: MeshRequestAnchorIdentifier
    public let anchorPayload: MeshRequestAnchorPayload

    public var signedRequestHash: MeshPayloadHash {
        metadata.signedRequestHash
    }

    public init(
        request: MeshRequest,
        providerIdentity: MeshChainProviderIdentity,
        policyId: String = DailyMartDelegatedSpendingPolicy.policyId,
        policyHash: MeshPayloadHash = DailyMartDelegatedSpendingPolicy.policyHash
    ) throws {
        self.request = request
        self.metadata = try MeshSignedRequestAnchorMetadata(request: request)
        self.anchoringReference = try MeshRequestAnchorCanonicalization.anchoringReference(
            forSignedRequestHash: metadata.signedRequestHash,
            providerIdentity: providerIdentity
        )
        self.anchorPayload = try MeshRequestAnchorPayload(
            metadata: metadata,
            policyId: policyId,
            policyHash: policyHash
        )
        try MeshRequestAnchorCanonicalization.validate(metadata: metadata, boundTo: request)
    }
}

public struct HermesDailyMartInvocationRequestFactory: Sendable {
    public let caller: MeshIdentity
    public let target: MeshCapability
    public let signer: MeshRequestSigner
    public let requestIdPrefix: String
    public let noncePrefix: String
    private let requestIdSuffix: @Sendable () -> String
    private let nonceSuffix: @Sendable () -> String
    private let timestamp: @Sendable () -> String

    public init(
        caller: MeshIdentity,
        target: MeshCapability,
        signer: MeshRequestSigner,
        requestIdPrefix: String = "ios-grocery",
        noncePrefix: String = "ios-grocery-nonce",
        uniqueSuffix: @escaping @Sendable () -> String = { UUID().uuidString },
        nonceUniqueSuffix: (@Sendable () -> String)? = nil,
        timestamp: @escaping @Sendable () -> String = { ISO8601DateFormatter().string(from: Date()) }
    ) throws {
        try Self.validatePrefix("requestIdPrefix", requestIdPrefix)
        try Self.validatePrefix("noncePrefix", noncePrefix)
        self.caller = caller
        self.target = target
        self.signer = signer
        self.requestIdPrefix = requestIdPrefix
        self.noncePrefix = noncePrefix
        self.requestIdSuffix = uniqueSuffix
        self.nonceSuffix = nonceUniqueSuffix ?? uniqueSuffix
        self.timestamp = timestamp
    }

    public func makePurchaseEssentialsRequest() throws -> MeshRequest {
        let requestIdSuffix = requestIdSuffix()
        let nonceSuffix = nonceSuffix()
        return try MeshSignedRequestBuilder(caller: caller, target: target, signer: signer).makeRequest(
            requestId: "\(requestIdPrefix)-\(requestIdSuffix)",
            payload: Self.purchaseEssentialsPayload(),
            nonce: "\(noncePrefix)-\(nonceSuffix)",
            timestamp: timestamp()
        )
    }

    public func makePurchaseEssentialsAnchoredInvocation(
        providerIdentity: MeshChainProviderIdentity,
        policyId: String = DailyMartDelegatedSpendingPolicy.policyId,
        policyHash: MeshPayloadHash = DailyMartDelegatedSpendingPolicy.policyHash
    ) throws -> HermesDailyMartAnchoredInvocation {
        try HermesDailyMartAnchoredInvocation(
            request: makePurchaseEssentialsRequest(),
            providerIdentity: providerIdentity,
            policyId: policyId,
            policyHash: policyHash
        )
    }

    public static func purchaseEssentialsPayload() -> [String: String] {
        [
            "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6",
            "address_ref": "home.saved",
            "budget_krw": "100",
            "merchantScope": DailyMartDelegatedSpendingPolicy.merchantScope,
            "capabilityScope": DailyMartDelegatedSpendingPolicy.capabilityScope,
            "consentGrantId": DailyMartDelegatedSpendingPolicy.consentGrantId,
            "walletSessionId": DailyMartDelegatedSpendingPolicy.walletSessionId,
            "principalId": DailyMartDelegatedSpendingPolicy.principalId,
            "requestContextSubject": DailyMartDelegatedSpendingPolicy.requestContextSubject,
            "policyId": DailyMartDelegatedSpendingPolicy.policyId,
            "policyHash": DailyMartDelegatedSpendingPolicy.policyHash.value
        ]
    }

    private static func validatePrefix(_ field: String, _ value: String) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized == value else {
            throw MeshKitValidationError.invalidSecurityField(field)
        }
    }
}
