// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BandCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "BandCore", targets: ["BandCore"])],
    targets: [
        .target(name: "BandCore"),
        .testTarget(name: "BandCoreTests", dependencies: ["BandCore"])
    ]
)
