// swift-tools-version: 5.10.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftSourceryTemplate",
    platforms: [
      .macOS(.v13)
    ],
    products: [
        .executable(name: "SwiftSourceryTemplate", targets: ["SwiftSourceryTemplate"])
    ],
    dependencies: [
        // Swift Package 中添加依赖（示例）
        .package(url: "https://github.com/krzysztofzablocki/Sourcery", from: "2.2.7"),
        .package(url: "https://github.com/art-divin/swift-package-manager", from: "1.0.8"),
    ],
    targets: [
        .target(name: "SwiftSourceryTemplate", dependencies: [
            .product(name: "SourceryRuntime", package: "Sourcery"),
            .product(name: "SourcerySwift", package: "Sourcery"),
            .product(name: "SourceryFramework", package: "Sourcery"),
//            .product(name: "sourcery", package: "Sourcery"),
            // SwiftPM
//            .product(name: "PackagePlugin", package: "swift-package-manager"),
        ], exclude: ["Generated", "SourcePackages"]),
    ]
)
