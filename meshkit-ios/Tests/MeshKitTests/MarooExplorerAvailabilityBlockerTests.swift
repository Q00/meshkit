import XCTest
@testable import MeshKit

final class MarooExplorerAvailabilityBlockerTests: XCTestCase {
    func testMarooExplorerAvailabilityFailureCreatesBlockedByExternalChainEvidence() throws {
        let check = try MeshMarooTestnetExplorerAvailabilityCheck()
        let requestHash = MeshPayloadHash(value: String(repeating: "e", count: 64))

        let evidence = try check.blockerEvidence(
            observedAt: "2026-05-31T03:02:03Z",
            message: "maroo explorer did not return a usable transaction lookup response",
            requestHash: requestHash,
            requestNonce: "nonce-maroo-explorer-blocker",
            anchoringReference: "maroo-anchor-ios-grocery-explorer-001",
            txHash: "0xexplorerblocker001"
        )
        let extensionFields = evidence.providerExtensionFields

        XCTAssertEqual(evidence.exitCondition, MeshExternalChainBlockerEvidence.exitCondition)
        XCTAssertEqual(evidence.blockerType, .explorerUnavailable)
        XCTAssertEqual(evidence.identity.provider, "maroo")
        XCTAssertEqual(evidence.identity.network, "maroo-testnet")
        XCTAssertEqual(evidence.identity.chainId, "maroo-testnet-1")
        XCTAssertEqual(evidence.endpoint?.absoluteString, "https://explorer-testnet.maroo.io")
        XCTAssertEqual(evidence.operation, "explorer HEAD")
        XCTAssertEqual(evidence.requestHash, requestHash)
        XCTAssertEqual(evidence.requestNonce, "nonce-maroo-explorer-blocker")
        XCTAssertEqual(evidence.anchoringReference, "maroo-anchor-ios-grocery-explorer-001")
        XCTAssertEqual(evidence.txHash, "0xexplorerblocker001")
        XCTAssertEqual(extensionFields["exitCondition"], "BlockedByExternalChain")
        XCTAssertEqual(extensionFields["blockerType"], "explorer_unavailable")
        XCTAssertEqual(extensionFields["endpoint"], "https://explorer-testnet.maroo.io")
        XCTAssertEqual(extensionFields["operation"], "explorer HEAD")
        XCTAssertEqual(extensionFields["txHash"], "0xexplorerblocker001")
    }

    func testMarooExplorerHTTPFailureStatusConvertsToExplorerUnavailableEvidence() throws {
        let check = try MeshMarooTestnetExplorerAvailabilityCheck()

        let evidence = try XCTUnwrap(check.evaluateHTTPStatus(
            503,
            observedAt: "2026-05-31T03:03:04Z"
        ))

        XCTAssertEqual(evidence.exitCondition, "BlockedByExternalChain")
        XCTAssertEqual(evidence.blockerType, .explorerUnavailable)
        XCTAssertEqual(evidence.endpoint?.absoluteString, "https://explorer-testnet.maroo.io")
        XCTAssertEqual(evidence.operation, "explorer HEAD")
        XCTAssertEqual(evidence.message, "explorer HEAD unavailable with http status 503")
        XCTAssertEqual(evidence.providerExtensionFields["blockerType"], "explorer_unavailable")
    }

    func testMarooExplorerTransportFailureConvertsToExplorerUnavailableEvidence() throws {
        let check = try MeshMarooTestnetExplorerAvailabilityCheck()

        let evidence = try XCTUnwrap(check.evaluateHTTPStatus(
            nil,
            observedAt: "2026-05-31T03:04:05Z",
            errorMessage: "curl timed out reaching maroo explorer"
        ))

        XCTAssertEqual(evidence.blockerType, .explorerUnavailable)
        XCTAssertEqual(evidence.message, "curl timed out reaching maroo explorer")
        XCTAssertEqual(evidence.providerExtensionFields["blockerType"], "explorer_unavailable")
    }

    func testMarooExplorerSuccessfulHTTPStatusDoesNotCreateBlockerEvidence() throws {
        let check = try MeshMarooTestnetExplorerAvailabilityCheck()

        let evidence = try check.evaluateHTTPStatus(
            200,
            observedAt: "2026-05-31T03:05:06Z"
        )

        XCTAssertNil(evidence)
    }

    func testMarooExplorerAvailabilityCheckRequiresExplorerEndpoint() throws {
        let provider = try MeshMarooTestnetChainProvider(
            configuredRPCEndpoint: MeshMarooTestnetChainProvider.defaultRPCEndpoint,
            configuredExplorerBaseURL: nil
        )

        XCTAssertThrowsError(try MeshMarooTestnetExplorerAvailabilityCheck(chainProvider: provider)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .chainProviderExplorerUnavailable)
        }
    }
}
