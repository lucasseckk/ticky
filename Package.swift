// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Ticky", platforms: [.macOS(.v14)], targets: [
    .executableTarget(name: "Ticky", path: "Sources/Ticky")
])
