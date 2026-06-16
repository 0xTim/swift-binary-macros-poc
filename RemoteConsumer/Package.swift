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
            checksum: "0423f9e9998b980f57c5c1f631a79cf76996359558ce7e3e95e4495f6b629f8f"
        ),
        .executableTarget(name: "App", dependencies: ["DemoMacros"]),
    ]
)
