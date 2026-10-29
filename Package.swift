// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PackageClaimKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "PackageClaimKit", targets: ["PackageClaimKit"]),
        .executable(name: "PackageClaimDemo", targets: ["PackageClaimDemo"])
    ],
    targets: [
        .target(name: "PackageClaimKit"),
        .executableTarget(
            name: "PackageClaimDemo",
            dependencies: ["PackageClaimKit"]
        ),
        .testTarget(
            name: "PackageClaimKitTests",
            dependencies: ["PackageClaimKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
