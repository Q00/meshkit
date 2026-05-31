import CryptoKit
import XCTest
@testable import MeshKit

final class MeshSignedRequestCryptoTests: XCTestCase {
    private let signingKey = Curve25519.Signing.PrivateKey()

    func testProducesRequestSignatureAndVerifiesSignedAppToAppPayload() throws {
        let signer = MeshRequestSigner.ed25519(keyId: "hermes-agent-key", privateKey: signingKey)
        let unsigned = appToAppRequest(
            requestId: "ios-grocery-signature-001",
            nonce: "nonce-ios-grocery-signature-001"
        )

        let signature = try MeshSignedRequestCrypto.makeSignature(for: unsigned, signer: signer)
        let signed = MeshRequest(
            requestId: unsigned.requestId,
            caller: unsigned.caller,
            target: unsigned.target,
            payload: unsigned.payload,
            payloadHash: unsigned.payloadHash,
            nonce: unsigned.nonce,
            timestamp: unsigned.timestamp,
            signature: signature
        )

        XCTAssertEqual(signature.algorithm, "Ed25519")
        XCTAssertEqual(signature.keyId, "hermes-agent-key")
        XCTAssertFalse(signature.value.isEmpty)
        XCTAssertNoThrow(try MeshSignedRequestCrypto.verifySignature(for: signed, trust: trust))
    }

    func testVerificationFailsWhenSignedNonceBoundPayloadIsTampered() throws {
        let signer = MeshRequestSigner.ed25519(keyId: "hermes-agent-key", privateKey: signingKey)
        let signed = try MeshSignedRequestCrypto.sign(
            appToAppRequest(
                requestId: "ios-grocery-signature-002",
                nonce: "nonce-ios-grocery-signature-original"
            ),
            signer: signer
        )
        let tampered = MeshRequest(
            requestId: signed.requestId,
            caller: signed.caller,
            target: signed.target,
            payload: signed.payload,
            payloadHash: signed.payloadHash,
            nonce: "nonce-ios-grocery-signature-tampered",
            timestamp: signed.timestamp,
            signature: signed.signature
        )

        XCTAssertThrowsError(try MeshSignedRequestCrypto.verifySignature(for: tampered, trust: trust)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("invalid request signature"))
        }
    }

    func testVerificationFailsForDifferentTrustKey() throws {
        let signer = MeshRequestSigner.ed25519(keyId: "hermes-agent-key", privateKey: signingKey)
        let signed = try MeshSignedRequestCrypto.sign(
            appToAppRequest(
                requestId: "ios-grocery-signature-003",
                nonce: "nonce-ios-grocery-signature-003"
            ),
            signer: signer
        )
        let otherTrust = MeshSenderTrust(
            callerAppId: "app.hermes-chat",
            callerBundleId: "ai.meshkit.sample.hermeschat",
            teamId: "DEVTEAMID",
            requestSigningAlgorithm: "Ed25519",
            requestSigningKeyId: "hermes-agent-key",
            publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        )

        XCTAssertThrowsError(try MeshSignedRequestCrypto.verifySignature(for: signed, trust: otherTrust)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("invalid request signature"))
        }
    }

    private var trust: MeshSenderTrust {
        MeshSenderTrust(
            callerAppId: "app.hermes-chat",
            callerBundleId: "ai.meshkit.sample.hermeschat",
            teamId: "DEVTEAMID",
            requestSigningAlgorithm: "Ed25519",
            requestSigningKeyId: "hermes-agent-key",
            publicKey: signingKey.publicKey.rawRepresentation.base64EncodedString()
        )
    }

    private func appToAppRequest(requestId: String, nonce: String) -> MeshRequest {
        MeshRequest(
            requestId: requestId,
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ipad-hermes-install",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "hermes-agent-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                version: "1.0"
            ),
            payload: [
                "address_ref": "home",
                "budget_krw": "100",
                "items": "milk,bread,eggs",
                "payment_asset": "OKRW"
            ],
            nonce: nonce,
            timestamp: "2026-05-31T12:00:00Z",
            signature: MeshSignature(algorithm: "Ed25519", keyId: "hermes-agent-key", value: "")
        )
    }
}
