// swift-tools-version: 6.0
import PackageDescription

// Consumes the macro from a LOCAL artifact bundle. Run `Scripts/build-bundle.sh` first to
// produce ../dist/DemoMacros.artifactbundle, then build with the patched toolchain (see README).
let package = Package(
    name: "Consumer",
    platforms: [.macOS(.v13)],
    targets: [
        .binaryTarget(name: "DemoMacros", path: "../dist/DemoMacros.artifactbundle"),
        .executableTarget(name: "App", dependencies: ["DemoMacros"]),
    ]
)
