import XCTest
@testable import MeshKit

final class MarooRPCAvailabilityBlockerTests: XCTestCase {
    func testMarooRPCAvailabilityFailureCreatesBlockedByExternalChainEvidence() throws {
        let check = try MeshMarooTestnetRPCAvailabilityCheck()
        let requestHash = MeshPayloadHash(value: String(repeating: "d", count: 64))

        let evidence = try check.blockerEvidence(
            observedAt: "2026-05-31T02:02:03Z",
            message: "maroo rpc did not return a usable eth_blockNumber response",
            requestHash: requestHash,
            requestNonce: "nonce-maroo-rpc-blocker",
            anchoringReference: "maroo-anchor-ios-grocery-rpc-001"
        )
        let extensionFields = evidence.providerExtensionFields

        XCTAssertEqual(evidence.exitCondition, MeshExternalChainBlockerEvidence.exitCondition)
        XCTAssertEqual(evidence.blockerType, .rpcUnavailable)
        XCTAssertEqual(evidence.identity.provider, "maroo")
        XCTAssertEqual(evidence.identity.network, "maroo-testnet")
        XCTAssertEqual(evidence.identity.chainId, "maroo-testnet-1")
        XCTAssertEqual(evidence.endpoint?.absoluteString, "https://rpc-testnet.maroo.io")
        XCTAssertEqual(evidence.operation, "eth_blockNumber")
        XCTAssertEqual(evidence.requestHash, requestHash)
        XCTAssertEqual(evidence.requestNonce, "nonce-maroo-rpc-blocker")
        XCTAssertEqual(evidence.anchoringReference, "maroo-anchor-ios-grocery-rpc-001")
        XCTAssertEqual(extensionFields["exitCondition"], "BlockedByExternalChain")
        XCTAssertEqual(extensionFields["blockerType"], "rpc_unavailable")
        XCTAssertEqual(extensionFields["endpoint"], "https://rpc-testnet.maroo.io")
        XCTAssertEqual(extensionFields["operation"], "eth_blockNumber")
    }

    func testMarooRPCHTTPFailureStatusConvertsToRPCUnavailableEvidence() throws {
        let check = try MeshMarooTestnetRPCAvailabilityCheck()

        let evidence = try XCTUnwrap(check.evaluateHTTPStatus(
            503,
            observedAt: "2026-05-31T02:03:04Z"
        ))

        XCTAssertEqual(evidence.exitCondition, "BlockedByExternalChain")
        XCTAssertEqual(evidence.blockerType, .rpcUnavailable)
        XCTAssertEqual(evidence.endpoint?.absoluteString, "https://rpc-testnet.maroo.io")
        XCTAssertEqual(evidence.operation, "eth_blockNumber")
        XCTAssertEqual(evidence.message, "eth_blockNumber unavailable with http status 503")
    }

    func testMarooRPCTransportFailureConvertsToRPCUnavailableEvidence() throws {
        let check = try MeshMarooTestnetRPCAvailabilityCheck()

        let evidence = try XCTUnwrap(check.evaluateHTTPStatus(
            nil,
            observedAt: "2026-05-31T02:04:05Z",
            errorMessage: "curl timed out reaching maroo rpc"
        ))

        XCTAssertEqual(evidence.blockerType, .rpcUnavailable)
        XCTAssertEqual(evidence.message, "curl timed out reaching maroo rpc")
        XCTAssertEqual(evidence.providerExtensionFields["blockerType"], "rpc_unavailable")
    }

    func testMarooRPCUnusableJSONRPCResultConvertsToRPCUnavailableEvidence() throws {
        let check = try MeshMarooTestnetRPCAvailabilityCheck()

        let evidence = try XCTUnwrap(check.evaluateJSONRPCResponse(
            httpStatus: 200,
            result: "not-a-hex-block",
            observedAt: "2026-05-31T02:05:06Z"
        ))

        XCTAssertEqual(evidence.blockerType, .rpcUnavailable)
        XCTAssertEqual(evidence.operation, "eth_blockNumber")
        XCTAssertEqual(evidence.message, "eth_blockNumber returned unusable JSON-RPC result")
    }

    func testMarooRPCSuccessfulJSONRPCResultDoesNotCreateBlockerEvidence() throws {
        let check = try MeshMarooTestnetRPCAvailabilityCheck()

        let evidence = try check.evaluateJSONRPCResponse(
            httpStatus: 200,
            result: "0x1234",
            observedAt: "2026-05-31T02:06:07Z"
        )

        XCTAssertNil(evidence)
    }

    func testMarooNetVersionSuccessfulJSONRPCResultDoesNotCreateBlockerEvidence() throws {
        let check = try MeshMarooTestnetRPCAvailabilityCheck(
            operation: "net_version",
            resultExpectation: .nonEmptyString
        )

        let evidence = try check.evaluateJSONRPCResponse(
            httpStatus: 200,
            result: "1001",
            observedAt: "2026-05-31T02:07:08Z"
        )

        XCTAssertNil(evidence)
    }
}
