import CryptoKit
import XCTest
@testable import MeshKit

final class DailyMartSignedMCPRequestVerifierTests: XCTestCase {
    func testDailyMartSignatureVerifierAcceptsExpectedSignerAndCanonicalPayloadHash() throws {
        let request = signedDailyMartRequest(nonce: "nonce-dailymart-signature-module-valid")
        let verifier = try DailyMartSignedMCPRequestVerifier(expectedHermesAgentSigner: expectedTrust)

        XCTAssertNoThrow(try verifier.verify(request))
    }

    func testDailyMartSignatureVerifierRejectsTamperedPayload() throws {
        let request = signedDailyMartRequest(nonce: "nonce-dailymart-signature-module-tampered")
        let tampered = MeshRequest(
            requestId: request.requestId,
            caller: request.caller,
            target: request.target,
            payload: request.payload.merging(["budget_krw": "999"]) { _, new in new },
            payloadHash: request.payloadHash,
            nonce: request.nonce,
            timestamp: request.timestamp,
            signature: request.signature
        )
        let verifier = try DailyMartSignedMCPRequestVerifier(expectedHermesAgentSigner: expectedTrust)

        XCTAssertThrowsError(try verifier.verify(tampered)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .payloadHashMismatch)
        }
    }

    func testDailyMartSignatureVerifierRejectsWrongSigner() throws {
        let request = signedDailyMartRequest(
            nonce: "nonce-dailymart-signature-module-wrong-signer",
            signerKeyId: "other-hermes-agent-key",
            signingKey: wrongSigningKey
        )
        let verifier = try DailyMartSignedMCPRequestVerifier(expectedHermesAgentSigner: expectedTrust)

        XCTAssertThrowsError(try verifier.verify(request)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("request signing key id mismatch"))
        }
    }

    private let expectedSigningKey = Curve25519.Signing.PrivateKey()
    private let wrongSigningKey = Curve25519.Signing.PrivateKey()

    private var expectedTrust: MeshSenderTrust {
        MeshSenderTrust(
            callerAppId: "app.hermes-chat",
            callerBundleId: "ai.meshkit.sample.hermeschat",
            teamId: "DEVTEAMID",
            requestSigningAlgorithm: "Ed25519",
            requestSigningKeyId: "demo-key",
            publicKey: expectedSigningKey.publicKey.rawRepresentation.base64EncodedString()
        )
    }

    private func signedDailyMartRequest(
        nonce: String,
        signerKeyId: String = "demo-key",
        signingKey: Curve25519.Signing.PrivateKey? = nil
    ) -> MeshRequest {
        let key = signingKey ?? expectedSigningKey
        let unsigned = MeshRequest(
            requestId: "ios-grocery-\(nonce)",
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ipad-real-device",
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
            nonce: nonce,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            signature: MeshSignature(algorithm: "Ed25519", keyId: signerKeyId, value: "")
        )
        let signature = try! key.signature(for: unsigned.signingInputData()).base64EncodedString()
        return MeshRequest(
            requestId: unsigned.requestId,
            caller: unsigned.caller,
            target: unsigned.target,
            payload: unsigned.payload,
            payloadHash: unsigned.payloadHash,
            nonce: unsigned.nonce,
            timestamp: unsigned.timestamp,
            signature: MeshSignature(algorithm: "Ed25519", keyId: signerKeyId, value: signature)
        )
    }
}
