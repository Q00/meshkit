import CryptoKit
import Foundation

public struct MeshSignature: Codable, Equatable, Sendable {
    public let algorithm: String
    public let keyId: String
    public let value: String

    public init(algorithm: String, keyId: String, value: String) {
        self.algorithm = algorithm
        self.keyId = keyId
        self.value = value
    }
}

public struct MeshPayloadHash: Codable, Equatable, Sendable {
    public let algorithm: String
    public let value: String

    public init(algorithm: String = "sha256", value: String) {
        self.algorithm = algorithm
        self.value = value
    }
}

public enum MeshRequestPayloadHasher {
    public static let algorithm = "sha256"
    public static let nonceBoundVersion = "meshkit-payload-hash/v1"

    public static func canonicalData(for payload: [String: String]) -> Data {
        let canonicalString = payload.keys.sorted().map { key in
            "\(escape(key))=\(escape(payload[key] ?? ""))"
        }.joined(separator: "&")
        return Data(canonicalString.utf8)
    }

    public static func canonicalData(for payload: [String: String], nonce: String) -> Data {
        let canonicalString = [
            nonceBoundVersion,
            "nonce=\(escape(nonce))",
            "payload=\(String(data: canonicalData(for: payload), encoding: .utf8) ?? "")"
        ].joined(separator: "\n")
        return Data(canonicalString.utf8)
    }

    public static func sha256Hex(for payload: [String: String]) -> String {
        let digest = SHA256.hash(data: canonicalData(for: payload))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(for payload: [String: String], nonce: String) -> String {
        let digest = SHA256.hash(data: canonicalData(for: payload, nonce: nonce))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func hash(for payload: [String: String]) -> MeshPayloadHash {
        MeshPayloadHash(algorithm: algorithm, value: sha256Hex(for: payload))
    }

    public static func hash(for payload: [String: String], nonce: String) -> MeshPayloadHash {
        MeshPayloadHash(algorithm: algorithm, value: sha256Hex(for: payload, nonce: nonce))
    }

    public static func hash(for request: MeshRequest) -> MeshPayloadHash {
        hash(for: request.payload, nonce: request.nonce)
    }

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }
}

public struct MeshRequest: Codable, Equatable, Sendable {
    public let requestId: String
    public let caller: MeshIdentity
    public let target: MeshCapability
    public let payload: [String: String]
    public let payloadHash: MeshPayloadHash
    public let nonce: String
    public let timestamp: String
    public let signature: MeshSignature

    public init(
        requestId: String,
        caller: MeshIdentity,
        target: MeshCapability,
        payload: [String: String],
        payloadHash: MeshPayloadHash? = nil,
        nonce: String,
        timestamp: String,
        signature: MeshSignature
    ) {
        self.requestId = requestId
        self.caller = caller
        self.target = target
        self.payload = payload
        self.nonce = nonce
        self.payloadHash = payloadHash ?? MeshRequestPayloadHasher.hash(for: payload, nonce: nonce)
        self.timestamp = timestamp
        self.signature = signature
    }

    public func encodedForURLScheme() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        return data.base64EncodedString()
    }

    public static func decodedFromURLScheme(_ encoded: String) throws -> MeshRequest {
        guard let data = Data(base64Encoded: encoded) else { throw MeshKitValidationError.invalidEncoding("mesh_request is not valid base64") }
        return try JSONDecoder().decode(MeshRequest.self, from: data)
    }

    public func signingInputData() -> Data {
        let components = [
            "meshkit-request-signing/v1",
            requestId,
            caller.appId,
            caller.bundleId,
            caller.publicKeyId,
            target.targetBundleId,
            target.capabilityId,
            target.version,
            payloadHash.algorithm.lowercased(),
            payloadHash.value.lowercased(),
            timestamp,
            nonce
        ]
        return Data(components.joined(separator: "\n").utf8)
    }

    public static func canonicalPayloadData(_ payload: [String: String]) -> Data {
        MeshRequestPayloadHasher.canonicalData(for: payload)
    }

    public static func sha256HexForPayload(_ payload: [String: String]) -> String {
        MeshRequestPayloadHasher.sha256Hex(for: payload)
    }

    public static func sha256HexForPayload(_ payload: [String: String], nonce: String) -> String {
        MeshRequestPayloadHasher.sha256Hex(for: payload, nonce: nonce)
    }
}
