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

Macros are increasingly part of library and SDK public APIs. But a macro is two halves:

* The declaration - `macro foo(...) = #externalMacro(module: "FooMacros", ...)`; this is just the API and _can_ be distributed inside an XCFramework or any other `.swiftinterface`
* The implementation - `struct FooMacro: ...`; this is the executable run by the compiler at build time. Currently this can only be compiled from source

This creates two problems:

1. **Binary SDKs can't ship macros at all.** A vendor distributing precompiled XCFrameworks can
   put the macro *declaration* in the `.swiftinterface`, but has nowhere to
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

The change for this was actually pretty small and reuses a lot of existing infrastructure to make it work. The changes affect `swift build` and `swift-package-manager`:

* `swift-build` - [the PR](https://github.com/swiftlang/swift-build/pull/1460) for this is a one liner to add `SWIFT_LOAD_BINARY_MACROS` to `ProjectModel.BuildSettings.MultipleValueSetting`. This ensures the setting survives PIF encode and decode
* `swift-package-manager` - [the PR for this](https://github.com/swiftlang/swift-package-manager/pull/10210) is a bit more complex, but not overly so. Essentially it just hooks everything up so that the macro works in a binary artifact and the correct settings are passed to the compiler.

I've tested this on both **macOS (arm64)** and **Linux (aarch64)**, with **both** the native and
the default SwiftBuild build engines, including consumption from a real GitHub release. The PoC just vends
the macro declaration in a target, but I've tested this via an XCFramework as well on both platforms.

## How to try it

See the PoC repo's README. In short: clone the two forks, point SwiftPM at the local `swift-build`
fork (`swift package edit`), build `swift-run`, then `swift run --package-path RemoteConsumer App`
— which pulls a macro from a GitHub release via `url:checksum:` and expands it, printing
`value=42 source=40 + 2`, with no macro source compiled by the consumer.

## Alternatives considered

There are number of alternatives that could be done instead from the fragile (setting compiler flags)
to the very large (extending XCFrameworks) to brand new APIs. But this was a much easier, and stable
solution.

One interesting future direction could be the future improvements to prebuilts, but currently there
is no way to publish your own macro binaries and these changes will still be required.

## Future directions

Consuming these binary artifacts is pretty easy. Publishing them is a little more complicated and
involves building for each host target and combining them together. It would be nice to eventually
hook into the cross-compilation work and have it all done with one command, rather than hand-rolling
the artifact (see the script in the PoC). This would be similar to how XCFrameworks are created with
`xcodebuild`.

Additionally the published binary is tied to a Swift toolchain version. The PoC only uses the triple to
key variants, but something like the swift-syntax prebuilts manifest has better options to key on compiler
version as well to avoid compile time issues due to mismatched toolchains.
