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
        let metadata = [
            "provider": provider.id,
            "model": model,
            "reasoningEffort": reasoningEffort ?? "default",
            "allowedTools": allowedTools.map { $0.map(\.rawValue).sorted().joined(separator: ",") } ?? "default",
            "saveToNewConversation": String(saveToNewConversation)
        ]
        // A start entry without a matching result shows that the system ended the run
        // (for example on its execution time limit) before the intent could report.
        DiagnosticsLogger.log("Shortcut intent started", category: .chat, metadata: metadata)
        let startedAt = Date()

        do {
            let result = try await PiAgentRuntime.withListenerHeld {
                try await AppServices.resolve().chatRepository.runShortcut(
                    prompt: prompt,
                    provider: provider.id,
                    model: model,
                    systemPromptOverride: resolvedSystemPrompt,
                    reasoningEffort: reasoningEffort,
                    allowedTools: allowedTools,
                    saveToNewConversation: saveToNewConversation
                )
            }
            DiagnosticsLogger.log(
                "Shortcut intent completed",
                category: .chat,
                metadata: metadata.merging(["durationMs": elapsedMilliseconds(since: startedAt)]) { current, _ in current }
            )
            return .result(
                value: result.text,
                dialog: IntentDialog(stringLiteral: L10n.text("Shortcuts: 完了しました。"))
            )
        } catch {
            DiagnosticsLogger.log(
                saveToNewConversation ? "Shortcut save intent failed" : "Shortcut intent failed",
                category: .chat,
                metadata: metadata.merging(["durationMs": elapsedMilliseconds(since: startedAt)]) { current, _ in current },
                error: error
            )
            throw error
        }
    }

    private static func elapsedMilliseconds(since start: Date) -> String {
        String(Int(Date().timeIntervalSince(start) * 1_000))
    }

    /// Shortcuts resolves entities and option lists before `perform()`. Their failures reach the
    /// Shortcuts app directly, so each resolution stage records its own error.
    static func logged<T>(
        _ stage: String,
        metadata: [String: String] = [:],
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch {
            DiagnosticsLogger.log("Shortcut \(stage) failed", category: .chat, metadata: metadata, error: error)
            throw error
        }
    }
}
