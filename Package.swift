// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "morphogen",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MorphogenCore", targets: ["MorphogenCore"]),
        .executable(name: "morphogen", targets: ["morphogen"])
    ],
    targets: [
        .target(name: "MorphogenCore", resources: [.copy("Shaders")]),
        .executableTarget(name: "morphogen", dependencies: ["MorphogenCore"]),
        .testTarget(name: "MorphogenCoreTests", dependencies: ["MorphogenCore"])
    ]
)
