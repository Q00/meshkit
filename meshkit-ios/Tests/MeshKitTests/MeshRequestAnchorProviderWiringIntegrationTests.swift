import CryptoKit
import XCTest
@testable import MeshKit

final class MeshRequestAnchorProviderWiringIntegrationTests: XCTestCase {
    private static let signingKey = Curve25519.Signing.PrivateKey()

    func testSDKProviderWiringResolvesMarooTestnetRequestAnchorAdapterAndSubmitsSignedMCPAnchor() async throws {
        let chainProvider = try MeshMarooTestnetChainProvider(
            capabilities: MeshMarooTestnetRequestAnchorAdapter.defaultCapabilities
        )
        let provider = try MeshRequestAnchorProviderWiring.resolveRequestAnchorProvider(
            chainProviderIdentity: chainProvider.identity,
            status: .pending
        )
        let adapter = try XCTUnwrap(provider as? MeshMarooTestnetRequestAnchorAdapter)
        let request = signedDailyMartRequest(
            requestId: "ios-grocery-provider-wiring-maroo-001",
            nonce: "nonce-provider-wiring-maroo-001"
        )
        let payload = try MeshRequestAnchorPayload(
            metadata: MeshSignedRequestAnchorMetadata(request: request),
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash
        )
        let input = try MeshRequestAnchorSubmitInput(
            payload: payload,
            providerIdentity: provider.identity,
            submittedAt: "2026-05-31T00:00:08Z"
        )

        let output = try await MeshRequestAnchorSubmissionModule(provider: provider).submitAnchor(input)
        let capabilityMetadata = try adapter.capabilityMetadata

        XCTAssertEqual(adapter.providerMetadata.provider, "maroo")
        XCTAssertEqual(adapter.providerMetadata.network, "maroo-testnet")
        XCTAssertEqual(adapter.providerMetadata.chainId, "maroo-testnet-1")
        XCTAssertEqual(capabilityMetadata.adapterId, MeshMarooTestnetRequestAnchorAdapter.adapterId)
        XCTAssertTrue(capabilityMetadata.supports(.anchorSignedRequest))
        XCTAssertEqual(output.anchoringReference.identity.metadata, adapter.providerMetadata)
        XCTAssertEqual(output.anchoringReference.anchorId, "maroo-anchor-ios-grocery-provider-wiring-maroo-001")
        XCTAssertEqual(output.requestHash, payload.metadata.signedRequestHash)
        XCTAssertEqual(output.requestNonce, "nonce-provider-wiring-maroo-001")
        XCTAssertEqual(output.policyId, DailyMartDelegatedSpendingPolicy.policyId)
        XCTAssertEqual(output.policyHash, DailyMartDelegatedSpendingPolicy.policyHash)
        XCTAssertEqual(output.status, .pending)
        XCTAssertEqual(output.submittedAt, "2026-05-31T00:00:08Z")
        XCTAssertEqual(
            output.anchoringReference.explorerURL?.absoluteString,
            "https://explorer-testnet.maroo.io/tx/\(try XCTUnwrap(output.anchoringReference.transactionHash))"
        )
    }

    func testSubmittedMarooRequestAnchorMetadataIsExposedThroughStatusLookupAfterSubmission() async throws {
        let chainProvider = try MeshMarooTestnetChainProvider(
            capabilities: MeshMarooTestnetRequestAnchorAdapter.defaultCapabilities
        )
        let provider = try MeshRequestAnchorProviderWiring.resolveRequestAnchorProvider(
            chainProviderIdentity: chainProvider.identity,
            status: .pending
        )
        let request = signedDailyMartRequest(
            requestId: "ios-grocery-provider-wiring-maroo-metadata-001",
            nonce: "nonce-provider-wiring-maroo-metadata-001"
        )
        let metadata = try MeshSignedRequestAnchorMetadata(request: request)
        let payload = try MeshRequestAnchorPayload(
            metadata: metadata,
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash
        )
        let input = try MeshRequestAnchorSubmitInput(
            payload: payload,
            providerIdentity: provider.identity,
            submittedAt: "2026-05-31T00:00:09Z"
        )

        let output = try await MeshRequestAnchorSubmissionModule(provider: provider).submitAnchor(input)
        let lookedUpAnchor = try await MeshRequestAnchorStatusModule(provider: provider).lookup(
            identifier: output.anchoringReference,
            checkedAt: "2026-05-31T00:00:10Z"
        )

        XCTAssertEqual(lookedUpAnchor.identifier, output.anchoringReference)
        XCTAssertEqual(lookedUpAnchor.metadata, metadata)
        XCTAssertEqual(lookedUpAnchor.payload, payload)
        XCTAssertEqual(lookedUpAnchor.metadata.requestId, request.requestId)
        XCTAssertEqual(lookedUpAnchor.metadata.nonce, request.nonce)
        XCTAssertEqual(lookedUpAnchor.metadata.signature, request.signature)
        XCTAssertEqual(lookedUpAnchor.metadata.signedRequestHash, output.requestHash)
        XCTAssertEqual(lookedUpAnchor.payload?.policyId, output.policyId)
        XCTAssertEqual(lookedUpAnchor.payload?.policyHash, output.policyHash)
        XCTAssertEqual(lookedUpAnchor.submittedAt, input.submittedAt)
        XCTAssertEqual(lookedUpAnchor.observedAt, "2026-05-31T00:00:10Z")
        XCTAssertEqual(lookedUpAnchor.status, .pending)
    }

    private func signedDailyMartRequest(requestId: String, nonce: String) -> MeshRequest {
        let unsigned = MeshRequest(
            requestId: requestId,
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-device",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "demo-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                version: "1.0"
            ),
            payload: [
                "address_ref": "home.saved",
                "budget_krw": "4900",
                "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6"
            ],
            nonce: nonce,
            timestamp: "2026-05-31T00:00:00Z",
            signature: MeshSignature(algorithm: "Ed25519", keyId: "demo-key", value: "")
        )
        let signature = try! Self.signingKey.signature(for: unsigned.signingInputData()).base64EncodedString()
        return MeshRequest(
            requestId: unsigned.requestId,
            caller: unsigned.caller,
            target: unsigned.target,
            payload: unsigned.payload,
            payloadHash: unsigned.payloadHash,
            nonce: unsigned.nonce,
            timestamp: unsigned.timestamp,
            signature: MeshSignature(algorithm: "Ed25519", keyId: "demo-key", value: signature)
        )
    }
}
