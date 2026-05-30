import Foundation

public struct MeshCapability: Codable, Equatable, Sendable {
    public let targetBundleId: String
    public let capabilityId: String
    public let version: String

    public init(targetBundleId: String, capabilityId: String, version: String) {
        self.targetBundleId = targetBundleId
        self.capabilityId = capabilityId
        self.version = version
    }
}
