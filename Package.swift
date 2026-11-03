// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Transcripted",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Transcripted", targets: ["Transcripted"])],
    targets: [
        .executableTarget(name: "Transcripted", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "TranscriptedTests", dependencies: ["Transcripted"])
    ]
)
