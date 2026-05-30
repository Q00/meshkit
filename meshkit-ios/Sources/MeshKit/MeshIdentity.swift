import Foundation

public struct MeshIdentity: Codable, Equatable, Sendable {
    public let appId: String
    public let installId: String
    public let bundleId: String
    public let publicKeyId: String

    public init(appId: String, installId: String, bundleId: String, publicKeyId: String) {
        self.appId = appId
        self.installId = installId
        self.bundleId = bundleId
        self.publicKeyId = publicKeyId
    }
}
