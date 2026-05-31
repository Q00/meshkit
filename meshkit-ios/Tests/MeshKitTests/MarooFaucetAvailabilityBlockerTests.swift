import XCTest
@testable import MeshKit

final class MarooFaucetAvailabilityBlockerTests: XCTestCase {
    func testMarooFaucetAvailabilityFailureCreatesBlockedByExternalChainEvidence() throws {
        let check = try MeshMarooTestnetFaucetAvailabilityCheck()
        let requestHash = MeshPayloadHash(value: String(repeating: "c", count: 64))

        let evidence = try check.blockerEvidence(
            observedAt: "2026-05-31T01:02:03Z",
            message: "maroo faucet did not return a usable funding response",
            requestHash: requestHash,
            requestNonce: "nonce-maroo-faucet-blocker",
            anchoringReference: "maroo-anchor-ios-grocery-faucet-001"
        )
        let extensionFields = evidence.providerExtensionFields

        XCTAssertEqual(evidence.exitCondition, MeshExternalChainBlockerEvidence.exitCondition)
        XCTAssertEqual(evidence.blockerType, .faucetUnavailable)
        XCTAssertEqual(evidence.identity.provider, "maroo")
        XCTAssertEqual(evidence.identity.network, "maroo-testnet")
        XCTAssertEqual(evidence.identity.chainId, "maroo-testnet-1")
        XCTAssertEqual(evidence.endpoint?.absoluteString, "https://faucet.maroo.io")
        XCTAssertEqual(evidence.operation, "faucet HEAD")
        XCTAssertEqual(evidence.requestHash, requestHash)
        XCTAssertEqual(evidence.requestNonce, "nonce-maroo-faucet-blocker")
        XCTAssertEqual(evidence.anchoringReference, "maroo-anchor-ios-grocery-faucet-001")
        XCTAssertEqual(extensionFields["exitCondition"], "BlockedByExternalChain")
        XCTAssertEqual(extensionFields["blockerType"], "faucet_unavailable")
        XCTAssertEqual(extensionFields["endpoint"], "https://faucet.maroo.io")
        XCTAssertEqual(extensionFields["operation"], "faucet HEAD")
    }

    func testMarooFaucetHTTPFailureStatusConvertsToFaucetUnavailableEvidence() throws {
        let check = try MeshMarooTestnetFaucetAvailabilityCheck()

        let evidence = try XCTUnwrap(check.evaluateHTTPStatus(
            503,
            observedAt: "2026-05-31T01:03:04Z"
        ))

        XCTAssertEqual(evidence.exitCondition, "BlockedByExternalChain")
        XCTAssertEqual(evidence.blockerType, .faucetUnavailable)
        XCTAssertEqual(evidence.endpoint?.absoluteString, "https://faucet.maroo.io")
        XCTAssertEqual(evidence.operation, "faucet HEAD")
        XCTAssertEqual(evidence.message, "faucet HEAD unavailable with http status 503")
    }

    func testMarooFaucetTransportFailureConvertsToFaucetUnavailableEvidence() throws {
        let check = try MeshMarooTestnetFaucetAvailabilityCheck()

        let evidence = try XCTUnwrap(check.evaluateHTTPStatus(
            nil,
            observedAt: "2026-05-31T01:04:05Z",
            errorMessage: "curl timed out reaching maroo faucet"
        ))

        XCTAssertEqual(evidence.blockerType, .faucetUnavailable)
        XCTAssertEqual(evidence.message, "curl timed out reaching maroo faucet")
        XCTAssertEqual(evidence.providerExtensionFields["blockerType"], "faucet_unavailable")
    }

    func testMarooFaucetSuccessfulHTTPStatusDoesNotCreateBlockerEvidence() throws {
        let check = try MeshMarooTestnetFaucetAvailabilityCheck()

        let evidence = try check.evaluateHTTPStatus(
            204,
            observedAt: "2026-05-31T01:05:06Z"
        )

        XCTAssertNil(evidence)
    }
}
