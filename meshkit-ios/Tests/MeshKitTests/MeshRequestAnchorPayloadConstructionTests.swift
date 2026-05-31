import CryptoKit
import XCTest
@testable import MeshKit

final class MeshRequestAnchorPayloadConstructionTests: XCTestCase {
    private let signer = MeshRequestSigner(algorithm: "Ed25519", keyId: "hermes-anchor-payload-key") { data in
        Data(SHA256.hash(data: data))
    }

    func testRequestAnchorPayloadConstructionBindsRequestNoncePolicyIdAndPolicyHash() throws {
        let request = try signedDailyMartRequest()
        let metadata = try MeshSignedRequestAnchorMetadata(request: request)
        let policyId = "policy-hermes-dailymart-okrw-v1-payload-binding"
        let policyHash = MeshPayloadHash(value: String(repeating: "7", count: 64))

        let payload = try MeshRequestAnchorPayload(
            metadata: metadata,
            policyId: policyId,
            policyHash: policyHash
        )
        let encoded = try JSONEncoder().encode(payload)
        let payloadJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let encodedPolicyHash = try XCTUnwrap(payloadJSON["policyHash"] as? [String: Any])

        XCTAssertEqual(payload.requestNonce, "nonce-anchor-payload-binding-001")
        XCTAssertEqual(payload.requestNonce, metadata.nonce)
        XCTAssertEqual(payload.policyId, policyId)
        XCTAssertEqual(payload.policyHash, policyHash)
        XCTAssertEqual(payloadJSON["requestNonce"] as? String, "nonce-anchor-payload-binding-001")
        XCTAssertEqual(payloadJSON["policyId"] as? String, policyId)
        XCTAssertEqual(encodedPolicyHash["value"] as? String, policyHash.value)
    }

    func testExtractedAnchoringFieldsMapIntoSubmitAnchorInputShape() throws {
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-anchor-payload-submit-input-001",
            nonce: "nonce-anchor-payload-submit-input-001"
        )
        let providerIdentity = try chainProviderIdentity()
        let payload = try MeshRequestAnchorPayload(
            metadata: MeshSignedRequestAnchorMetadata(request: request),
            policyId: "policy-hermes-dailymart-okrw-v1-payload-binding",
            policyHash: MeshPayloadHash(value: String(repeating: "7", count: 64))
        )
        let extractedFields = try payload.signedMCPRequestAnchoringFields()

        let submitInput = try MeshRequestAnchorSubmitInput(
            payload: payload,
            anchoringFields: extractedFields,
            providerIdentity: providerIdentity,
            submittedAt: "2026-05-31T12:09:00Z"
        )

        XCTAssertEqual(submitInput.signedMCPRequestHash, extractedFields.signedMCPRequestHash)
        XCTAssertEqual(submitInput.requestNonce, extractedFields.requestNonce)
        XCTAssertEqual(submitInput.policyId, extractedFields.policyId)
        XCTAssertEqual(submitInput.policyHash, extractedFields.policyHash)
        XCTAssertEqual(submitInput.payload, payload)
        XCTAssertEqual(submitInput.providerMetadata, providerIdentity.metadata)
        XCTAssertEqual(submitInput.submittedAt, "2026-05-31T12:09:00Z")
    }

    func testSubmitAnchorInputConstructionRejectsExtractedFieldPayloadMismatch() throws {
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-anchor-payload-submit-input-002",
            nonce: "nonce-anchor-payload-submit-input-002"
        )
        let payload = try MeshRequestAnchorPayload(
            metadata: MeshSignedRequestAnchorMetadata(request: request),
            policyId: "policy-hermes-dailymart-okrw-v1-payload-binding",
            policyHash: MeshPayloadHash(value: String(repeating: "7", count: 64))
        )
        let mismatchedFields = try MeshSignedMCPRequestAnchoringFields(
            signedMCPRequestHash: payload.metadata.signedRequestHash,
            requestNonce: "nonce-anchor-payload-submit-input-mismatch",
            policyId: payload.policyId,
            policyHash: payload.policyHash
        )

        XCTAssertThrowsError(
            try MeshRequestAnchorSubmitInput(
                payload: payload,
                anchoringFields: mismatchedFields,
                providerIdentity: chainProviderIdentity(),
                submittedAt: "2026-05-31T12:10:00Z"
            )
        ) { error in
            XCTAssertEqual(
                error as? MeshKitValidationError,
                .signatureMismatch("signed MCP request anchoring fields payload linkage mismatch")
            )
        }
    }

    func testRequestAnchorPayloadRejectsNonceThatDoesNotMatchSignedRequestMetadata() throws {
        let request = try signedDailyMartRequest()
        let payload = try MeshRequestAnchorPayload(
            metadata: MeshSignedRequestAnchorMetadata(request: request),
            policyId: "policy-hermes-dailymart-okrw-v1-payload-binding",
            policyHash: MeshPayloadHash(value: String(repeating: "7", count: 64))
        )
        let encoded = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var tampered = json
        tampered["requestNonce"] = "nonce-anchor-payload-binding-tampered"
        let tamperedData = try JSONSerialization.data(withJSONObject: tampered, options: [.sortedKeys])

        XCTAssertThrowsError(try JSONDecoder().decode(MeshRequestAnchorPayload.self, from: tamperedData)) { error in
            XCTAssertEqual(
                error as? MeshKitValidationError,
                .signatureMismatch("request anchor payload nonce mismatch")
            )
        }
    }

    private func signedDailyMartRequest(
        requestId: String = "ios-grocery-anchor-payload-binding-001",
        nonce: String = "nonce-anchor-payload-binding-001"
    ) throws -> MeshRequest {
        try MeshSignedRequestBuilder(
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ipad-device",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "hermes-anchor-payload-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                version: "1.0"
            ),
            signer: signer
        ).makeRequest(
            requestId: requestId,
            payload: [
                "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6",
                "address_ref": "home.saved",
                "budget_krw": "100",
                "policyId": "policy-hermes-dailymart-okrw-v1-payload-binding",
                "policyHash": String(repeating: "7", count: 64)
            ],
            nonce: nonce,
            timestamp: "2026-05-31T12:08:00Z"
        )
    }

    private func chainProviderIdentity() throws -> MeshChainProviderIdentity {
        try MeshChainProviderIdentity(
            providerName: "mock-chain",
            networkIdentity: "mock-testnet",
            chainId: "mock-testnet-1",
            rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc.mock-chain.example.invalid")),
            explorerBaseURL: try XCTUnwrap(URL(string: "https://explorer.mock-chain.example.invalid"))
        )
    }
}
