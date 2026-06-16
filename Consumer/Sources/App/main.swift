// The macro DECLARATION (in a real SDK this lives in a library's .swiftinterface). Its
// implementation is loaded from the DemoMacros artifact bundle — no macro source compiled here.
@freestanding(expression)
macro stringify<T>(_ value: T) -> (T, String) =
    #externalMacro(module: "DemoMacros", type: "StringifyMacro")

let (value, source) = #stringify(40 + 2)
print("value=\(value) source=\(source)")
