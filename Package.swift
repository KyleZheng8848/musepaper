// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Musepaper",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Musepaper", targets: ["Musepaper"])],
    targets: [
        .executableTarget(name: "Musepaper", path: "Sources", sources: ["Musepaper", "Shared"]),
        .testTarget(name: "MusepaperTests", dependencies: ["Musepaper"])
    ]
)
