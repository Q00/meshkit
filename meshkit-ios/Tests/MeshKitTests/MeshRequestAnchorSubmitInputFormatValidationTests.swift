import CryptoKit
import XCTest
@testable import MeshKit

final class MeshRequestAnchorSubmitInputFormatValidationTests: XCTestCase {
    private let signer = MeshRequestSigner(algorithm: "Ed25519", keyId: "hermes-anchor-submit-format-key") { data in
        Data(SHA256.hash(data: data))
    }

    func testSubmitAnchorRejectsInvalidSignedMCPRequestHashFormat() async throws {
        let input = try decodedSubmitInput(
            overriding: ["signedMCPRequestHash", "value"],
            with: String(repeating: "z", count: 64)
        )

        try await assertSubmitAnchorRejects(
            input,
            expectedError: .invalidChainProviderIdentity("signedMCPRequestHash.value")
        )
    }

    func testSubmitAnchorRejectsInvalidRequestNonceFormat() async throws {
        let input = try decodedSubmitInput(
            overriding: ["requestNonce"],
            with: "nonce with spaces"
        )

        try await assertSubmitAnchorRejects(
            input,
            expectedError: .invalidChainProviderIdentity("requestNonce")
        )
    }

    func testSubmitAnchorRejectsInvalidPolicyIdFormat() async throws {
        let input = try decodedSubmitInput(
            overriding: ["policyId"],
            with: "policy/hermes/dailymart"
        )

        try await assertSubmitAnchorRejects(
            input,
            expectedError: .invalidChainProviderIdentity("policyId")
        )
    }

    func testSubmitAnchorRejectsInvalidPolicyHashFormat() async throws {
        let input = try decodedSubmitInput(
            overriding: ["policyHash", "value"],
            with: "not-a-sha256-policy-hash"
        )

        try await assertSubmitAnchorRejects(
            input,
            expectedError: .invalidChainProviderIdentity("policyHash.value")
        )
    }

    private func assertSubmitAnchorRejects(
        _ input: MeshRequestAnchorSubmitInput,
        expectedError: MeshKitValidationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let module = try MeshRequestAnchorSubmissionModule(provider: rejectingProvider())

        do {
            _ = try await module.submitAnchor(input)
            XCTFail("submitAnchor accepted malformed input", file: file, line: line)
        } catch let error as MeshKitValidationError {
            XCTAssertEqual(error, expectedError, file: file, line: line)
        }
    }

    private func decodedSubmitInput(
        overriding path: [String],
        with value: Any
    ) throws -> MeshRequestAnchorSubmitInput {
        let validInput = try submitInput()
        let data = try JSONEncoder().encode(validInput)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let tampered = try setting(value, at: path, in: json)
        let tamperedData = try JSONSerialization.data(withJSONObject: tampered, options: [.sortedKeys])
        return try JSONDecoder().decode(MeshRequestAnchorSubmitInput.self, from: tamperedData)
    }

    private func setting(
        _ value: Any,
        at path: [String],
        in object: [String: Any]
    ) throws -> [String: Any] {
        guard let key = path.first else { return object }
        var object = object
        if path.count == 1 {
            object[key] = value
            return object
        }

        let child = try XCTUnwrap(object[key] as? [String: Any])
        object[key] = try setting(value, at: Array(path.dropFirst()), in: child)
        return object
    }

    private func submitInput() throws -> MeshRequestAnchorSubmitInput {
        let request = try signedDailyMartRequest()
        let providerIdentity = try chainProviderIdentity()
        let payload = try MeshRequestAnchorPayload(
            metadata: MeshSignedRequestAnchorMetadata(request: request),
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash
        )
        return try MeshRequestAnchorSubmitInput(
            payload: payload,
            providerIdentity: providerIdentity,
            submittedAt: "2026-05-31T12:01:05Z"
        )
    }

    private func signedDailyMartRequest() throws -> MeshRequest {
        try MeshSignedRequestBuilder(
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ipad-device",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "hermes-anchor-submit-format-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                version: "1.0"
            ),
            signer: signer
        ).makeRequest(
            requestId: "ios-grocery-anchor-submit-format-001",
            payload: [
                "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6",
                "address_ref": "home.saved",
                "budget_krw": "100",
                "policyId": DailyMartDelegatedSpendingPolicy.policyId,
                "policyHash": DailyMartDelegatedSpendingPolicy.policyHash.value
            ],
            nonce: "nonce-anchor-submit-format-001",
            timestamp: "2026-05-31T12:01:00Z"
        )
    }

    private func rejectingProvider() throws -> MeshDemoRequestAnchorProvider {
        try MeshDemoRequestAnchorProvider(identity: chainProviderIdentity(), status: .submitted)
    }

    private func chainProviderIdentity() throws -> MeshChainProviderIdentity {
        try MeshChainProviderIdentity(
            providerName: "demo-chain",
            networkIdentity: "demo-testnet",
            chainId: "demo-testnet-1",
            rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc.demo-chain.example.invalid")),
            explorerBaseURL: try XCTUnwrap(URL(string: "https://explorer.demo-chain.example.invalid"))
        )
    }
}
