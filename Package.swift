// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Stanza",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Stanza", targets: ["Stanza"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Stanza",
            dependencies: [],
            path: "Sources/Stanza",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "StanzaTests",
            dependencies: ["Stanza"],
            path: "Tests/StanzaTests"
        )
    ]
)
