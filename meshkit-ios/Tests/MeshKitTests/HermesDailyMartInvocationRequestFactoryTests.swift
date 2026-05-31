import CryptoKit
import XCTest
@testable import MeshKit

final class HermesDailyMartInvocationRequestFactoryTests: XCTestCase {
    private let signingKey = Curve25519.Signing.PrivateKey()

    func testDailyMartAppToAppInvocationIncludesRequestId() throws {
        let factory = try makeFactory(requestIdSuffixes: ["request-001"], nonceSuffixes: ["nonce-001"])

        let request = try factory.makePurchaseEssentialsRequest()

        XCTAssertEqual(request.requestId, "ios-grocery-request-001")
        XCTAssertEqual(request.nonce, "ios-grocery-nonce-nonce-001")
        XCTAssertFalse(request.requestId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertEqual(request.target.capabilityId, "grocery.purchase_essentials")
        XCTAssertFalse(request.signature.value.isEmpty)
    }

    func testDailyMartAppToAppInvocationDoesNotReuseRequestIdsAcrossCalls() throws {
        let factory = try makeFactory(
            requestIdSuffixes: ["request-001", "request-002", "request-003"],
            nonceSuffixes: ["nonce-001", "nonce-002", "nonce-003"]
        )

        let first = try factory.makePurchaseEssentialsRequest()
        let second = try factory.makePurchaseEssentialsRequest()
        let third = try factory.makePurchaseEssentialsRequest()
        let requestIds = [first.requestId, second.requestId, third.requestId]

        XCTAssertEqual(Set(requestIds).count, requestIds.count)
        XCTAssertEqual(requestIds, [
            "ios-grocery-request-001",
            "ios-grocery-request-002",
            "ios-grocery-request-003"
        ])
        XCTAssertEqual(Set(requestIds.map(\.isEmpty)), [false])
    }

    func testDailyMartAppToAppInvocationIncludesFreshNoncesAcrossCalls() throws {
        let factory = try makeFactory(
            requestIdSuffixes: ["request-001", "request-002", "request-003"],
            nonceSuffixes: ["nonce-001", "nonce-002", "nonce-003"]
        )

        let first = try factory.makePurchaseEssentialsRequest()
        let second = try factory.makePurchaseEssentialsRequest()
        let third = try factory.makePurchaseEssentialsRequest()
        let nonces = [first.nonce, second.nonce, third.nonce]

        XCTAssertEqual(nonces, [
            "ios-grocery-nonce-nonce-001",
            "ios-grocery-nonce-nonce-002",
            "ios-grocery-nonce-nonce-003"
        ])
        XCTAssertEqual(Set(nonces).count, nonces.count)
        XCTAssertTrue(nonces.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    func testDailyMartSavedGrantInvocationUsesFreshRequestIdsAcrossCalls() throws {
        let factory = try makeFactory(
            requestIdPrefix: "ios-grocery-saved-consent",
            noncePrefix: "ios-grocery-saved-consent-nonce",
            requestIdSuffixes: ["saved-request-001", "saved-request-002"],
            nonceSuffixes: ["saved-nonce-001", "saved-nonce-002"]
        )

        let first = try factory.makePurchaseEssentialsRequest()
        let second = try factory.makePurchaseEssentialsRequest()

        XCTAssertEqual(first.requestId, "ios-grocery-saved-consent-saved-request-001")
        XCTAssertEqual(second.requestId, "ios-grocery-saved-consent-saved-request-002")
        XCTAssertEqual(first.nonce, "ios-grocery-saved-consent-nonce-saved-nonce-001")
        XCTAssertEqual(second.nonce, "ios-grocery-saved-consent-nonce-saved-nonce-002")
        XCTAssertNotEqual(first.requestId, second.requestId)
        XCTAssertNotEqual(first.nonce, second.nonce)
        XCTAssertNotEqual(first.requestId, first.nonce)
        XCTAssertNotEqual(second.requestId, second.nonce)
        XCTAssertNotEqual(first.signature.value, second.signature.value)
    }

    func testHermesChatToDailyMartGenerationCreatesFreshRequestIdAndNonceForEveryRepeatedInvocation() throws {
        let factory = try makeFactory(
            requestIdSuffixes: ["tap-001", "tap-002", "tap-003", "tap-004"],
            nonceSuffixes: ["nonce-001", "nonce-002", "nonce-003", "nonce-004"]
        )

        let repeatedCalls = try (0..<4).map { _ in try factory.makePurchaseEssentialsRequest() }
        let requestIds = repeatedCalls.map(\.requestId)
        let nonces = repeatedCalls.map(\.nonce)

        XCTAssertEqual(Set(requestIds).count, repeatedCalls.count)
        XCTAssertEqual(Set(nonces).count, repeatedCalls.count)
        XCTAssertTrue(zip(requestIds, nonces).allSatisfy { requestId, nonce in requestId != nonce })
        XCTAssertTrue(repeatedCalls.allSatisfy { !$0.signature.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    func testHermesChatToDailyMartPayloadHashVerifiesGeneratedPayloadAndChangesWithNonce() throws {
        let factory = try makeFactory(
            requestIdSuffixes: ["request-001", "request-001"],
            nonceSuffixes: ["nonce-001", "nonce-002"]
        )

        let first = try factory.makePurchaseEssentialsRequest()
        let second = try factory.makePurchaseEssentialsRequest()

        XCTAssertEqual(first.payload, HermesDailyMartInvocationRequestFactory.purchaseEssentialsPayload())
        XCTAssertEqual(first.payloadHash, MeshRequestPayloadHasher.hash(for: first.payload, nonce: first.nonce))
        XCTAssertEqual(second.payloadHash, MeshRequestPayloadHasher.hash(for: second.payload, nonce: second.nonce))
        XCTAssertNotEqual(first.nonce, second.nonce)
        XCTAssertNotEqual(first.payloadHash, second.payloadHash)
        XCTAssertNoThrow(try DailyMartRequestPayloadHashValidator().validate(first))
        XCTAssertNoThrow(try DailyMartRequestPayloadHashValidator().validate(second))
    }

    func testHermesChatToDailyMartSignedPayloadVerifiesAndFailsWhenNonceChanges() throws {
        let factory = try makeFactory(
            requestIdSuffixes: ["request-001"],
            nonceSuffixes: ["nonce-001"]
        )

        let signed = try factory.makePurchaseEssentialsRequest()

        XCTAssertEqual(signed.payload, HermesDailyMartInvocationRequestFactory.purchaseEssentialsPayload())
        XCTAssertEqual(signed.signature.algorithm, "Ed25519")
        XCTAssertEqual(signed.signature.keyId, "sample-ios-ed25519")
        XCTAssertFalse(signed.signature.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertNoThrow(try MeshSignedRequestCrypto.verifySignature(for: signed, trust: dailyMartTrust))

        let tamperedNonce = MeshRequest(
            requestId: signed.requestId,
            caller: signed.caller,
            target: signed.target,
            payload: signed.payload,
            payloadHash: signed.payloadHash,
            nonce: "ios-grocery-nonce-tampered",
            timestamp: signed.timestamp,
            signature: signed.signature
        )

        XCTAssertThrowsError(try MeshSignedRequestCrypto.verifySignature(for: tamperedNonce, trust: dailyMartTrust)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("invalid request signature"))
        }
    }

    func testHermesChatToDailyMartAnchoringReferenceRecordsSignedRequestHash() throws {
        let factory = try makeFactory(
            requestIdSuffixes: ["anchor-request-001"],
            nonceSuffixes: ["anchor-nonce-001"]
        )
        let providerIdentity = try marooProviderIdentity()

        let invocation = try factory.makePurchaseEssentialsAnchoredInvocation(providerIdentity: providerIdentity)
        let expectedRequestHash = try MeshRequestAnchorCanonicalization.signedRequestHash(for: invocation.request)

        XCTAssertEqual(invocation.metadata.requestId, invocation.request.requestId)
        XCTAssertEqual(invocation.metadata.nonce, invocation.request.nonce)
        XCTAssertEqual(invocation.signedRequestHash, expectedRequestHash)
        XCTAssertEqual(invocation.anchorPayload.metadata.signedRequestHash, expectedRequestHash)
        XCTAssertEqual(invocation.anchorPayload.policyId, DailyMartDelegatedSpendingPolicy.policyId)
        XCTAssertEqual(invocation.anchorPayload.policyHash, DailyMartDelegatedSpendingPolicy.policyHash)
        XCTAssertEqual(invocation.anchoringReference.identity.metadata, providerIdentity.metadata)
        XCTAssertEqual(
            invocation.anchoringReference.anchorId,
            "request-anchor-sha256-\(expectedRequestHash.value)"
        )
        XCTAssertTrue(invocation.anchoringReference.anchorId.contains(expectedRequestHash.value))
    }

    func testHermesChatToDailyMartSwiftFlowCarriesVisibleDelegatedLimitIntoSignedRequestConstruction() throws {
        let wallet = try HermesChatDelegatedWalletViewModels.marooTestnetOKRWDailyMartGrocerySession()
        let panel = wallet.panelSnapshot
        let factory = try makeFactory(
            requestIdSuffixes: ["visible-limit-request-001"],
            nonceSuffixes: ["visible-limit-nonce-001"]
        )

        let invocation = try factory.makePurchaseEssentialsAnchoredInvocation(
            providerIdentity: marooProviderIdentity(),
            policyId: wallet.policyId,
            policyHash: wallet.policyHash
        )
        let request = invocation.request

        XCTAssertEqual(panel.headerLabel, "AgentOS/OCG delegated wallet")
        XCTAssertEqual(panel.sessionLimitLine, "100 OKRW")
        XCTAssertEqual(panel.remainingLimitLine, "100 OKRW")
        XCTAssertEqual(panel.perPaymentMaxLine, "100 OKRW")
        XCTAssertEqual(panel.authorizationLine, "OKRW · DailyMart grocery.purchase_essentials")
        XCTAssertEqual(panel.scopePresentation.merchantScope, request.payload["merchantScope"])
        XCTAssertEqual(panel.scopePresentation.capabilityScope, request.payload["capabilityScope"])
        XCTAssertEqual(wallet.consentGrantId, request.payload["consentGrantId"])
        XCTAssertEqual(wallet.policyId, request.payload["policyId"])
        XCTAssertEqual(wallet.policyHash.value, request.payload["policyHash"])
        XCTAssertEqual(wallet.targetBundleId, request.target.targetBundleId)
        XCTAssertEqual(wallet.capabilityScope, request.target.capabilityId)
        XCTAssertEqual("100", request.payload["budget_krw"])
        XCTAssertEqual(request.requestId, "ios-grocery-visible-limit-request-001")
        XCTAssertEqual(request.nonce, "ios-grocery-nonce-visible-limit-nonce-001")
        XCTAssertEqual(invocation.anchorPayload.policyId, wallet.policyId)
        XCTAssertEqual(invocation.anchorPayload.policyHash, wallet.policyHash)
        XCTAssertEqual(invocation.metadata.requestId, request.requestId)
        XCTAssertEqual(invocation.metadata.nonce, request.nonce)
        XCTAssertNoThrow(try DailyMartRequestPayloadHashValidator().validate(request))
        XCTAssertNoThrow(try MeshSignedRequestCrypto.verifySignature(for: request, trust: dailyMartTrust))
    }

    private var dailyMartTrust: MeshSenderTrust {
        MeshSenderTrust(
            callerAppId: "app.hermes-chat",
            callerBundleId: "ai.meshkit.sample.hermeschat",
            teamId: "DEVTEAMID",
            requestSigningAlgorithm: "Ed25519",
            requestSigningKeyId: "sample-ios-ed25519",
            publicKey: signingKey.publicKey.rawRepresentation.base64EncodedString()
        )
    }

    private func makeFactory(
        requestIdPrefix: String = "ios-grocery",
        noncePrefix: String = "ios-grocery-nonce",
        requestIdSuffixes: [String],
        nonceSuffixes: [String]
    ) throws -> HermesDailyMartInvocationRequestFactory {
        let requestIdGenerator = LockedSuffixGenerator(requestIdSuffixes)
        let nonceGenerator = LockedSuffixGenerator(nonceSuffixes)
        return try HermesDailyMartInvocationRequestFactory(
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-device",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "sample-ios-ed25519"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                version: "1.0"
            ),
            signer: MeshRequestSigner.ed25519(keyId: "sample-ios-ed25519", privateKey: signingKey),
            requestIdPrefix: requestIdPrefix,
            noncePrefix: noncePrefix,
            uniqueSuffix: { requestIdGenerator.next() },
            nonceUniqueSuffix: { nonceGenerator.next() },
            timestamp: { "2026-05-31T12:00:00Z" }
        )
    }

    private func marooProviderIdentity() throws -> MeshChainProviderIdentity {
        try MeshMarooTestnetChainProvider().identity
    }
}

private final class LockedSuffixGenerator: @unchecked Sendable {
    private let lock = NSLock()
    private var suffixes: [String]

    init(_ suffixes: [String]) {
        self.suffixes = suffixes
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        return suffixes.removeFirst()
    }
}
