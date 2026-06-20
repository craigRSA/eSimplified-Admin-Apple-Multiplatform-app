// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EsimplifiedKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "EsimplifiedKit", targets: ["EsimplifiedKit"]),
    ],
    targets: [
        .target(name: "EsimplifiedKit"),
        .testTarget(
            name: "EsimplifiedKitTests",
            dependencies: ["EsimplifiedKit"]
        ),
    ]
)
