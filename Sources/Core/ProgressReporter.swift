//
//  ProgressReporter.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import MCP

/// Sends MCP progress notifications during long-running tool operations.
/// The server sets the current progress token before each tool call and clears it after.
/// Build tools call `report(message:)` as xcodebuild phases change.
public actor ProgressReporter {
    public typealias Sender = @Sendable (ProgressToken, Double, Double?, String?) async -> Void

    private let sender: Sender
    private var currentToken: ProgressToken?
    private var stepCount: Double = 0

    public init(sender: @escaping Sender) {
        self.sender = sender
    }

    public func setToken(_ token: ProgressToken?) {
        currentToken = token
        stepCount = 0
    }

    public func report(message: String) async {
        guard let token = currentToken else { return }
        stepCount += 1
        await sender(token, stepCount, nil, message)
    }
}
