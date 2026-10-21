//
//  IntegerArgument.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import MCP

/// JSON numbers may decode as Double even for integer parameters. Validate
/// before conversion so fractions, non-finite values and overflow cannot trap.
func integerArgument(_ value: Value, named name: String) -> Result<Int, ToolError> {
    let integer: Int?
    switch value {
    case .int(let number): integer = number
    case .double(let number): integer = Int(exactly: number)
    default: integer = nil
    }
    guard let integer else {
        return .failure(ToolError(code: .invalidInput, message: "\(name) must be a representable whole number."))
    }
    return .success(integer)
}
