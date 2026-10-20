// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Musepaper",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Musepaper", targets: ["Musepaper"])],
    targets: [
        .executableTarget(name: "Musepaper", path: "Sources", resources: [.process("Musepaper/Resources")]),
        .testTarget(name: "MusepaperTests", dependencies: ["Musepaper"])
    ]
)
