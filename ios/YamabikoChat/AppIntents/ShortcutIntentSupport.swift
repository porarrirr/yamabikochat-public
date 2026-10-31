import AppIntents
import Foundation

enum ShortcutIntentSupport {
    static func perform(
        prompt: String,
        provider: ShortcutProviderEntity,
        model: String,
        systemPrompt: String?,
        reasoningEffort: String?,
        allowedTools: Set<ShortcutTool>?,
        saveToNewConversation: Bool
    ) async throws -> some IntentResult & ReturnsValue<String> {
        let trimmedSystemPrompt = systemPrompt?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSystemPrompt = trimmedSystemPrompt?.isEmpty == false ? trimmedSystemPrompt : nil

        do {
            let result = try await AppServices.resolve().chatRepository.runShortcut(
                prompt: prompt,
                provider: provider.id,
                model: model,
                systemPromptOverride: resolvedSystemPrompt,
                reasoningEffort: reasoningEffort,
                allowedTools: allowedTools,
                saveToNewConversation: saveToNewConversation
            )
            return .result(
                value: result.text,
                dialog: IntentDialog(stringLiteral: L10n.text("Shortcuts: 完了しました。"))
            )
        } catch {
            DiagnosticsLogger.log(
                saveToNewConversation ? "Shortcut save intent failed" : "Shortcut intent failed",
                category: .chat,
                metadata: [
                    "provider": provider.id,
                    "model": model,
                    "reasoningEffort": reasoningEffort ?? "default",
                    "allowedTools": allowedTools.map { $0.map(\.rawValue).sorted().joined(separator: ",") } ?? "default"
                ],
                error: error
            )
            throw error
        }
    }
}
