// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RedshiftMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "RedshiftMenuBar",
            targets: ["RedshiftMenuBar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "RedshiftMenuBar",
            path: "Sources/RedshiftMenuBar"
        )
    ]
)
