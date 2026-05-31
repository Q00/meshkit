import XCTest
@testable import MeshKit

final class MarooOKRWContractAvailabilityBlockerTests: XCTestCase {
    func testMarooOKRWContractAvailabilityFailureCreatesBlockedByExternalChainEvidence() throws {
        let check = try MeshMarooTestnetOKRWContractAvailabilityCheck(
            contractAddress: "0x1111111111111111111111111111111111111111"
        )
        let requestHash = MeshPayloadHash(value: String(repeating: "e", count: 64))

        let evidence = try check.blockerEvidence(
            observedAt: "2026-05-31T03:02:03Z",
            message: "maroo OKRW contract did not return deployed bytecode",
            requestHash: requestHash,
            requestNonce: "nonce-maroo-okrw-contract-blocker",
            anchoringReference: "maroo-anchor-ios-grocery-okrw-contract-001"
        )
        let extensionFields = evidence.providerExtensionFields

        XCTAssertEqual(evidence.exitCondition, MeshExternalChainBlockerEvidence.exitCondition)
        XCTAssertEqual(evidence.blockerType, .okrwContractUnavailable)
        XCTAssertEqual(evidence.identity.provider, "maroo")
        XCTAssertEqual(evidence.identity.network, "maroo-testnet")
        XCTAssertEqual(evidence.identity.chainId, "maroo-testnet-1")
        XCTAssertEqual(evidence.endpoint?.absoluteString, "https://rpc-testnet.maroo.io")
        XCTAssertEqual(evidence.operation, "eth_getCode OKRW")
        XCTAssertEqual(evidence.requestHash, requestHash)
        XCTAssertEqual(evidence.requestNonce, "nonce-maroo-okrw-contract-blocker")
        XCTAssertEqual(evidence.anchoringReference, "maroo-anchor-ios-grocery-okrw-contract-001")
        XCTAssertEqual(extensionFields["exitCondition"], "BlockedByExternalChain")
        XCTAssertEqual(extensionFields["blockerType"], "okrw_contract_unavailable")
        XCTAssertEqual(extensionFields["endpoint"], "https://rpc-testnet.maroo.io")
        XCTAssertEqual(extensionFields["operation"], "eth_getCode OKRW")
    }

    func testMarooOKRWContractHTTPFailureStatusConvertsToContractUnavailableEvidence() throws {
        let check = try MeshMarooTestnetOKRWContractAvailabilityCheck(
            contractAddress: "0x2222222222222222222222222222222222222222"
        )

        let evidence = try XCTUnwrap(check.evaluateHTTPStatus(
            503,
            observedAt: "2026-05-31T03:03:04Z"
        ))

        XCTAssertEqual(evidence.exitCondition, "BlockedByExternalChain")
        XCTAssertEqual(evidence.blockerType, .okrwContractUnavailable)
        XCTAssertEqual(evidence.endpoint?.absoluteString, "https://rpc-testnet.maroo.io")
        XCTAssertEqual(evidence.operation, "eth_getCode OKRW")
        XCTAssertEqual(evidence.message, "eth_getCode OKRW unavailable with http status 503")
    }

    func testMarooOKRWContractTransportFailureConvertsToContractUnavailableEvidence() throws {
        let check = try MeshMarooTestnetOKRWContractAvailabilityCheck(
            contractAddress: "0x3333333333333333333333333333333333333333"
        )

        let evidence = try XCTUnwrap(check.evaluateHTTPStatus(
            nil,
            observedAt: "2026-05-31T03:04:05Z",
            errorMessage: "curl timed out reading maroo OKRW contract bytecode"
        ))

        XCTAssertEqual(evidence.blockerType, .okrwContractUnavailable)
        XCTAssertEqual(evidence.message, "curl timed out reading maroo OKRW contract bytecode")
        XCTAssertEqual(evidence.providerExtensionFields["blockerType"], "okrw_contract_unavailable")
    }

    func testMarooOKRWContractEmptyBytecodeConvertsToContractUnavailableEvidence() throws {
        let check = try MeshMarooTestnetOKRWContractAvailabilityCheck(
            contractAddress: "0x4444444444444444444444444444444444444444"
        )

        let evidence = try XCTUnwrap(check.evaluateJSONRPCResponse(
            httpStatus: 200,
            result: "0x",
            observedAt: "2026-05-31T03:05:06Z"
        ))

        XCTAssertEqual(evidence.blockerType, .okrwContractUnavailable)
        XCTAssertEqual(evidence.operation, "eth_getCode OKRW")
        XCTAssertEqual(evidence.message, "eth_getCode OKRW returned no deployed OKRW contract bytecode")
    }

    func testMarooOKRWContractDeployedBytecodeDoesNotCreateBlockerEvidence() throws {
        let check = try MeshMarooTestnetOKRWContractAvailabilityCheck(
            contractAddress: "0x5555555555555555555555555555555555555555"
        )

        let evidence = try check.evaluateJSONRPCResponse(
            httpStatus: 200,
            result: "0x60016000",
            observedAt: "2026-05-31T03:06:07Z"
        )

        XCTAssertNil(evidence)
    }

    func testMarooOKRWContractAvailabilityCheckRequiresContractAddress() throws {
        XCTAssertThrowsError(
            try MeshMarooTestnetOKRWContractAvailabilityCheck(contractAddress: "okrw")
        ) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProviderIdentity("contractAddress"))
        }
    }
}
