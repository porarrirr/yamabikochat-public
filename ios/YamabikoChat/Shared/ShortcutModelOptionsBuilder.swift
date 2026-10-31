import Foundation

enum ShortcutModelOptionsBuilder {
    /// Mirrors the app's provider picker: built-ins followed by selectable models.dev providers.
    static func providerOptions(catalogProviders: [CatalogProvider]) -> [ProviderDisplay] {
        ProviderCatalog.options + catalogProviders
            .filter { ModelsDevMergedProvider.isSelectableCatalogProvider($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { ProviderDisplay(key: $0.reference.persistedID, title: $0.name) }
    }

    static func modelOptions(
        provider: String,
        settings: AppSettings,
        openRouterModels: [SimpleModel],
        codexModels: [PiCodexModel] = [],
        catalogProvider: CatalogProvider? = nil
    ) -> [String] {
        let normalizedProvider = provider.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var options: [String] = []

        func appendUnique(_ value: String?) {
            guard let value else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !options.contains(trimmed) else { return }
            options.append(trimmed)
        }

        if settings.apiProvider.uppercased() == normalizedProvider {
            appendUnique(settings.defaultModel)
        }

        if let data = settings.providerDefaultModelsJSON.data(using: .utf8),
           let rawMap = try? JSONDecoder().decode([String: String].self, from: data) {
            appendUnique(rawMap[normalizedProvider])
        }

        appendUnique(settings.providerModelMap()[normalizedProvider])

        catalogProvider?.models.map(\.id).forEach { appendUnique($0) }

        switch normalizedProvider {
        case "GEMINI":
            GeminiModelCatalog.suggestedModels.forEach { appendUnique($0) }
        case "SUPERGROK":
            SuperGrokModelCatalog.supportedModels.map(\.id).forEach { appendUnique($0) }
        case "CODEX_AUTH":
            codexModels.filter { $0.supported == true }.map(\.id).forEach { appendUnique($0) }
        case "APPLE_INTELLIGENCE":
            AppleIntelligenceModelCatalog.supportedModels.forEach { appendUnique($0) }
        case "OPENROUTER":
            if openRouterModels.isEmpty {
                openRouterFallbackModelIDs.forEach { appendUnique($0) }
            } else {
                openRouterModels.map(\.id).forEach { appendUnique($0) }
            }
        default:
            break
        }

        return options
    }

    private static let openRouterFallbackModelIDs: [String] = [
        "openai/gpt-4o",
        "anthropic/claude-3.5-sonnet",
        "meta-llama/llama-3.1-8b-instruct:free"
    ]
}
