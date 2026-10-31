import AppIntents
import Foundation

private enum ShortcutModelOptionsSupport {
    static func modelOptions(for providerID: String) async throws -> [String] {
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

    static func defaultProviderID() throws -> String {
        try AppServices.resolve().settingsRepository.load().apiProvider
    }
}

struct AskShortcutModelOptionsProvider: DynamicOptionsProvider {
    @IntentParameterDependency<RunYamabikoModelIntent>(\.$provider)
    private var intent

    func results() async throws -> [String] {
        try await ShortcutModelOptionsSupport.modelOptions(
            for: try intent?.provider.id ?? ShortcutModelOptionsSupport.defaultProviderID()
        )
    }

    func defaultResult() async -> String? {
        guard let provider = intent?.provider.id ?? (try? ShortcutModelOptionsSupport.defaultProviderID()) else {
            return nil
        }
        return try? await ShortcutModelOptionsSupport.modelOptions(for: provider).first
    }
}

struct SaveShortcutModelOptionsProvider: DynamicOptionsProvider {
    @IntentParameterDependency<RunAndSaveYamabikoModelIntent>(\.$provider)
    private var intent

    func results() async throws -> [String] {
        try await ShortcutModelOptionsSupport.modelOptions(
            for: try intent?.provider.id ?? ShortcutModelOptionsSupport.defaultProviderID()
        )
    }

    func defaultResult() async -> String? {
        guard let provider = intent?.provider.id ?? (try? ShortcutModelOptionsSupport.defaultProviderID()) else {
            return nil
        }
        return try? await ShortcutModelOptionsSupport.modelOptions(for: provider).first
    }
}

private enum ShortcutReasoningEffortOptionsSupport {
    /// Same per-model options as the chat effort picker; empty when the model has no selectable effort.
    static func options(provider: String, model: String) async throws -> [String] {
        let repository = try AppServices.resolve().chatRepository
        await repository.refreshReasoningEffortCatalog(for: provider)
        return repository.reasoningEffortConfiguration(
            settings: try repository.loadSettings(),
            provider: provider,
            model: model
        )?.options ?? []
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
