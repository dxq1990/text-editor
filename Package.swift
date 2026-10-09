// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TextEditor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TextEditor", targets: ["TextEditor"])
    ],
    targets: [
        .target(name: "EditorCore"),
        .executableTarget(
            name: "TextEditor",
            dependencies: ["EditorCore"]
        ),
        .testTarget(
            name: "EditorCoreTests",
            dependencies: ["EditorCore"]
        )
    ]
)
