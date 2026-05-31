import CryptoKit
import XCTest
@testable import MeshKit

final class MeshRequestPayloadHasherTests: XCTestCase {
    private let signer = MeshRequestSigner(algorithm: "Ed25519", keyId: "sample-ios-ed25519") { data in
        Data(SHA256.hash(data: data))
    }

    func testPayloadHashIsStableForEquivalentPayloadInputs() {
        let firstPayload = [
            "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6",
            "address_ref": "home.saved",
            "budget_krw": "100",
            "policyId": DailyMartDelegatedSpendingPolicy.policyId,
            "policyHash": DailyMartDelegatedSpendingPolicy.policyHash.value
        ]
        let equivalentPayloadWithDifferentInsertionOrder = [
            "policyHash": DailyMartDelegatedSpendingPolicy.policyHash.value,
            "budget_krw": "100",
            "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6",
            "policyId": DailyMartDelegatedSpendingPolicy.policyId,
            "address_ref": "home.saved"
        ]

        XCTAssertEqual(
            MeshRequestPayloadHasher.canonicalData(for: firstPayload),
            MeshRequestPayloadHasher.canonicalData(for: equivalentPayloadWithDifferentInsertionOrder)
        )
        XCTAssertEqual(
            MeshRequestPayloadHasher.hash(for: firstPayload),
            MeshRequestPayloadHasher.hash(for: equivalentPayloadWithDifferentInsertionOrder)
        )
        XCTAssertEqual(
            MeshRequest.sha256HexForPayload(firstPayload),
            MeshRequestPayloadHasher.hash(for: firstPayload).value
        )
    }

    func testNonceBoundPayloadHashChangesWhenNonceChanges() {
        let payload = HermesDailyMartInvocationRequestFactory.purchaseEssentialsPayload()

        let firstHash = MeshRequestPayloadHasher.hash(for: payload, nonce: "nonce-ios-grocery-hash-001")
        let secondHash = MeshRequestPayloadHasher.hash(for: payload, nonce: "nonce-ios-grocery-hash-002")

        XCTAssertEqual(firstHash, MeshPayloadHash(
            value: MeshRequest.sha256HexForPayload(payload, nonce: "nonce-ios-grocery-hash-001")
        ))
        XCTAssertNotEqual(firstHash, secondHash)
    }

    func testSignedRequestHashIsStableForEquivalentSignedPayloadInputs() throws {
        let firstRequest = try signedRequest(payload: [
            "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6",
            "address_ref": "home.saved",
            "budget_krw": "100",
            "policyId": DailyMartDelegatedSpendingPolicy.policyId,
            "policyHash": DailyMartDelegatedSpendingPolicy.policyHash.value
        ])
        let equivalentRequest = try signedRequest(payload: [
            "policyHash": DailyMartDelegatedSpendingPolicy.policyHash.value,
            "budget_krw": "100",
            "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6",
            "policyId": DailyMartDelegatedSpendingPolicy.policyId,
            "address_ref": "home.saved"
        ])

        XCTAssertEqual(firstRequest.payloadHash, equivalentRequest.payloadHash)
        XCTAssertEqual(firstRequest.signingInputData(), equivalentRequest.signingInputData())
        XCTAssertEqual(firstRequest.signature, equivalentRequest.signature)
        XCTAssertEqual(
            try MeshRequestAnchorCanonicalization.signedRequestHash(for: firstRequest),
            try MeshRequestAnchorCanonicalization.signedRequestHash(for: equivalentRequest)
        )
    }

    func testSignedRequestHashChangesWhenPayloadMeaningChanges() throws {
        let approvedRequest = try signedRequest(payload: [
            "items": "laundry_detergent:1",
            "address_ref": "home.saved",
            "budget_krw": "100",
            "policyId": DailyMartDelegatedSpendingPolicy.policyId,
            "policyHash": DailyMartDelegatedSpendingPolicy.policyHash.value
        ])
        let changedRequest = try signedRequest(payload: [
            "items": "laundry_detergent:1",
            "address_ref": "home.saved",
            "budget_krw": "101",
            "policyId": DailyMartDelegatedSpendingPolicy.policyId,
            "policyHash": DailyMartDelegatedSpendingPolicy.policyHash.value
        ])

        XCTAssertNotEqual(approvedRequest.payloadHash, changedRequest.payloadHash)
        XCTAssertNotEqual(
            try MeshRequestAnchorCanonicalization.signedRequestHash(for: approvedRequest),
            try MeshRequestAnchorCanonicalization.signedRequestHash(for: changedRequest)
        )
    }

    private func signedRequest(payload: [String: String]) throws -> MeshRequest {
        return try MeshSignedRequestBuilder(
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
            signer: signer
        ).makeRequest(
            requestId: "ios-grocery-hash-stability-001",
            payload: payload,
            nonce: "nonce-hash-stability-001",
            timestamp: "2026-05-31T12:00:00Z"
        )
    }
}
