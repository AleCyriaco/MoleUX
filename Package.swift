// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MoleGUI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MoleGUI", targets: ["MoleGUI"])
    ],
    targets: [
        .executableTarget(
            name: "MoleGUI",
            path: "Sources/MoleGUI",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
