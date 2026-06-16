# Distributing Swift macros as prebuilt binaries (artifact bundles)

A proof-of-concept showing that a Swift **macro implementation** can be shipped as a
**prebuilt binary** inside an artifact bundle — distributed via a GitHub release and consumed
with a plain `.binaryTarget(url:checksum:)`, exactly like a binary XCFramework — instead of
recompiling the macro (and `swift-syntax`) from source in every consumer.

This requires small additions to **SwiftPM** and the **swift-build** engine (patches included);
it is the basis for an upstream proposal.

## Why a separate artifact (and not "inside the XCFramework")?

A macro has two halves:

| Half | What it is | Where it ships |
|---|---|---|
| **Declaration** (`macro stringify(...) = #externalMacro(module: "DemoMacros", ...)`) | Pure API surface (Swift) | a library's `.swiftinterface` (e.g. inside an XCFramework) |
| **Implementation** (`StringifyMacro`) | A **compiler-plugin executable** the compiler runs at build time | a **host-keyed** artifact bundle |

They're keyed on different axes: an XCFramework is organized by **target** triple (what the app
runs on); a macro plugin is a **host** tool (it runs on the machine doing the compile, whatever
the target). The XCFramework format has no slot for a host tool — so the implementation rides
**alongside** the library in an artifact bundle, not inside the XCFramework.

## The artifact bundle

`Scripts/build-bundle.sh` builds the plugin for the current host and assembles a bundle whose
`info.json` declares a **new `macro` artifact type**, with one host-keyed variant per triple:

```jsonc
{
  "schemaVersion": "1.0",
  "artifacts": {
    "DemoMacros": {
      "type": "macro",
      "version": "1.0.0",
      "variants": [
        { "path": "arm64-apple-macosx/DemoMacros",        "supportedTriples": ["arm64-apple-macosx"] },
        { "path": "aarch64-unknown-linux-gnu/DemoMacros", "supportedTriples": ["aarch64-unknown-linux-gnu"] }
      ]
    }
  }
}
```

SwiftPM selects the variant matching the **host** performing the build and passes it to the
compiler with `-load-plugin-executable <path>#DemoMacros`.

## The toolchain changes

Two small changes, available as branches on these forks (and as patches in `patches/`):

- **[0xTim/swift-package-manager `feature/binary-macro-artifact-targets`](https://github.com/0xTim/swift-package-manager/tree/feature/binary-macro-artifact-targets)**
  — adds the `macro` artifact type, selects the host variant, and emits
  `-load-plugin-executable` for both the native build engine and the SwiftBuild PIF bridge
  (`SWIFT_LOAD_BINARY_MACROS`).
- **[0xTim/swift-build `feature/binary-macro-artifact-targets`](https://github.com/0xTim/swift-build/tree/feature/binary-macro-artifact-targets)**
  — one line: registers `SWIFT_LOAD_BINARY_MACROS` as a known PIF build setting so it survives
  PIF encode/decode.

## Trying it out

### 1. Build the patched SwiftPM CLI

Clone the two forks side by side and point SwiftPM at the local `swift-build` fork (the engine
change lives there), then build just the `swift-run` product (tested with a Swift 6.4 toolchain):

```bash
git clone -b feature/binary-macro-artifact-targets https://github.com/0xTim/swift-package-manager.git
git clone -b feature/binary-macro-artifact-targets https://github.com/0xTim/swift-build.git

cd swift-package-manager
swift package edit swift-build --path ../swift-build   # use the patched engine
swift build --product swift-run
export SR="$(swift build --product swift-run --show-bin-path)/swift-run"
cd ..
```

### 2. Consume the macro

```bash
cd swift-binary-macros-poc

# (a) Local flow — build the bundle with YOUR toolchain, then consume it by path:
Scripts/build-bundle.sh                      # builds dist/DemoMacros.artifactbundle (+ prints checksum)
"$SR" --package-path Consumer App            # -> value=42 source=40 + 2

# (b) Remote flow — pull the published GitHub release by url + checksum (no local artifact):
"$SR" --package-path RemoteConsumer App      # -> value=42 source=40 + 2
```

Both consumers only **declare** `#stringify` and use it; the implementation is loaded from the
binary bundle via `-load-plugin-executable`. The local flow (a) is the most robust because the
plugin is built with your own toolchain; the remote flow (b) demonstrates distribution but
expects a toolchain compatible with the one that built the released binary (see compiler-version
keying below).

## Status / open questions

- Verified end-to-end on macOS (arm64) and Linux (aarch64), with both the native and the
  default SwiftBuild build engines.
- **Compiler-version keying:** macro plugins talk to the compiler over a version-specific
  protocol, so a published bundle is toolchain-specific. Variants are keyed by triple only; a
  robust solution should also key on compiler version (cf. swift-syntax prebuilts).
- The SwiftBuild side currently avoids registering the macro bundle as a build file (so the
  engine's artifact parser never sees the new type); teaching the parser directly is an
  alternative worth discussing.
- Upstreaming is two coordinated PRs (swift-package-manager + swift-build) plus tests.
