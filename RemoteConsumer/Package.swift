// swift-tools-version: 6.0
import PackageDescription

// Consumes the macro from a REMOTE zipped artifact bundle published as a GitHub release —
// the same `url` + `checksum` mechanism used for binary XCFrameworks. Build with the patched
// toolchain (see README). No macro source and no local path: distribution only.
let package = Package(
    name: "RemoteConsumer",
    platforms: [.macOS(.v13)],
    targets: [
        .binaryTarget(
            name: "DemoMacros",
            url: "https://github.com/0xTim/swift-binary-macros-poc/releases/download/v1.0.0/DemoMacros.artifactbundle.zip",
            checksum: "263d88b986a14c5ac3c43abf060da412abddbe6dca6cb4210bd4254fc6a4efbb"
        ),
        .executableTarget(name: "App", dependencies: ["DemoMacros"]),
    ]
)
