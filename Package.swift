// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SignalDesk",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SignalDesk", targets: ["SignalDesk"])
    ],
    targets: [
        .executableTarget(name: "SignalDesk"),
        .testTarget(name: "SignalDeskTests", dependencies: ["SignalDesk"])
    ],
    swiftLanguageModes: [.v5]
)
