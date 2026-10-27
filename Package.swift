// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ToDoList", platforms: [.macOS(.v14)], targets: [
    .executableTarget(name: "ToDoList", path: "Sources/KleineListe")
])
