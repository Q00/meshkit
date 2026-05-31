import CryptoKit
import XCTest
@testable import MeshKit

final class DailyMartRequestNonceFreshnessStoreTests: XCTestCase {
    private let referenceDate = ISO8601DateFormatter().date(from: "2026-05-31T12:00:00Z")!
    private let signingKey = Curve25519.Signing.PrivateKey()

    func testDailyMartNonceFreshnessStoreAcceptsWellFormedFreshSignedRequest() throws {
        let store = DailyMartRequestNonceFreshnessStore(
            expirationValidator: DailyMartRequestNonceExpirationValidator(maxAgeSeconds: 300)
        )
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-fresh-signed-001",
            nonce: "nonce-dailymart-fresh-signed-001",
            timestamp: "2026-05-31T11:59:00Z"
        )

        XCTAssertEqual(
            try store.acceptFreshNonce(for: request, now: referenceDate),
            "nonce-dailymart-fresh-signed-001"
        )
    }

    func testDailyMartNonceFreshnessStoreAcceptsNewNonces() throws {
        let store = DailyMartRequestNonceFreshnessStore()
        let first = dailyMartRequest(requestId: "ios-grocery-001", nonce: "nonce-dailymart-fresh-001")
        let second = dailyMartRequest(requestId: "ios-grocery-002", nonce: "nonce-dailymart-fresh-002")

        XCTAssertEqual(try store.acceptFreshNonce(for: first), "nonce-dailymart-fresh-001")
        XCTAssertEqual(try store.acceptFreshNonce(for: second), "nonce-dailymart-fresh-002")
    }

    func testDailyMartNonceFreshnessStoreRejectsReusedNonce() throws {
        let store = DailyMartRequestNonceFreshnessStore()
        let original = dailyMartRequest(requestId: "ios-grocery-003", nonce: "nonce-dailymart-replay")
        let replay = dailyMartRequest(requestId: "ios-grocery-004", nonce: "nonce-dailymart-replay")

        try store.acceptFreshNonce(for: original)

        XCTAssertThrowsError(try store.acceptFreshNonce(for: replay)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .replayDetected("nonce-dailymart-replay"))
        }
    }

    func testDailyMartNonceFreshnessScopeIncludesCallerAndCapability() throws {
        let store = DailyMartRequestNonceFreshnessStore()
        let dailyMart = dailyMartRequest(requestId: "ios-grocery-005", nonce: "nonce-shared-across-scope")
        let otherCapability = MeshRequest(
            requestId: "ios-grocery-006",
            caller: dailyMart.caller,
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.check_inventory",
                version: "1.0"
            ),
            payload: dailyMart.payload,
            nonce: dailyMart.nonce,
            timestamp: dailyMart.timestamp,
            signature: dailyMart.signature
        )

        XCTAssertNoThrow(try store.acceptFreshNonce(for: dailyMart))
        XCTAssertNoThrow(try store.acceptFreshNonce(for: otherCapability))
    }

    func testDailyMartNonceExpirationAcceptsNonExpiredNonce() throws {
        let validator = DailyMartRequestNonceExpirationValidator(maxAgeSeconds: 300)
        let request = dailyMartRequest(
            requestId: "ios-grocery-nonce-expiry-001",
            nonce: "nonce-dailymart-not-expired",
            timestamp: "2026-05-31T11:56:00Z"
        )

        XCTAssertNoThrow(try validator.validate(request, now: referenceDate))
    }

    func testDailyMartNonceExpirationRejectsExpiredNonce() throws {
        let validator = DailyMartRequestNonceExpirationValidator(maxAgeSeconds: 300)
        let request = dailyMartRequest(
            requestId: "ios-grocery-nonce-expiry-002",
            nonce: "nonce-dailymart-expired",
            timestamp: "2026-05-31T11:54:59Z"
        )

        XCTAssertThrowsError(try validator.validate(request, now: referenceDate)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .staleTimestamp)
        }
    }

    func testDailyMartNonceFreshnessStoreRejectsExpiredNonceBeforeReplayReservation() throws {
        let store = DailyMartRequestNonceFreshnessStore(
            expirationValidator: DailyMartRequestNonceExpirationValidator(maxAgeSeconds: 300)
        )
        let expired = dailyMartRequest(
            requestId: "ios-grocery-nonce-expiry-003",
            nonce: "nonce-dailymart-expired-before-replay",
            timestamp: "2026-05-31T11:54:59Z"
        )
        let retryWithCurrentTimestamp = dailyMartRequest(
            requestId: "ios-grocery-nonce-expiry-004",
            nonce: "nonce-dailymart-expired-before-replay",
            timestamp: "2026-05-31T11:59:59Z"
        )

        XCTAssertThrowsError(try store.acceptFreshNonce(for: expired, now: referenceDate)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .staleTimestamp)
        }
        XCTAssertEqual(
            try store.acceptFreshNonce(for: retryWithCurrentTimestamp, now: referenceDate),
            "nonce-dailymart-expired-before-replay"
        )
    }

    func testDailyMartNonceFreshnessStoreRejectsMalformedNonceBeforeReplayReservation() throws {
        let store = DailyMartRequestNonceFreshnessStore(
            expirationValidator: DailyMartRequestNonceExpirationValidator(maxAgeSeconds: 300)
        )
        let malformed = dailyMartRequest(
            requestId: "ios-grocery-nonce-malformed-001",
            nonce: "nonce/dailymart/malformed",
            timestamp: "2026-05-31T11:59:59Z"
        )

        XCTAssertThrowsError(try store.acceptFreshNonce(for: malformed, now: referenceDate)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidSecurityField("nonce"))
        }
    }

    private func dailyMartRequest(
        requestId: String,
        nonce: String,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) -> MeshRequest {
        MeshRequest(
            requestId: requestId,
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
            payload: [
                "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6",
                "address_ref": "home.saved",
                "budget_krw": "100"
            ],
            nonce: nonce,
            timestamp: timestamp,
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "sample-ios-ed25519",
                value: "demo-signature"
            )
        )
    }

    private func signedDailyMartRequest(
        requestId: String,
        nonce: String,
        timestamp: String
    ) throws -> MeshRequest {
        try MeshSignedRequestBuilder(
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ipad-real-device",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "demo-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                version: "1.0"
            ),
            signer: MeshRequestSigner.ed25519(keyId: "demo-key", privateKey: signingKey)
        ).makeRequest(
            requestId: requestId,
            payload: [
                "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6",
                "address_ref": "home.saved",
                "budget_krw": "100",
                "merchantScope": DailyMartDelegatedSpendingPolicy.merchantScope,
                "capabilityScope": DailyMartDelegatedSpendingPolicy.capabilityScope,
                "consentGrantId": DailyMartDelegatedSpendingPolicy.consentGrantId,
                "walletSessionId": DailyMartDelegatedSpendingPolicy.walletSessionId,
                "principalId": DailyMartDelegatedSpendingPolicy.principalId,
                "policyId": DailyMartDelegatedSpendingPolicy.policyId,
                "policyHash": DailyMartDelegatedSpendingPolicy.policyHash.value
            ],
            nonce: nonce,
            timestamp: timestamp
        )
    }
}
