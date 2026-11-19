// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "morphogen",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MorphogenCore", targets: ["MorphogenCore"]),
    ],
    targets: [
        .target(
            name: "MorphogenCore",
            resources: [.copy("Shaders")]
        ),
        .testTarget(
            name: "MorphogenCoreTests",
            dependencies: ["MorphogenCore"]
        ),
    ]
)
