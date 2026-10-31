import Foundation

/// App-executed function tools a Shortcut run can allow. Provider-native tools
/// (Gemini / OpenRouter search, code execution, MCP) keep following the provider settings.
enum ShortcutTool: String, CaseIterable, Sendable {
    case webSearch
    case python
    case editor
    case genUI

    var functionNames: Set<String> {
        switch self {
        case .webSearch:
            return [WebSearchTool.name, FetchUrlTool.name]
        case .python:
            return [PythonExecuteTool.name]
        case .editor:
            return [StrReplaceEditorTool.name]
        case .genUI:
            return [GenUITool.name, GenUIReferenceTool.name]
        }
    }

    static func functionNames(allowing tools: Set<ShortcutTool>) -> Set<String> {
        tools.reduce(into: []) { $0.formUnion($1.functionNames) }
    }

    /// The selection decides which app tools are enabled for this run, independent of the
    /// in-app toggles, so a Shortcut can turn on a tool that chat currently has off.
    static func settings(_ settings: AppSettings, allowing tools: Set<ShortcutTool>) -> AppSettings {
        var updated = settings
        updated.clientWebSearchToolEnabled = tools.contains(.webSearch)
        updated.pythonToolEnabled = tools.contains(.python)
        updated.genUIToolEnabled = tools.contains(.genUI)
        return updated
    }
}
