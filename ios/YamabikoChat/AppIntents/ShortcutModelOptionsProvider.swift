import AppIntents
import Foundation

private enum ShortcutModelOptionsSupport {
    /// Models are offered only for the provider chosen in this action. The app's own selected
    /// provider is unrelated to the Shortcut, so it never supplies options or a default model.
    static func modelOptions(for providerID: String?) async throws -> [String] {
        guard let providerID else { return [] }
        return try await ShortcutIntentSupport.logged(
            "model options",
            metadata: ["provider": providerID]
        ) {
            let services = try AppServices.resolve()
            let settings = try services.settingsRepository.load()
            let openRouterModels = services.openRouterModelService.currentModels()
            let reference = ProviderReference(persistedID: providerID)
            if reference.isModelsDev {
                _ = await services.modelsDevCatalogRepository.load()
            }
            return ShortcutModelOptionsBuilder.modelOptions(
                provider: providerID,
                settings: settings,
                openRouterModels: openRouterModels,
                codexModels: services.codexAuthRepository.cachedModels(),
                catalogProvider: services.modelsDevCatalogRepository.provider(for: reference)
            )
        }
    }
}

struct AskShortcutModelOptionsProvider: DynamicOptionsProvider {
    @IntentParameterDependency<RunYamabikoModelIntent>(\.$provider)
    private var intent

    func results() async throws -> [String] {
        try await ShortcutModelOptionsSupport.modelOptions(for: intent?.provider.id)
    }

    func defaultResult() async -> String? {
        try? await ShortcutModelOptionsSupport.modelOptions(for: intent?.provider.id).first
    }
}

struct SaveShortcutModelOptionsProvider: DynamicOptionsProvider {
    @IntentParameterDependency<RunAndSaveYamabikoModelIntent>(\.$provider)
    private var intent

    func results() async throws -> [String] {
        try await ShortcutModelOptionsSupport.modelOptions(for: intent?.provider.id)
    }

    func defaultResult() async -> String? {
        try? await ShortcutModelOptionsSupport.modelOptions(for: intent?.provider.id).first
    }
}

private enum ShortcutReasoningEffortOptionsSupport {
    /// Same per-model options as the chat effort picker; empty when the model has no selectable effort.
    static func options(provider: String, model: String) async throws -> [String] {
        try await ShortcutIntentSupport.logged(
            "reasoning effort options",
            metadata: ["provider": provider, "model": model]
        ) {
            let repository = try AppServices.resolve().chatRepository
            await repository.refreshReasoningEffortCatalog(for: provider)
            return repository.reasoningEffortConfiguration(
                settings: try repository.loadSettings(),
                provider: provider,
                model: model
            )?.options ?? []
        }
    }
}

struct AskShortcutReasoningEffortOptionsProvider: DynamicOptionsProvider {
    @IntentParameterDependency<RunYamabikoModelIntent>(\.$provider, \.$model)
    private var intent

    func results() async throws -> [String] {
        guard let intent else { return [] }
        return try await ShortcutReasoningEffortOptionsSupport.options(provider: intent.provider.id, model: intent.model)
    }
}

struct SaveShortcutReasoningEffortOptionsProvider: DynamicOptionsProvider {
    @IntentParameterDependency<RunAndSaveYamabikoModelIntent>(\.$provider, \.$model)
    private var intent

    func results() async throws -> [String] {
        guard let intent else { return [] }
        return try await ShortcutReasoningEffortOptionsSupport.options(provider: intent.provider.id, model: intent.model)
    }
}
