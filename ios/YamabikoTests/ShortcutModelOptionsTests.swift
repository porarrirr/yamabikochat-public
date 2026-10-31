import XCTest
@testable import YamabikoChat

final class ShortcutModelOptionsTests: XCTestCase {
    func testGeminiOptionsIncludeCurrentSettingsSavedModelAndCatalog() {
        var settings = AppSettings()
        settings.apiProvider = "GEMINI"
        settings.defaultModel = "custom-gemini-model"
        settings.providerDefaultModelsJSON = #"{"GEMINI":"saved-gemini-model"}"#

        let options = ShortcutModelOptionsBuilder.modelOptions(
            provider: "GEMINI",
            settings: settings,
            openRouterModels: []
        )

        XCTAssertTrue(options.contains("custom-gemini-model"))
        XCTAssertTrue(options.contains("saved-gemini-model"))
        XCTAssertTrue(options.contains("gemini-2.5-flash"))
        XCTAssertEqual(options.first, "custom-gemini-model")
    }

    func testOpenRouterOptionsPreferCachedModelsOverFallback() {
        var settings = AppSettings()
        settings.apiProvider = "OPENROUTER"
        settings.defaultModel = "openai/gpt-4o-mini"
        let cached = [
            SimpleModel(
                id: "cached/model-a",
                name: "Cached A",
                provider: "cached",
                topProvider: nil,
                contextLength: 1,
                promptPricePerMillion: 0,
                completionPricePerMillion: 0,
                isFree: false,
                availableProviders: [],
                availableQuantizations: []
            )
        ]

        let options = ShortcutModelOptionsBuilder.modelOptions(
            provider: "OPENROUTER",
            settings: settings,
            openRouterModels: cached
        )

        XCTAssertEqual(options.first, "openai/gpt-4o-mini")
        XCTAssertTrue(options.contains("cached/model-a"))
        XCTAssertFalse(options.contains("anthropic/claude-3.5-sonnet"))
    }

    func testOpenRouterOptionsUseFallbackWhenCacheEmpty() {
        let settings = AppSettings()
        let options = ShortcutModelOptionsBuilder.modelOptions(
            provider: "OPENROUTER",
            settings: settings,
            openRouterModels: []
        )

        XCTAssertTrue(options.contains("openai/gpt-4o"))
        XCTAssertTrue(options.contains("meta-llama/llama-3.1-8b-instruct:free"))
    }

    func testAppleIntelligenceOptionsIncludeOnDeviceAndPCC() {
        let settings = AppSettings()
        let options = ShortcutModelOptionsBuilder.modelOptions(
            provider: "APPLE_INTELLIGENCE",
            settings: settings,
            openRouterModels: []
        )

        XCTAssertEqual(options, AppleIntelligenceModelCatalog.supportedModels)
    }

    func testProviderOptionsMirrorBuiltInsAndSelectableModelsDevProviders() {
        let options = ShortcutModelOptionsBuilder.providerOptions(catalogProviders: [
            Self.catalogProvider(id: "opencode-go", name: "OpenCode Go", modelIDs: ["beam-free"]),
            Self.catalogProvider(id: "google", name: "Google", modelIDs: ["gemini-2.5-flash"])
        ])

        XCTAssertEqual(Array(options.prefix(ProviderCatalog.options.count)), ProviderCatalog.options)
        XCTAssertTrue(options.contains(ProviderDisplay(key: "MODELS_DEV:opencode-go", title: "OpenCode Go")))
        XCTAssertFalse(options.contains(where: { $0.key == "MODELS_DEV:google" }))
        XCTAssertFalse(options.contains(where: { $0.key == "OPENCODE_GO" }))
    }

    func testCodexOptionsIncludeOnlySupportedAccountCatalogModels() {
        let settings = AppSettings()
        let options = ShortcutModelOptionsBuilder.modelOptions(
            provider: "CODEX_AUTH",
            settings: settings,
            openRouterModels: [],
            codexModels: [
                PiCodexModel(id: "gpt-6.1-sol", name: "Sol", supported: true),
                PiCodexModel(id: "gpt-6-sol", name: "Old Sol", supported: true),
                PiCodexModel(id: "future-model", name: "Future", supported: false, reason: "pi_model_missing")
            ]
        )

        XCTAssertTrue(options.contains("gpt-6.1-sol"))
        XCTAssertTrue(options.contains("gpt-6-sol"))
        XCTAssertFalse(options.contains("future-model"))
    }

    func testCodexOptionsAreEmptyWithoutAnAccountCatalog() {
        let options = ShortcutModelOptionsBuilder.modelOptions(
            provider: "CODEX_AUTH",
            settings: AppSettings(),
            openRouterModels: []
        )

        XCTAssertFalse(options.contains("gpt-6.1-sol"))
    }

    func testModelsDevOptionsIncludeSavedModelAndCatalogModels() {
        var settings = AppSettings()
        settings.apiProvider = "MODELS_DEV:opencode-go"
        settings.defaultModel = "beam-free"
        let options = ShortcutModelOptionsBuilder.modelOptions(
            provider: "MODELS_DEV:opencode-go",
            settings: settings,
            openRouterModels: [],
            catalogProvider: Self.catalogProvider(id: "opencode-go", name: "OpenCode Go", modelIDs: ["glm-5.3", "beam-free"])
        )

        XCTAssertEqual(options, ["beam-free", "glm-5.3"])
    }

    static func catalogProvider(id: String, name: String, modelIDs: [String]) -> CatalogProvider {
        CatalogProvider(
            id: id,
            name: name,
            npm: "@ai-sdk/openai-compatible",
            env: [],
            models: modelIDs.map { modelID in
                CatalogModel(
                    id: modelID,
                    name: modelID,
                    reasoningOptions: [],
                    inputModalities: ["text"],
                    outputModalities: ["text"],
                    limits: CatalogLimits(context: nil, input: nil, output: nil),
                    cost: CatalogCost(
                        inputPerMillion: nil, outputPerMillion: nil, reasoningPerMillion: nil,
                        cacheReadPerMillion: nil, cacheWritePerMillion: nil
                    )
                )
            }
        )
    }
}
