import CryptoKit
import XCTest
@testable import MeshKit

final class MeshRequestAnchorResolutionModuleTests: XCTestCase {
    private static let signingKey = Curve25519.Signing.PrivateKey()

    func testRequestAnchorResolutionModuleMapsKnownReferenceToOriginalRequestHashAndStatus() async throws {
        let request = signedDailyMartRequest(
            requestId: "ios-anchor-resolution-known",
            nonce: "nonce-anchor-resolution-known"
        )
        let metadata = try MeshSignedRequestAnchorMetadata(request: request)
        let identifier = try MeshRequestAnchorIdentifier(
            identity: Self.sampleChainProviderIdentity(),
            anchorId: "anchor-ios-anchor-resolution-known",
            transactionHash: "0xknownresolution001"
        )
        let anchor = try MeshRequestAnchor(
            metadata: metadata,
            identifier: identifier,
            status: .confirmed,
            submittedAt: "2026-05-31T00:00:00Z",
            observedAt: "2026-05-31T00:00:01Z"
        )
        let provider = StaticResolvingRequestAnchorProvider(anchorsById: [identifier.anchorId: anchor])
        let module = MeshRequestAnchorResolutionModule(provider: provider)

        let response = try await module.resolveResponse(
            identifier: identifier,
            checkedAt: "2026-05-31T00:00:02Z"
        )
        let requestHash = try await module.resolveRequestHash(
            identifier: identifier,
            checkedAt: "2026-05-31T00:00:02Z"
        )

        XCTAssertEqual(response.outcome, MeshRequestAnchorResolutionOutcome.known)
        XCTAssertEqual(response.identifier, identifier)
        XCTAssertEqual(response.requestHash, metadata.signedRequestHash)
        XCTAssertEqual(response.anchorStatus, .confirmed)
        XCTAssertEqual(response.checkedAt, "2026-05-31T00:00:02Z")
        XCTAssertNil(response.message)
        XCTAssertEqual(requestHash, metadata.signedRequestHash)
        XCTAssertEqual(requestHash, try MeshRequestAnchorCanonicalization.signedRequestHash(for: request))
    }

    func testRequestAnchorResolutionModuleResolvesConfirmedPendingFailedAndUnavailableStates() async throws {
        for expectedStatus in [MeshRequestAnchorStatus.confirmed, .pending, .failed, .unavailable] {
            let request = signedDailyMartRequest(
                requestId: "ios-anchor-resolution-\(expectedStatus.rawValue)",
                nonce: "nonce-anchor-resolution-\(expectedStatus.rawValue)"
            )
            let metadata = try MeshSignedRequestAnchorMetadata(request: request)
            let identifier = try MeshRequestAnchorIdentifier(
                identity: Self.sampleChainProviderIdentity(),
                anchorId: "anchor-ios-anchor-resolution-\(expectedStatus.rawValue)",
                transactionHash: "0xresolution\(expectedStatus.rawValue)"
            )
            let anchor = try MeshRequestAnchor(
                metadata: metadata,
                identifier: identifier,
                status: expectedStatus,
                submittedAt: "2026-05-31T00:00:00Z",
                observedAt: "2026-05-31T00:00:01Z",
                message: expectedStatus == .unavailable ? "anchor status currently unavailable" : nil
            )
            let provider = StaticResolvingRequestAnchorProvider(anchorsById: [identifier.anchorId: anchor])
            let module = MeshRequestAnchorResolutionModule(provider: provider)

            let response = try await module.resolveResponse(
                identifier: identifier,
                checkedAt: "2026-05-31T00:00:02Z"
            )

            XCTAssertEqual(response.outcome, .known)
            XCTAssertEqual(response.identifier, identifier)
            XCTAssertEqual(response.requestHash, metadata.signedRequestHash)
            XCTAssertEqual(response.anchorStatus, expectedStatus)
        }
    }

    func testRequestAnchorResolutionModuleFailsPredictablyForUnknownReference() async throws {
        let provider = StaticResolvingRequestAnchorProvider(anchorsById: [:])
        let module = MeshRequestAnchorResolutionModule(provider: provider)
        let unknownReference = try MeshRequestAnchorIdentifier(
            identity: Self.sampleChainProviderIdentity(),
            anchorId: "anchor-unknown-resolution",
            transactionHash: "0xunknownresolution001"
        )

        let response = try await module.resolveResponse(
            identifier: unknownReference,
            checkedAt: "2026-05-31T00:00:02Z"
        )

        XCTAssertEqual(response.outcome, MeshRequestAnchorResolutionOutcome.unknownReference)
        XCTAssertEqual(response.identifier, unknownReference)
        XCTAssertNil(response.requestHash)
        XCTAssertNil(response.anchorStatus)
        XCTAssertEqual(response.message, "unknown anchoring reference")

        do {
            _ = try await module.resolveRequestHash(
                identifier: unknownReference,
                checkedAt: "2026-05-31T00:00:02Z"
            )
            XCTFail("Expected unknown anchoring reference to fail with requestAnchorReferenceNotFound")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .requestAnchorReferenceNotFound("anchor-unknown-resolution"))
        }
    }

    func testRequestAnchorResolutionModuleRequiresAdvertisedCapability() async throws {
        let provider = StaticResolvingRequestAnchorProvider(
            capabilities: [.lookupRequestAnchorStatus],
            anchorsById: [:]
        )
        let module = MeshRequestAnchorResolutionModule(provider: provider)
        let identifier = try MeshRequestAnchorIdentifier(
            identity: Self.sampleChainProviderIdentity(),
            anchorId: "anchor-resolution-unsupported"
        )

        do {
            _ = try await module.resolveResponse(
                identifier: identifier,
                checkedAt: "2026-05-31T00:00:02Z"
            )
            XCTFail("Expected request anchor resolution to require resolveRequestAnchorHash capability")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }
    }

    private struct StaticResolvingRequestAnchorProvider: MeshRequestAnchorProvider {
        let identity: MeshChainProviderIdentity
        let capabilities: [MeshChainProviderCapability]
        let anchorsById: [String: MeshRequestAnchor]

        init(
            identity: MeshChainProviderIdentity = try! MeshRequestAnchorResolutionModuleTests.sampleChainProviderIdentity(),
            capabilities: [MeshChainProviderCapability] = [.lookupRequestAnchorStatus, .resolveRequestAnchorHash],
            anchorsById: [String: MeshRequestAnchor]
        ) {
            self.identity = identity
            self.capabilities = capabilities
            self.anchorsById = anchorsById
        }

        func anchorSignedRequest(
            metadata: MeshSignedRequestAnchorMetadata,
            submittedAt: String
        ) async throws -> MeshRequestAnchor {
            try MeshChainProviderConfiguration(identity: identity, capabilities: capabilities).require(.anchorSignedRequest)
            return try MeshRequestAnchor(
                metadata: metadata,
                identifier: MeshRequestAnchorIdentifier(identity: identity, anchorId: "anchor-\(metadata.requestId)"),
                status: .submitted,
                submittedAt: submittedAt,
                observedAt: submittedAt
            )
        }

        func requestAnchorStatus(
            identifier: MeshRequestAnchorIdentifier,
            checkedAt: String
        ) async throws -> MeshRequestAnchor {
            try MeshChainProviderConfiguration(identity: identity, capabilities: capabilities).require(.lookupRequestAnchorStatus)
            try identifier.validate()
            guard identifier.identity.metadata == identity.metadata else {
                throw MeshKitValidationError.signatureMismatch("request anchor provider metadata mismatch")
            }
            guard let anchor = anchorsById[identifier.anchorId] else {
                throw MeshKitValidationError.requestAnchorReferenceNotFound(identifier.anchorId)
            }
            return anchor
        }
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

    private static func sampleChainProviderIdentity() throws -> MeshChainProviderIdentity {
        try MeshChainProviderIdentity(
            providerName: "maroo",
            networkIdentity: "maroo-testnet",
            chainId: "maroo-testnet-1",
            rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc-testnet.example.invalid")),
            explorerBaseURL: try XCTUnwrap(URL(string: "https://explorer-testnet.example.invalid"))
        )
    }
}
