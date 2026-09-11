// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "wire-vectors-gen",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../../meshkit-ios")
    ],
    targets: [
        .executableTarget(
            name: "wire-vectors-gen",
            dependencies: [.product(name: "MeshKit", package: "meshkit-ios")],
            path: "Sources"
        )
    ]
)
