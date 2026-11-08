// swift-tools-version:5.9
// Builds and tests the platform-independent core of the Woop app (WHOOP protocol decoding and
// on-device analytics) with `swift test`, on macOS or Linux. The iOS app itself is built from
// project.yml with XcodeGen + Xcode; it compiles these same sources directly.
import PackageDescription

let package = Package(
    name: "WoopCore",
    products: [.library(name: "WoopCore", targets: ["WoopCore"])],
    targets: [
        .target(name: "WoopCore", path: "Woop/Core"),
        .testTarget(name: "WoopCoreTests", dependencies: ["WoopCore"], path: "Tests/WoopCoreTests"),
    ]
)
