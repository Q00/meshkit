// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeshKit",
    platforms: [.iOS(.v15), .macOS(.v10_15)],
    products: [
        .library(name: "MeshKit", targets: ["MeshKit"]),
    ],
    targets: [
        .target(name: "MeshKit"),
        .testTarget(name: "MeshKitTests", dependencies: ["MeshKit"]),
    ]
)
