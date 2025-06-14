// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CloudFramework",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "CloudFramework",
            targets: ["CloudFramework"])
    ],
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "CloudFramework",
            path: "CloudFramework.xcframework"
        )
    ],
    swiftLanguageVersions: [.v5]
)
