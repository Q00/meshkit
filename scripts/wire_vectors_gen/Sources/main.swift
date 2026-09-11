import CryptoKit
import Foundation
import MeshKit

// Generates meshkit-android/vectors/wire-compat.v1.json from the Swift SDK so
// the Kotlin core can prove byte-level wire compatibility. Deterministic:
// fixed key seeds, fixed nonces/timestamps, sorted-keys JSON output.

let requestSeed = Data((0..<32).map { UInt8($0 &+ 1) })
let receiptSeed = Data((0..<32).map { UInt8(0xA0) &+ UInt8($0) })

let requestKey = try Curve25519.Signing.PrivateKey(rawRepresentation: requestSeed)
let receiptKey = try Curve25519.Signing.PrivateKey(rawRepresentation: receiptSeed)

func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

struct VectorCase: Codable {
    let name: String
    let requestEnvelopeBase64: String
    let canonicalPayload: String
    let canonicalPayloadNonceBound: String
    let payloadHashPlain: String
    let payloadHashNonceBound: String
    let requestSigningInput: String
    let requestSignatureBase64: String
    let receiptEnvelopeBase64: String
    let receiptSigningInput: String
    let receiptCanonicalResult: String
    let receiptSignatureBase64: String
}

struct VectorFile: Codable {
    let version: String
    let generator: String
    let requestSignerSeedHex: String
    let requestSignerPublicKeyBase64: String
    let requestSignerKeyId: String
    let receiptSignerSeedHex: String
    let receiptSignerPublicKeyBase64: String
    let receiptSignerKeyId: String
    let cases: [VectorCase]
}

func makeCase(
    name: String,
    requestId: String,
    payload: [String: String],
    nonce: String,
    timestamp: String,
    capability: MeshCapability,
    receiptId: String,
    receiptStatus: String,
    receiptResult: [String: String],
    receiptNonce: String,
    receiptTimestamp: String,
    targetAppId: String
) throws -> VectorCase {
    let caller = MeshIdentity(
        appId: "app.hermes-chat",
        installId: "install-fixed-0001",
        bundleId: "ai.meshkit.sample.hermeschat",
        publicKeyId: "hermes-request-ed25519"
    )
    let unsigned = MeshRequest(
        requestId: requestId,
        caller: caller,
        target: capability,
        payload: payload,
        nonce: nonce,
        timestamp: timestamp,
        signature: MeshSignature(algorithm: "Ed25519", keyId: "hermes-request-ed25519", value: "")
    )
    let signatureValue = try requestKey.signature(for: unsigned.signingInputData()).base64EncodedString()
    let request = MeshRequest(
        requestId: requestId,
        caller: caller,
        target: capability,
        payload: payload,
        nonce: nonce,
        timestamp: timestamp,
        signature: MeshSignature(algorithm: "Ed25519", keyId: "hermes-request-ed25519", value: signatureValue)
    )

    let signer = MeshReceiptSigner.ed25519(keyId: "target-receipt-ed25519", privateKey: receiptKey)
    let receipt = try signer.makeReceipt(
        receiptId: receiptId,
        request: request,
        targetAppId: targetAppId,
        targetBundleId: capability.targetBundleId,
        status: receiptStatus,
        result: receiptResult,
        nonce: receiptNonce,
        timestamp: receiptTimestamp
    )

    return VectorCase(
        name: name,
        requestEnvelopeBase64: try request.encodedForURLScheme(),
        canonicalPayload: String(data: MeshRequest.canonicalPayloadData(payload), encoding: .utf8)!,
        canonicalPayloadNonceBound: String(data: MeshRequestPayloadHasher.canonicalData(for: payload, nonce: nonce), encoding: .utf8)!,
        payloadHashPlain: MeshRequest.sha256HexForPayload(payload),
        payloadHashNonceBound: MeshRequest.sha256HexForPayload(payload, nonce: nonce),
        requestSigningInput: String(data: request.signingInputData(), encoding: .utf8)!,
        requestSignatureBase64: signatureValue,
        receiptEnvelopeBase64: try receipt.encodedForURLScheme(),
        receiptSigningInput: String(data: receipt.signingInputData(), encoding: .utf8)!,
        receiptCanonicalResult: MeshReceipt.canonicalResultString(receiptResult),
        receiptSignatureBase64: receipt.signature.value
    )
}

let dailyMart = try makeCase(
    name: "dailymart_purchase_essentials",
    requestId: "req-dailymart-0001",
    payload: [
        "items": "milk,eggs,bread",
        "address_ref": "addr-home",
        "budget_krw": "100",
        "delivery_window": "today 18:00-20:00",
        "payment_method": "okrw_wallet"
    ],
    nonce: "nonce-dailymart-0001",
    timestamp: "2026-08-24T09:00:00Z",
    capability: MeshCapability(
        targetBundleId: "ai.meshkit.sample.dailymart",
        capabilityId: "grocery.purchase_essentials",
        version: "1.0"
    ),
    receiptId: "rcpt-dailymart-0001",
    receiptStatus: "completed",
    receiptResult: [
        "status": "completed",
        "order_id": "order-2026-0824-0001",
        "total_krw": "100",
        "audit_id": "audit-0001"
    ],
    receiptNonce: "rcpt-nonce-dailymart-0001",
    receiptTimestamp: "2026-08-24T09:00:05Z",
    targetAppId: "app.dailymart"
)

let mintNotes = try makeCase(
    name: "mintnotes_append_note_unicode_escaping",
    requestId: "req-mintnotes-0002",
    payload: [
        "note_ref": "note/2026-08-24",
        "text": "장보기 예산 ₩100 & eggs=12개 (50%+) \"quoted\""
    ],
    nonce: "nonce-mintnotes-0002",
    timestamp: "2026-08-24T09:10:00Z",
    capability: MeshCapability(
        targetBundleId: "ai.meshkit.sample.mintnotes",
        capabilityId: "notes.append_note",
        version: "1.0"
    ),
    receiptId: "rcpt-mintnotes-0002",
    receiptStatus: "completed",
    receiptResult: [
        "status": "completed",
        "note_ref": "note/2026-08-24",
        "audit_id": "audit-0002"
    ],
    receiptNonce: "rcpt-nonce-mintnotes-0002",
    receiptTimestamp: "2026-08-24T09:10:02Z",
    targetAppId: "app.mint-notes"
)

let file = VectorFile(
    version: "wire-compat.v1",
    generator: "scripts/wire_vectors_gen",
    requestSignerSeedHex: hex(requestSeed),
    requestSignerPublicKeyBase64: requestKey.publicKey.rawRepresentation.base64EncodedString(),
    requestSignerKeyId: "hermes-request-ed25519",
    receiptSignerSeedHex: hex(receiptSeed),
    receiptSignerPublicKeyBase64: receiptKey.publicKey.rawRepresentation.base64EncodedString(),
    receiptSignerKeyId: "target-receipt-ed25519",
    cases: [dailyMart, mintNotes]
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
let outputData = try encoder.encode(file)

// Cross-verify mode: `wire-vectors-gen cross-verify <kotlin-signed.json>`
// proves the reverse direction — the Swift SDK verifies Kotlin-produced
// request and receipt signatures (e.g. iOS Hermes verifying an Android
// DailyMart receipt).
if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "cross-verify" {
    struct KotlinSignedCase: Codable {
        let name: String
        let requestEnvelopeBase64: String
        let receiptEnvelopeBase64: String
    }
    struct KotlinSignedFile: Codable {
        let cases: [KotlinSignedCase]
    }
    let inputURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let signed = try JSONDecoder().decode(KotlinSignedFile.self, from: Data(contentsOf: inputURL))
    for signedCase in signed.cases {
        let request = try MeshRequest.decodedFromURLScheme(signedCase.requestEnvelopeBase64)
        try MeshSignedRequestCrypto.verifySignature(
            for: request,
            trust: MeshSenderTrust(
                callerAppId: request.caller.appId,
                callerBundleId: request.caller.bundleId,
                teamId: "cross-verify",
                requestSigningAlgorithm: "Ed25519",
                requestSigningKeyId: request.signature.keyId,
                publicKey: requestKey.publicKey.rawRepresentation.base64EncodedString()
            )
        )
        let receipt = try MeshReceipt.decodedFromURLScheme(signedCase.receiptEnvelopeBase64)
        _ = try MeshReceiptVerifier.verify(
            receipt,
            trust: MeshReceiptTrust(
                targetAppId: receipt.targetAppId,
                targetBundleId: receipt.targetBundleId,
                receiptSigningAlgorithm: "Ed25519",
                receiptSigningKeyId: receipt.signature.keyId,
                publicKey: receiptKey.publicKey.rawRepresentation.base64EncodedString()
            ),
            maxAgeSeconds: 60 * 60 * 24 * 365 * 20
        )
        print("cross-verified \(signedCase.name)")
    }
    print("swift-verified \(signed.cases.count) externally-signed cases")
    exit(0)
}

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "meshkit-android/vectors/wire-compat.v1.json"
let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try outputData.write(to: outputURL)
print("wrote \(outputPath) (\(outputData.count) bytes)")
