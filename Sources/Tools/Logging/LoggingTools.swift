//
//  LoggingTools.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core

/// Registers all logging tools: start_log_capture, stop_log_capture.
func registerLoggingTools(
    with registry: ToolRegistry,
    session: SessionStore,
    logCapture: any LogCapturing,
    concurrency: ConcurrencyPolicy,
    validator: DefaultsValidator
) async {
    await registerStartLogCaptureTool(with: registry, session: session, logCapture: logCapture, concurrency: concurrency, validator: validator)
    await registerStopLogCaptureTool(with: registry, logCapture: logCapture)
}
