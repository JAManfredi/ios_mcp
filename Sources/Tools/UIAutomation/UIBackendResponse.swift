// Created by Jared Manfredi

import Core

/// Preserve artifacts and error codes while making pre-action selection visible.
func uiBackendResponse(_ response: ToolResponse, reason: String) -> ToolResponse {
    let context = "UI backend: axe (\(reason))."
    switch response {
    case .success(let result):
        return .success(ToolResult(content: context + "\n" + result.content, artifacts: result.artifacts,
                                   nextSteps: result.nextSteps, inlineArtifacts: result.inlineArtifacts,
                                   unsafeCommandExecuted: result.unsafeCommandExecuted))
    case .error(let error):
        return .error(ToolError(code: error.code, message: context + "\n" + error.message, details: error.details))
    }
}
