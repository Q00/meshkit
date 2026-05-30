import CryptoKit
import Foundation

public struct MeshReceiptTrust: Codable, Equatable, Sendable {
    public let targetAppId: String
    public let targetBundleId: String
    public let receiptSigningAlgorithm: String
    public let receiptSigningKeyId: String
    public let publicKey: String

    public init(
        targetAppId: String,
        targetBundleId: String,
        receiptSigningAlgorithm: String,
        receiptSigningKeyId: String,
        publicKey: String
    ) {
        self.targetAppId = targetAppId
        self.targetBundleId = targetBundleId
        self.receiptSigningAlgorithm = receiptSigningAlgorithm
        self.receiptSigningKeyId = receiptSigningKeyId
        self.publicKey = publicKey
    }
}

public struct MeshReceipt: Codable, Equatable, Sendable {
    public let receiptId: String
    public let requestId: String
    public let capabilityId: String
    public let targetAppId: String
    public let targetBundleId: String
    public let requestPayloadHash: MeshPayloadHash
    public let status: String
    public let result: [String: String]
    public let nonce: String
    public let timestamp: String
    public let signature: MeshSignature

    public init(
        receiptId: String,
        requestId: String,
        capabilityId: String,
        targetAppId: String,
        targetBundleId: String,
        requestPayloadHash: MeshPayloadHash,
        status: String,
        result: [String: String],
        nonce: String,
        timestamp: String,
        signature: MeshSignature
    ) {
        self.receiptId = receiptId
        self.requestId = requestId
        self.capabilityId = capabilityId
        self.targetAppId = targetAppId
        self.targetBundleId = targetBundleId
        self.requestPayloadHash = requestPayloadHash
        self.status = status
        self.result = result
        self.nonce = nonce
        self.timestamp = timestamp
        self.signature = signature
    }

    public func signingInputData() -> Data {
        let components = [
            "meshkit-target-receipt-signing/v1",
            receiptId,
            requestId,
            capabilityId,
            targetAppId,
            targetBundleId,
            requestPayloadHash.algorithm.lowercased(),
            requestPayloadHash.value.lowercased(),
            status,
            MeshReceipt.canonicalResultString(result),
            timestamp,
            nonce
        ]
        return Data(components.joined(separator: "\n").utf8)
    }

    public func encodedForURLScheme() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        return data.base64EncodedString()
    }

    public static func decodedFromURLScheme(_ encoded: String) throws -> MeshReceipt {
        guard let data = Data(base64Encoded: encoded) else {
            throw MeshKitValidationError.invalidEncoding("mesh_receipt is not valid base64")
        }
        return try JSONDecoder().decode(MeshReceipt.self, from: data)
    }

    public static func canonicalResultString(_ result: [String: String]) -> String {
        result.keys.sorted().map { key in
            "\(escape(key))=\(escape(result[key] ?? ""))"
        }.joined(separator: "&")
    }

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }
}

public struct MeshReceiptSigner: Sendable {
    public let algorithm: String
    public let keyId: String
    private let signData: @Sendable (Data) throws -> Data

    public init(algorithm: String, keyId: String, signData: @escaping @Sendable (Data) throws -> Data) {
        self.algorithm = algorithm
        self.keyId = keyId
        self.signData = signData
    }

    public static func ed25519(keyId: String, privateKey: Curve25519.Signing.PrivateKey) -> MeshReceiptSigner {
        MeshReceiptSigner(algorithm: "Ed25519", keyId: keyId) { data in
            try privateKey.signature(for: data)
        }
    }

    public func makeReceipt(
        receiptId: String,
        request: MeshRequest,
        targetAppId: String,
        targetBundleId: String,
        status: String,
        result: [String: String],
        nonce: String = UUID().uuidString,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) throws -> MeshReceipt {
        let unsigned = MeshReceipt(
            receiptId: receiptId,
            requestId: request.requestId,
            capabilityId: request.target.capabilityId,
            targetAppId: targetAppId,
            targetBundleId: targetBundleId,
            requestPayloadHash: request.payloadHash,
            status: status,
            result: result,
            nonce: nonce,
            timestamp: timestamp,
            signature: MeshSignature(algorithm: algorithm, keyId: keyId, value: "")
        )
        let signature = try signData(unsigned.signingInputData()).base64EncodedString()
        return MeshReceipt(
            receiptId: unsigned.receiptId,
            requestId: unsigned.requestId,
            capabilityId: unsigned.capabilityId,
            targetAppId: unsigned.targetAppId,
            targetBundleId: unsigned.targetBundleId,
            requestPayloadHash: unsigned.requestPayloadHash,
            status: unsigned.status,
            result: unsigned.result,
            nonce: unsigned.nonce,
            timestamp: unsigned.timestamp,
            signature: MeshSignature(algorithm: algorithm, keyId: keyId, value: signature)
        )
    }
}

public enum MeshReceiptVerifier {
    public static func verify(_ receipt: MeshReceipt, trust: MeshReceiptTrust, maxAgeSeconds: TimeInterval = 300) throws -> MeshReceipt {
        try validateEnvelope(receipt)
        guard receipt.targetAppId == trust.targetAppId else { throw MeshKitValidationError.targetIdentityMismatch }
        guard receipt.targetBundleId == trust.targetBundleId else { throw MeshKitValidationError.targetIdentityMismatch }
        guard receipt.signature.algorithm == trust.receiptSigningAlgorithm else {
            throw MeshKitValidationError.signatureMismatch("receipt signing algorithm mismatch")
        }
        guard receipt.signature.keyId == trust.receiptSigningKeyId else {
            throw MeshKitValidationError.signatureMismatch("receipt signing key id mismatch")
        }
        guard trust.receiptSigningAlgorithm == "Ed25519" else {
            throw MeshKitValidationError.signatureMismatch("unsupported receipt signing algorithm: \(trust.receiptSigningAlgorithm)")
        }
        guard let timestamp = ISO8601DateFormatter().date(from: receipt.timestamp), abs(timestamp.timeIntervalSinceNow) <= maxAgeSeconds else {
            throw MeshKitValidationError.staleTimestamp
        }
        guard let publicKeyData = Data(base64Encoded: trust.publicKey), !publicKeyData.isEmpty else { throw MeshKitValidationError.signatureRequired }
        guard let signatureData = Data(base64Encoded: receipt.signature.value), !signatureData.isEmpty else {
            throw MeshKitValidationError.signatureMismatch("receipt signature is not valid base64")
        }
        do {
            let verifier = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
            guard verifier.isValidSignature(signatureData, for: receipt.signingInputData()) else {
                throw MeshKitValidationError.signatureMismatch("invalid receipt signature")
            }
        } catch let error as MeshKitValidationError {
            throw error
        } catch {
            throw MeshKitValidationError.signatureMismatch("invalid receipt signing public key")
        }
        return receipt
    }

    private static func validateEnvelope(_ receipt: MeshReceipt) throws {
        try requireSecurityField("receiptId", receipt.receiptId)
        try requireSecurityField("requestId", receipt.requestId)
        try requireSecurityField("capabilityId", receipt.capabilityId)
        try requireSecurityField("targetAppId", receipt.targetAppId)
        try requireSecurityField("targetBundleId", receipt.targetBundleId)
        try requireSecurityField("status", receipt.status)
        try requireSecurityField("nonce", receipt.nonce)
        try requireSecurityField("timestamp", receipt.timestamp)
        try requireSecurityField("signature.algorithm", receipt.signature.algorithm)
        try requireSecurityField("signature.keyId", receipt.signature.keyId)
        if receipt.signature.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MeshKitValidationError.signatureRequired }
        guard receipt.requestPayloadHash.algorithm.lowercased() == "sha256" else { throw MeshKitValidationError.unsupportedPayloadHashAlgorithm }
        guard receipt.requestPayloadHash.value.count == 64,
              receipt.requestPayloadHash.value.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdefABCDEF").inverted) == nil else {
            throw MeshKitValidationError.invalidSecurityField("requestPayloadHash.value")
        }
        for (key, value) in receipt.result {
            try requireSecurityField("result.key", key)
            try requireSecurityField("result[\(key)]", value)
        }
    }

    private static func requireSecurityField(_ field: String, _ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == value else { throw MeshKitValidationError.invalidSecurityField(field) }
        guard value.rangeOfCharacter(from: CharacterSet.newlines.union(.controlCharacters)) == nil else {
            throw MeshKitValidationError.invalidSecurityField(field)
        }
    }
}

public final class MeshPendingReceiptStore: @unchecked Sendable {
    private struct Pending: Sendable {
        let requestId: String
        let capabilityId: String
        let requestPayloadHash: MeshPayloadHash
    }

    private var pending: [String: Pending] = [:]
    private var consumed = Set<String>()
    private let lock = NSLock()

    public init() {}

    @discardableResult
    public func register(request: MeshRequest, capabilityId: String? = nil) -> String {
        let token = request.requestId
        lock.lock()
        defer { lock.unlock() }
        pending[token] = Pending(
            requestId: request.requestId,
            capabilityId: capabilityId ?? request.target.capabilityId,
            requestPayloadHash: request.payloadHash
        )
        return token
    }

    public func consumeVerified(
        _ receipt: MeshReceipt,
        expectedToken: String,
        trust: MeshReceiptTrust,
        maxAgeSeconds: TimeInterval = 300
    ) throws -> MeshReceipt {
        let pendingRecord: Pending
        lock.lock()
        if consumed.contains(expectedToken) {
            lock.unlock()
            throw MeshKitValidationError.replayDetected(expectedToken)
        }
        guard let stored = pending[expectedToken] else {
            lock.unlock()
            throw MeshKitValidationError.receiptCorrelationMismatch
        }
        pendingRecord = stored
        lock.unlock()

        guard receipt.requestId == expectedToken,
              receipt.requestId == pendingRecord.requestId,
              receipt.capabilityId == pendingRecord.capabilityId,
              receipt.requestPayloadHash == pendingRecord.requestPayloadHash else {
            throw MeshKitValidationError.receiptCorrelationMismatch
        }

        let verified = try MeshReceiptVerifier.verify(receipt, trust: trust, maxAgeSeconds: maxAgeSeconds)

        lock.lock()
        pending.removeValue(forKey: expectedToken)
        consumed.insert(expectedToken)
        lock.unlock()
        return verified
    }
}
