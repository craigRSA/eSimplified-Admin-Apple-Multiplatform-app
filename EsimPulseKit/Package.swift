// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EsimPulseKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "EsimPulseKit", targets: ["EsimPulseKit"]),
    ],
    targets: [
        .target(name: "EsimPulseKit"),
        .testTarget(
            name: "EsimPulseKitTests",
            dependencies: ["EsimPulseKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
