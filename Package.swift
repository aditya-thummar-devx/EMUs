// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EMUs",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "EMUs",
            targets: ["EMUs"]
        )
    ],
    targets: [
        .executableTarget(
            name: "EMUs",
            path: "Sources/EMUs"
        )
    ]
)
