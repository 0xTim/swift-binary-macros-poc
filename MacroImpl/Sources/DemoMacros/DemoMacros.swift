import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

enum DemoMacroError: Error, CustomStringConvertible {
    case missingArgument
    var description: String { "#stringify requires a single expression argument." }
}

/// Expands `#stringify(x + y)` into `(x + y, "x + y")`.
public struct StringifyMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in _: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let argument = node.arguments.first?.expression else {
            throw DemoMacroError.missingArgument
        }
        return "(\(argument), \(literal: argument.description))"
    }
}

@main
struct DemoMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [StringifyMacro.self]
}
