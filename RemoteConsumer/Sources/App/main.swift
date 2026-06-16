// Identical to Consumer, but the macro implementation is pulled from a REMOTE zipped artifact
// bundle (GitHub release) via `.binaryTarget(url:checksum:)` — the same distribution mechanism
// XCFrameworks use. No macro source, no path dependency.
@freestanding(expression)
macro stringify<T>(_ value: T) -> (T, String) =
    #externalMacro(module: "DemoMacros", type: "StringifyMacro")

let (value, source) = #stringify(40 + 2)
print("value=\(value) source=\(source)")
