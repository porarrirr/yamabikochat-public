import AppIntents
import Foundation

/// Shortcut provider choices are derived from the same catalog the app's provider picker uses,
/// so every selectable value is a provider ID that `ChatRepository.runShortcut` accepts.
struct ShortcutProviderEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Shortcuts: プロバイダ"))
    static var defaultQuery = ShortcutProviderEntityQuery()

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    init(_ provider: ProviderDisplay) {
        id = provider.key
        title = provider.title
    }
}

struct ShortcutProviderEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ShortcutProviderEntity] {
        let options = try await providerOptions()
        return identifiers.compactMap { identifier in
            options.first { $0.key.caseInsensitiveCompare(identifier) == .orderedSame }
                .map(ShortcutProviderEntity.init)
        }
    }

    func entities(matching string: String) async throws -> [ShortcutProviderEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await providerOptions()
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.key.localizedCaseInsensitiveContains(query) }
            .map(ShortcutProviderEntity.init)
    }

    func suggestedEntities() async throws -> [ShortcutProviderEntity] {
        try await providerOptions().map(ShortcutProviderEntity.init)
    }

    private func providerOptions() async throws -> [ProviderDisplay] {
        let catalog = try await AppServices.resolve().modelsDevCatalogRepository.load()
        return ShortcutModelOptionsBuilder.providerOptions(catalogProviders: catalog.providers)
    }
}
