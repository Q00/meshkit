import CryptoKit
import XCTest
@testable import MeshKit

final class DailyMartRequestPayloadHashValidatorTests: XCTestCase {
    func testDailyMartPayloadHashValidatorAcceptsMatchingHash() throws {
        let request = signedDailyMartRequest(nonce: "nonce-dailymart-payload-hash-match")
        let validator = DailyMartRequestPayloadHashValidator()

        XCTAssertNoThrow(try validator.validate(request))
        XCTAssertEqual(
            DailyMartRequestPayloadHashValidator.expectedPayloadHash(for: request),
            request.payloadHash
        )
    }

    func testDailyMartPayloadHashValidatorRejectsHashMismatch() throws {
        let request = signedDailyMartRequest(
            nonce: "nonce-dailymart-payload-hash-mismatch",
            payloadHash: MeshPayloadHash(value: String(repeating: "0", count: 64))
        )
        let validator = DailyMartRequestPayloadHashValidator()

        XCTAssertThrowsError(try validator.validate(request)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .payloadHashMismatch)
        }
    }

    func testDailyMartVerifierRejectsHashMismatchBeforeExecution() throws {
        let request = signedDailyMartRequest(
            nonce: "nonce-dailymart-verifier-hash-mismatch",
            payloadHash: MeshPayloadHash(value: String(repeating: "f", count: 64))
        )
        let verifier = try DailyMartSignedMCPRequestVerifier(expectedHermesAgentSigner: sampleTrust)

        XCTAssertThrowsError(try verifier.verify(request)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .payloadHashMismatch)
        }
    }

    private let signingKey = Curve25519.Signing.PrivateKey()

    private var sampleTrust: MeshSenderTrust {
        MeshSenderTrust(
            callerAppId: "app.hermes-chat",
            callerBundleId: "ai.meshkit.sample.hermeschat",
            teamId: "DEVTEAMID",
            requestSigningAlgorithm: "Ed25519",
            requestSigningKeyId: "demo-key",
            publicKey: signingKey.publicKey.rawRepresentation.base64EncodedString()
        )
    }

    private func signedDailyMartRequest(
        nonce: String,
        payloadHash: MeshPayloadHash? = nil
    ) -> MeshRequest {
        let unsigned = MeshRequest(
            requestId: "ios-grocery-\(nonce)",
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-sim",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "demo-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                version: "1.0"
            ),
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
            payloadHash: payloadHash,
            nonce: nonce,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            signature: MeshSignature(algorithm: "Ed25519", keyId: "demo-key", value: "")
        )
        let signature = try! signingKey.signature(for: unsigned.signingInputData()).base64EncodedString()
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
