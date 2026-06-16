# Pitch: Distributing Swift macros as prebuilt binaries

* Proof of concept: https://github.com/0xTim/swift-binary-macros-poc
* Implementation: [swift-package-manager fork](https://github.com/0xTim/swift-package-manager/tree/feature/binary-macro-artifact-targets) · [swift-build fork](https://github.com/0xTim/swift-build/tree/feature/binary-macro-artifact-targets)

## Introduction

Swift macros today can only be consumed as a `.macro` **target built from source**. There is no
supported way to ship a macro's *implementation* as a prebuilt binary. This pitch proposes a
small addition to the artifact-bundle format and SwiftPM so that a macro implementation can be
distributed as a prebuilt binary — consumed with the same `.binaryTarget(url:checksum:)`
mechanism already used for XCFrameworks — while the macro's declaration continues to ship in a
library's module interface.

## Motivation

Macros are increasingly part of library and SDK public API. But a macro is two halves:

| Half | What it is | How it ships today |
|---|---|---|
| **Declaration** (`macro foo(...) = #externalMacro(module: "FooMacros", ...)`) | Pure API surface | already distributable in a `.swiftinterface` (incl. inside an XCFramework) |
| **Implementation** (`struct FooMacro: ...`) | A **compiler-plugin executable** run by the compiler at build time | **only** as a `.macro` target compiled from source |

This creates two problems:

1. **Binary SDKs can't ship macros at all.** A vendor distributing precompiled frameworks
   (XCFrameworks) can put the macro *declaration* in the `.swiftinterface`, but has nowhere to
   put the *implementation*. In practice they must publish the macro **source** in a separate,
   consumer-facing package and have every consumer recompile it — duplicating and re-maintaining
   the macro in two places. This pitch comes directly out of a real SDK that ships as
   XCFrameworks and hit exactly this: the same macros maintained twice, in the SDK source repo
   and in the public consumer package.

2. **Every consumer recompiles the macro (and swift-syntax) from source.** Even for
   source-distributed packages this is a well-known build-time cost. The
   [swift-syntax prebuilts feature](https://forums.swift.org/t/preview-swift-syntax-prebuilts-for-macros/80202)
   removes the swift-syntax compile, but the *macro itself* is still compiled from source by
   every consumer, and that feature is toolchain-managed and hardcoded to swift-syntax — it does
   not let a third party ship their own macro as a binary.

### Why not "just put it in the XCFramework"?

A macro plugin is a **host tool**: it runs on the machine performing the compile, regardless of
what the build *targets*. An XCFramework is organised by **target** triple (the device the code
runs on) and its format has no slot for a host executable. Artifact bundles
([SE‑0305](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0305-swiftpm-binary-target-improvements.md))
*are* the host‑keyed, multi‑triple container for executables — so the macro implementation rides
**alongside** the library bundle, not inside the XCFramework.

## Proposed solution

Add a `macro` artifact type to the artifact-bundle `info.json`, with host-keyed variants — just
like the existing `executable` type:

```jsonc
{
  "schemaVersion": "1.0",
  "artifacts": {
    "FooMacros": {
      "type": "macro",
      "version": "1.0.0",
      "variants": [
        { "path": "arm64-apple-macosx/FooMacros",        "supportedTriples": ["arm64-apple-macosx"] },
        { "path": "aarch64-unknown-linux-gnu/FooMacros",  "supportedTriples": ["aarch64-unknown-linux-gnu"] }
      ]
    }
  }
}
```

A consumer references it with the **existing** binary-target API — no new manifest surface:

```swift
.binaryTarget(name: "FooMacros", url: "https://.../FooMacros.artifactbundle.zip", checksum: "…"),
.target(name: "App", dependencies: ["FooLibrary", "FooMacros"]),
```

SwiftPM selects the variant matching the **host**, and passes
`-load-plugin-executable <path>#FooMacros` to the compiler — exactly the mechanism it already
uses for a source-built `.macro` target. The macro **declaration** still comes from the library
(`#externalMacro(module: "FooMacros", …)` in its `.swiftinterface`). Nothing about authoring or
*using* a macro changes; only how the implementation is delivered.

## Detailed design

The change is intentionally small and reuses existing infrastructure (artifact-bundle host-triple
selection; the compiler's existing plugin-loading path).

**SwiftPM** ([fork](https://github.com/0xTim/swift-package-manager/tree/feature/binary-macro-artifact-targets)):
- `ArtifactsArchiveMetadata.ArtifactType.macro` — declarable in `info.json`.
- `BinaryModule.containsMacro` and `parseMacroArtifactArchives(for:)` — host-triple variant
  selection, mirroring the existing `executable` handling.
- **Native build engine**: a Swift target that depends on a macro binary target emits
  `-load-plugin-executable <hostVariant>#<module>` for it, identical to a source macro.
- **SwiftBuild engine**: sets the `SWIFT_LOAD_BINARY_MACROS` build setting on the consuming
  target (the engine already turns that into `-load-plugin-executable`).

**swift-build** ([fork](https://github.com/0xTim/swift-build/tree/feature/binary-macro-artifact-targets)):
- One line: register `SWIFT_LOAD_BINARY_MACROS` in `ProjectModel.BuildSettings.MultipleValueSetting`
  so the setting survives PIF encode/decode. (The engine already has the full loading machinery.)

Verified end-to-end on **macOS (arm64)** and **Linux (aarch64)**, with **both** the native and
the default SwiftBuild build engines, including consumption from a real GitHub release.

## How to try it

See the PoC repo's README. In short: clone the two forks, point SwiftPM at the local `swift-build`
fork (`swift package edit`), build `swift-run`, then `swift run --package-path RemoteConsumer App`
— which pulls a macro from a GitHub release via `url:checksum:` and expands it, printing
`value=42 source=40 + 2`, with no macro source compiled by the consumer.

## Alternatives considered

1. **`-load-plugin-executable` via `unsafeFlags` / `OTHER_SWIFT_FLAGS`** in each consumer. Works,
   but is per-consumer, fragile, requires hand-rolled host-variant selection, and `unsafeFlags`
   bars the package from being a versioned dependency. This is the status-quo workaround.
2. **Distribute the macro source** and let each consumer compile it (today's reality). Causes the
   duplication/maintenance problem above, recompiles per consumer, and is impossible for a
   purely-binary SDK.
3. **Extend the XCFramework format** to carry host tools. Larger, Apple-owned format change, and
   conceptually wrong: XCFrameworks are target-keyed, macro plugins are host-keyed. Artifact
   bundles already solve host-keyed executable distribution.
4. **A new manifest API / target kind** for binary macros (e.g. `.binaryMacroTarget`). More API
   surface; the self-describing-artifact approach needs none — a plain `.binaryTarget` suffices.
5. **Toolchain-managed prebuilts** (as swift-syntax does). That is shipped with the toolchain and
   specific to swift-syntax; it does not let arbitrary authors publish their own macro binaries.

## Downsides and open questions

1. **Compiler-version keying (the main open question).** A macro plugin communicates with the
   compiler over a version-specific protocol, so a published binary is tied to a Swift toolchain
   version. The PoC keys variants by *triple* only; a robust design should also key on **compiler
   version** — the swift-syntax prebuilts manifest already does this and is a good model. Without
   it, a mismatched toolchain fails at compile time (observed as "plugin produced malformed
   response").
2. **Two-repo coordination.** The change spans `swift-package-manager` and `swift-build`; the two
   PRs must land together (the SwiftPM side relies on the `swift-build` setting).
3. **SwiftBuild parser.** The PoC deliberately avoids registering the macro bundle as a build file
   so the engine's artifact parser never has to learn the new type. Teaching the parser the
   `macro` type directly is a cleaner alternative worth discussing.
4. **Trust.** Consuming a macro means running a downloaded binary in the compiler's plugin sandbox
   at build time. This is the same trust model as existing binary targets and build-tool plugins,
   but it is worth stating explicitly for macros.
5. **Naming expectations.** Users may expect "macros in XCFrameworks"; the implementation is a
   sibling artifact bundle, not literally inside the XCFramework, for the host-vs-target reason
   above.

## Acknowledgements / prior art

* [SE‑0305 — Package Manager Binary Target Improvements](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0305-swiftpm-binary-target-improvements.md) (artifact bundles)
* [SE‑0394 — Package Manager Support for Custom Macros](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0394-swiftpm-expression-macros.md)
* [Swift-Syntax Prebuilts for Macros](https://forums.swift.org/t/preview-swift-syntax-prebuilts-for-macros/80202)
