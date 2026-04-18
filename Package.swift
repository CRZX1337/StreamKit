// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "StreamKit",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "StreamKitCore",
            targets: ["StreamKitCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/HaishinKit/HaishinKit.swift.git", branch: "main")
    ],
    targets: [
        .target(
            name: "StreamKitCore",
            dependencies: [
                .product(name: "HaishinKit", package: "HaishinKit.swift"),
                .product(name: "RTMPHaishinKit", package: "HaishinKit.swift")
            ],
            path: "StreamKit"
        )
    ]
)
