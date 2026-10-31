import XCTest
import GRDB
@testable import YamabikoChat

private final class TestCredentialStore: SecureCredentialStore {
    private var storage: [String: String] = [:]

    func saveSecret(_ value: String?, key: String) throws {
        if let value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }

    func readSecret(key: String) throws -> String? {
        storage[key]
    }

    func deleteSecret(key: String) throws {
        storage.removeValue(forKey: key)
    }
}

private struct NoopPricingRepository: LiteLlmPricingEstimating {
    func estimateCostUsd(
        provider: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cachedInputTokens: Int?,
        cacheCreationInputTokens: Int?,
        reasoningTokens: Int?
    ) async -> Double? {
        nil
    }

    func modelSupportsVision(provider: String, model: String) async -> Bool {
        false
    }
}

final class ShortcutRunTests: XCTestCase {
    func testRunShortcutAskOnlyReturnsTextWithoutPersistingConversation() async throws {
        let runtime = successRuntime()
        let fixture = try makeFixture(runtime: runtime) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = "openai/gpt-4o-mini"
            settings.isStreamingEnabled = true
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)

        let conversationCountBefore = try await fixture.dbQueue.read { db in
            try Conversation.fetchCount(db)
        }

        let result = try await fixture.repository.runShortcut(
            prompt: "hello shortcut",
            provider: "OPENROUTER",
            model: "openai/gpt-4o-mini",
            systemPromptOverride: "system from shortcut",
            saveToNewConversation: false
        )

        XCTAssertEqual(result.text, "shortcut answer")
        XCTAssertNil(result.conversationId)
        XCTAssertNil(result.userMessageId)
        XCTAssertNil(result.assistantMessageId)

        let conversationCountAfter = try await fixture.dbQueue.read { db in
            try Conversation.fetchCount(db)
        }
        XCTAssertEqual(conversationCountAfter, conversationCountBefore)

        let request = try XCTUnwrap(runtime.calls.last?.request)
        XCTAssertFalse(request.stream)
        XCTAssertEqual(request.model, "openai/gpt-4o-mini")
        XCTAssertEqual(request.messages.last?.content, "hello shortcut")
    }

    func testRunShortcutSaveCreatesConversationMessagesThinkingAndTokenUsage() async throws {
        let titleGenerator = ConversationTitleGeneratorSpy(generatedTitle: "Saved shortcut title")
        let fixture = try makeFixture(
            runtime: successRuntime(),
            conversationTitleGenerator: titleGenerator
        ) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = "openai/gpt-4o-mini"
            settings.isStreamingEnabled = false
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)

        let result = try await fixture.repository.runShortcut(
            prompt: "save this",
            provider: "OPENROUTER",
            model: "openai/gpt-4o-mini",
            systemPromptOverride: "saved system prompt",
            saveToNewConversation: true
        )

        XCTAssertEqual(result.text, "shortcut answer")
        let conversationID = try XCTUnwrap(result.conversationId)
        let assistantMessageID = try XCTUnwrap(result.assistantMessageId)

        let conversation = try fixture.repository.conversation(id: conversationID)
        XCTAssertEqual(conversation?.apiProvider, "OPENROUTER")
        XCTAssertEqual(conversation?.model, "openai/gpt-4o-mini")
        XCTAssertEqual(conversation?.systemPrompt, "saved system prompt")
        XCTAssertEqual(conversation?.title, "Saved shortcut title")
        XCTAssertEqual(
            titleGenerator.requests,
            [.init(firstPrompt: "save this", firstResponse: "shortcut answer")]
        )

        let messages = try fixture.conversations.fetchMessages(conversationId: conversationID)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, "user")
        XCTAssertEqual(messages[0].text, "save this")
        XCTAssertEqual(messages[1].role, "model")
        XCTAssertEqual(messages[1].text, "shortcut answer")

        let assistant = try XCTUnwrap(fixture.conversations.fetchFullMessage(id: assistantMessageID))
        XCTAssertEqual(assistant.thinkingStream, "shortcut thinking")

        let usageRecord = try await fixture.dbQueue.read { db in
            try TokenUsageRecord.fetchOne(db)
        }
        XCTAssertEqual(usageRecord?.requestType, "shortcut")
        XCTAssertEqual(usageRecord?.conversationId, conversationID)
        XCTAssertEqual(usageRecord?.inputTokens, 10)
        XCTAssertEqual(usageRecord?.outputTokens, 5)
    }

    func testRunShortcutAcceptsCustomModelIDOutsideCatalog() async throws {
        let runtime = successRuntime()
        let fixture = try makeFixture(runtime: runtime) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = "openai/gpt-4o-mini"
            settings.isStreamingEnabled = false
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)

        let result = try await fixture.repository.runShortcut(
            prompt: "custom model",
            provider: "OPENROUTER",
            model: "vendor/custom-model-id",
            saveToNewConversation: false
        )

        XCTAssertEqual(result.text, "shortcut answer")
        XCTAssertEqual(runtime.calls.last?.request.model, "vendor/custom-model-id")
    }

    func testRunShortcutRejectsEmptyPrompt() async throws {
        let fixture = try makeFixture()
        do {
            _ = try await fixture.repository.runShortcut(
                prompt: "   ",
                provider: "OPENROUTER",
                model: "openai/gpt-4o-mini",
                saveToNewConversation: false
            )
            XCTFail("Expected empty prompt to throw")
        } catch let error as ProviderClientError {
            if case let .parseFailure(message) = error {
                XCTAssertEqual(message, L10n.text("Shortcuts: プロンプトを入力してください。"))
            } else {
                XCTFail("Unexpected ProviderClientError: \(error)")
            }
        }
    }

    func testRunShortcutRejectsEmptyModel() async throws {
        let fixture = try makeFixture()
        do {
            _ = try await fixture.repository.runShortcut(
                prompt: "hello",
                provider: "OPENROUTER",
                model: "  ",
                saveToNewConversation: false
            )
            XCTFail("Expected empty model to throw")
        } catch let error as ProviderClientError {
            if case let .parseFailure(message) = error {
                XCTAssertEqual(message, L10n.text("Shortcuts: モデル ID を入力してください。"))
            } else {
                XCTFail("Unexpected ProviderClientError: \(error)")
            }
        }
    }

    func testRunShortcutRejectsUnknownProvider() async throws {
        let fixture = try makeFixture()
        do {
            _ = try await fixture.repository.runShortcut(
                prompt: "hello",
                provider: "NOT_A_PROVIDER",
                model: "openai/gpt-4o-mini",
                saveToNewConversation: false
            )
            XCTFail("Expected unknown provider to throw")
        } catch let error as ProviderClientError {
            if case let .parseFailure(message) = error {
                XCTAssertEqual(message, L10n.text("Shortcuts: 不明なプロバイダです。"))
            } else {
                XCTFail("Unexpected ProviderClientError: \(error)")
            }
        }
    }

    func testRunShortcutAcceptsEveryShortcutProviderOption() async throws {
        let fixture = try makeFixture()
        let options = ShortcutModelOptionsBuilder.providerOptions(catalogProviders: [
            ShortcutModelOptionsTests.catalogProvider(id: "opencode-go", name: "OpenCode Go", modelIDs: ["beam-free"])
        ])
        let unknownProvider = L10n.text("Shortcuts: 不明なプロバイダです。")

        for option in options {
            do {
                _ = try await fixture.repository.runShortcut(
                    prompt: "hello",
                    provider: option.key,
                    model: "model-id",
                    saveToNewConversation: false
                )
            } catch let ProviderClientError.parseFailure(message) where message == unknownProvider {
                XCTFail("Shortcut provider option \(option.key) was rejected as unknown")
            } catch {
                // Credential or model resolution failures are expected here; only provider validation is under test.
            }
        }
    }

    func testRunShortcutPropagatesProviderHTTPError() async throws {
        let runtime = PiStreamSpy { _, _ in
            throw ProviderClientError.httpStatus(500, "provider failed")
        }
        let fixture = try makeFixture(runtime: runtime) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = "openai/gpt-4o-mini"
            settings.isStreamingEnabled = false
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)

        do {
            _ = try await fixture.repository.runShortcut(
                prompt: "hello",
                provider: "OPENROUTER",
                model: "openai/gpt-4o-mini",
                saveToNewConversation: false
            )
            XCTFail("Expected provider HTTP error to throw")
        } catch {
            XCTAssertTrue(error is ProviderClientError)
        }
    }

    func testRunShortcutAppliesReasoningEffortForThisRunOnly() async throws {
        let runtime = successRuntime()
        let fixture = try makeFixture(runtime: runtime) { settings in
            settings.geminiThinkingEnabled = true
            settings.geminiThinkingLevel = "high"
        }
        try fixture.credentials.setCredential("gemini-key", for: .gemini)

        _ = try await fixture.repository.runShortcut(
            prompt: "think lightly",
            provider: "GEMINI",
            model: "gemini-3-flash-preview",
            reasoningEffort: "low",
            saveToNewConversation: false
        )

        XCTAssertEqual(runtime.calls.last?.request.metadata["geminiThinkingLevel"], "low")
        XCTAssertEqual(try fixture.repository.loadSettings().geminiThinkingLevel, "high")
    }

    func testRunShortcutRejectsReasoningEffortTheModelDoesNotOffer() async throws {
        let runtime = successRuntime()
        let fixture = try makeFixture(runtime: runtime)
        try fixture.credentials.setCredential("gemini-key", for: .gemini)

        do {
            _ = try await fixture.repository.runShortcut(
                prompt: "hello",
                provider: "GEMINI",
                model: "gemini-3-pro-preview",
                reasoningEffort: "minimal",
                saveToNewConversation: false
            )
            XCTFail("Expected unsupported effort to throw")
        } catch let ProviderClientError.parseFailure(message) {
            XCTAssertEqual(message, L10n.text("このモデルでは推論エフォートを変更できません。"))
        }
        XCTAssertTrue(runtime.calls.isEmpty)
    }

    func testRunShortcutAllowedToolsDefineTheAppToolsForThisRun() async throws {
        let runtime = successRuntime()
        let fixture = try makeFixture(runtime: runtime) { settings in
            settings.clientWebSearchToolEnabled = true
            settings.pythonToolEnabled = false
            settings.genUIToolEnabled = true
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)

        _ = try await fixture.repository.runShortcut(
            prompt: "calculate",
            provider: "OPENROUTER",
            model: "openai/gpt-4o-mini",
            allowedTools: [.python],
            saveToNewConversation: false
        )

        let request = try XCTUnwrap(runtime.calls.last?.request)
        XCTAssertEqual(functionToolNames(request), [PythonExecuteTool.name])
        let saved = try fixture.repository.loadSettings()
        XCTAssertTrue(saved.clientWebSearchToolEnabled)
        XCTAssertFalse(saved.pythonToolEnabled)
    }

    func testRunShortcutEmptyAllowedToolsSendsNoAppTools() async throws {
        let runtime = successRuntime()
        let fixture = try makeFixture(runtime: runtime) { settings in
            settings.clientWebSearchToolEnabled = true
            settings.genUIToolEnabled = true
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)

        _ = try await fixture.repository.runShortcut(
            prompt: "no tools",
            provider: "OPENROUTER",
            model: "openai/gpt-4o-mini",
            allowedTools: [],
            saveToNewConversation: false
        )

        XCTAssertEqual(functionToolNames(try XCTUnwrap(runtime.calls.last?.request)), [])
    }

    func testRunShortcutWithoutAllowedToolsKeepsAppToolSettings() async throws {
        let runtime = successRuntime()
        let fixture = try makeFixture(runtime: runtime) { settings in
            settings.clientWebSearchToolEnabled = true
            settings.pythonToolEnabled = false
            settings.genUIToolEnabled = false
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)

        _ = try await fixture.repository.runShortcut(
            prompt: "default tools",
            provider: "OPENROUTER",
            model: "openai/gpt-4o-mini",
            saveToNewConversation: false
        )

        XCTAssertEqual(
            functionToolNames(try XCTUnwrap(runtime.calls.last?.request)),
            [WebSearchTool.name, FetchUrlTool.name, StrReplaceEditorTool.name]
        )
    }

    private func functionToolNames(_ request: ProviderRequest) -> Set<String> {
        Set(request.tools.filter { $0.type == "function" }.compactMap { $0.payload["name"] })
    }

    private func makeFixture(
        runtime: PiStreamSpy = PiStreamSpy(),
        conversationTitleGenerator: any ConversationTitleGenerating = ConversationTitleGeneratorSpy(),
        configureSettings: ((inout AppSettings) -> Void)? = nil
    ) throws -> (
        repository: ChatRepository,
        conversations: ConversationRepository,
        credentials: TestCredentialStore,
        dbQueue: DatabaseQueue
    ) {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)

        let settings = SettingsRepository(dbQueue: dbQueue)
        let conversations = ConversationRepository(dbQueue: dbQueue)
        let credentials = TestCredentialStore()
        if configureSettings != nil {
            var current = try settings.load()
            configureSettings?(&current)
            try settings.save(current)
        }

        let repository = ChatRepositoryTestSupport.makeRepository(
            dbQueue: dbQueue,
            settings: settings,
            conversations: conversations,
            credentials: credentials,
            piStream: runtime.stream,
            pricingRepository: NoopPricingRepository(),
            conversationTitleGenerator: conversationTitleGenerator
        )
        return (repository, conversations, credentials, dbQueue)
    }

    private func successRuntime() -> PiStreamSpy {
        PiStreamSpy { _, _ in
            [.completed(ProviderResponse(
                text: "shortcut answer",
                reasoningSummary: "shortcut thinking",
                usage: ProviderUsage(inputTokens: 10, outputTokens: 5, totalTokens: 15)
            ))]
        }
    }
}
