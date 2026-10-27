import XCTest
@testable import YamabikoChat

private final class DiscoveryHTTPClient: HTTPClientProtocol {
    var requests: [HTTPRequest] = []
    var pages: [String]
    var status = 200

    init(_ pages: [String]) { self.pages = pages }

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let body = pages[min(requests.count - 1, pages.count - 1)]
        return (Data(body.utf8), HTTPURLResponse(url: request.url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

final class CustomEndpointTests: XCTestCase {
    func testDiscoveryAllProtocolsUsesExplicitURLAndAuthentication() async throws {
        for api in ["openai-completions", "openai-responses", "anthropic-messages", "google-generative-ai", "mistral-conversations"] {
            let gemini = api == "google-generative-ai"
            let client = DiscoveryHTTPClient([gemini ? #"{"models":[{"name":"models/private-id","displayName":"Private"}]}"# : #"{"data":[{"id":"private-id"}]}"#])
            let models = try await CustomEndpointModelService(httpClient: client).fetch(baseURL: "https://example.com/custom/v1/", apiProtocol: api, apiKey: "test-key")
            XCTAssertEqual(models.map(\.id), ["private-id"])
            let request = try XCTUnwrap(client.requests.first)
            XCTAssertEqual(request.url.absoluteString, "https://example.com/custom/v1/models")
            XCTAssertEqual(request.method, "GET")
            let header = gemini ? "x-goog-api-key" : api == "anthropic-messages" ? "x-api-key" : "Authorization"
            XCTAssertEqual(request.headers[header], header == "Authorization" ? "Bearer test-key" : "test-key")
            XCTAssertNil(request.url.query)
        }
    }

    func testDiscoveryPaginationKeepsSameEndpointAndDeduplicatesExactIDs() async throws {
        for api in ["anthropic-messages", "google-generative-ai"] {
            let anthropic = api == "anthropic-messages"
            let client = DiscoveryHTTPClient(anthropic ? [
                #"{"data":[{"id":"b"},{"id":"B"}],"has_more":true,"last_id":"B"}"#,
                #"{"data":[{"id":"b"},{"id":"a"}],"has_more":false}"#
            ] : [
                #"{"models":[{"name":"models/b"},{"name":"models/B"}],"nextPageToken":"next token"}"#,
                #"{"models":[{"name":"models/b"},{"name":"models/a"}]}"#
            ])
            let models = try await CustomEndpointModelService(httpClient: client).fetch(baseURL: "https://example.com/v1", apiProtocol: api, apiKey: nil)
            XCTAssertEqual(Set(models.map(\.id)), Set(["a", "b", "B"]))
            XCTAssertEqual(client.requests.count, 2)
            let components = URLComponents(url: client.requests[1].url, resolvingAgainstBaseURL: false)
            XCTAssertEqual(components?.host, "example.com")
            XCTAssertEqual(components?.queryItems?.first?.name, anthropic ? "after_id" : "pageToken")
            XCTAssertEqual(components?.queryItems?.first?.value, anthropic ? "B" : "next token")
        }
    }

    func testDiscoveryRejectsInvalidConfigurationWithoutSendingCredentials() async {
        for base in ["http://example.com/v1", "https://user:pass@example.com/v1", "https://example.com/v1?key=secret", "file:///tmp"] {
            let client = DiscoveryHTTPClient([#"{"data":[]}"#])
            do {
                _ = try await CustomEndpointModelService(httpClient: client).fetch(baseURL: base, apiProtocol: "openai-completions", apiKey: "test-key")
                XCTFail("Expected invalid URL")
            } catch { XCTAssertTrue(client.requests.isEmpty) }
        }
    }

    func testDiscoveryStopsOnHTTPFailureWithoutFallbackOrResponseBodyLeak() async {
        let client = DiscoveryHTTPClient(["echoed-test-key"])
        client.status = 401
        do {
            _ = try await CustomEndpointModelService(httpClient: client).fetch(baseURL: "https://example.com/v1", apiProtocol: "openai-responses", apiKey: "test-key")
            XCTFail("Expected failure")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains("test-key"))
            XCTAssertTrue(error.localizedDescription.contains("401"))
            XCTAssertEqual(client.requests.count, 1)
        }
    }

    func testDiscoveryRejectsMalformedAndRepeatingPages() async {
        for page in [#"{"error":"invalid"}"#, #"{"data":[{}]}"#, #"{"data":[{"id":"a"}],"has_more":true,"last_id":"a"}"#] {
            let client = DiscoveryHTTPClient([page])
            do {
                _ = try await CustomEndpointModelService(httpClient: client).fetch(baseURL: "https://example.com/v1", apiProtocol: "anthropic-messages", apiKey: nil)
                XCTFail("Expected failure")
            } catch { XCTAssertLessThanOrEqual(client.requests.count, 2) }
        }
    }

    func testLegacyPresetAndMultipleModelsRoundTripWithoutChangingSettings() throws {
        let legacy = Data(#"{"name":"Legacy","baseUrl":"https://example.com/v1","protocol":"openai-responses","modelId":"first"}"#.utf8)
        var preset = try JSONDecoder().decode(OpenAICompatPreset.self, from: legacy)
        XCTAssertEqual(preset.configuredModels.map(\.modelId), ["first"])
        preset.storeCurrentModel()
        preset.modelId = "second"
        preset.contextWindow = 64000
        preset.maxTokens = 16000
        preset.reasoning = true
        preset.reasoningEffort = "high"
        preset.apiProtocol = "anthropic-messages"
        preset.storeCurrentModel()
        let decoded = try JSONDecoder().decode(OpenAICompatPreset.self, from: JSONEncoder().encode(preset))
        XCTAssertEqual(decoded, preset)
        XCTAssertEqual(decoded.configuredModels.map(\.modelId), ["first", "second"])
        let first = try XCTUnwrap(decoded.resolving(modelID: "first"))
        XCTAssertEqual(first.apiProtocol, "openai-responses")
        XCTAssertFalse(first.reasoning)
        XCTAssertEqual(first.contextWindow, 128000)
        let second = try XCTUnwrap(decoded.resolving(modelID: "second"))
        XCTAssertEqual(second.apiProtocol, "anthropic-messages")
        XCTAssertEqual(second.contextWindow, 64000)
        XCTAssertEqual(second.maxTokens, 16000)
        XCTAssertEqual(second.reasoningEffort, "high")
        XCTAssertTrue(second.models.isEmpty)
        XCTAssertNil(decoded.resolving(modelID: "missing"))
    }

    @MainActor
    func testReopeningCurrentEndpointPreservesSelectedAndUnsupportedSavedModels() throws {
        let viewModel = SettingsViewModel()
        var preset = OpenAICompatPreset(name: "Private", baseURL: "https://example.com/v1")
        preset.apiProtocol = "openai-responses"
        preset.modelId = "first"
        preset.storeCurrentModel()
        preset.modelId = "second"
        preset.storeCurrentModel()
        viewModel.settings.openAICompatPresetsJSON = String(decoding: try JSONEncoder().encode([preset]), as: UTF8.self)
        viewModel.settings.selectedOpenAICompatPreset = preset.name
        viewModel.settings.defaultModel = "first"
        viewModel.selectCustomEndpointPreset(preset.name)
        XCTAssertEqual(viewModel.settings.defaultModel, "first")
        XCTAssertEqual(viewModel.customEndpointDraft.modelId, "first")
        viewModel.settings.defaultModel = "unsupported-saved-model"
        viewModel.selectCustomEndpointPreset(preset.name)
        XCTAssertEqual(viewModel.settings.defaultModel, "unsupported-saved-model")
    }

    @MainActor
    func testNewEndpointDoesNotInheritPreviousEndpointCredentialOrDiscovery() {
        let viewModel = SettingsViewModel()
        viewModel.openAICompatApiKeyInput = "previous-key"
        viewModel.customEndpointDiscoveredModels = [.init(id: "previous-model", name: "Previous")]
        viewModel.selectCustomEndpointPreset("")
        XCTAssertTrue(viewModel.openAICompatApiKeyInput.isEmpty)
        XCTAssertTrue(viewModel.customEndpointDiscoveredModels.isEmpty)
        XCTAssertTrue(viewModel.customEndpointDraft.models.isEmpty)
        XCTAssertTrue(viewModel.customEndpointDraft.baseURL.isEmpty)
        XCTAssertNil(viewModel.settings.selectedOpenAICompatPreset)
    }

    @MainActor
    func testDiscoveryDoesNotAutomaticallyRegisterOrSelectModels() async {
        let viewModel = SettingsViewModel()
        viewModel.customEndpointDraft.baseURL = "https://example.com/v1"
        viewModel.customEndpointDraft.apiProtocol = "openai-responses"
        let settingsBefore = viewModel.settings
        let client = DiscoveryHTTPClient([#"{"data":[{"id":"first"},{"id":"second"}]}"#])
        await viewModel.fetchCustomEndpointModels(service: CustomEndpointModelService(httpClient: client))
        XCTAssertFalse(viewModel.customEndpointModelsLoading)
        XCTAssertNil(viewModel.customEndpointModelsError)
        XCTAssertEqual(viewModel.customEndpointDiscoveredModels.count, 2)
        XCTAssertEqual(viewModel.settings, settingsBefore)
        viewModel.customEndpointModelSearch = "SECOND"
        XCTAssertEqual(viewModel.filteredCustomEndpointDiscoveredModels.map(\.id), ["second"])
        viewModel.chooseDiscoveredCustomEndpointModel("second")
        XCTAssertEqual(viewModel.customEndpointDraft.modelId, "second")
        XCTAssertTrue(viewModel.customEndpointDraft.models.isEmpty)
        XCTAssertEqual(viewModel.settings, settingsBefore)
        viewModel.invalidateCustomEndpointDiscovery()
        XCTAssertTrue(viewModel.customEndpointDiscoveredModels.isEmpty)
        XCTAssertTrue(viewModel.customEndpointModelSearch.isEmpty)
    }

    @MainActor
    func testFailedDiscoveryPreservesSettingsAndAllowsManualEntry() async {
        let viewModel = SettingsViewModel()
        viewModel.customEndpointDraft.baseURL = "https://example.com/v1"
        viewModel.customEndpointDraft.apiProtocol = "openai-responses"
        viewModel.customEndpointDraft.modelId = "manual-model"
        let before = viewModel.settings
        let client = DiscoveryHTTPClient(["invalid response"])
        client.status = 404
        await viewModel.fetchCustomEndpointModels(service: CustomEndpointModelService(httpClient: client))
        XCTAssertNotNil(viewModel.customEndpointModelsError)
        XCTAssertFalse(viewModel.customEndpointModelsLoading)
        XCTAssertEqual(viewModel.customEndpointDraft.modelId, "manual-model")
        XCTAssertEqual(viewModel.settings, before)
        XCTAssertTrue(viewModel.customEndpointDiscoveredModels.isEmpty)
    }

    @MainActor
    func testEditorAddsUpdatesAndDeletesModelsWithoutLosingExistingConfigurationOrKeyDraft() throws {
        let viewModel = SettingsViewModel()
        viewModel.customEndpointDraft.name = "Private"
        viewModel.customEndpointDraft.baseURL = "https://example.com/v1"
        viewModel.customEndpointDraft.apiProtocol = "openai-responses"
        viewModel.customEndpointDraft.modelId = "first"
        viewModel.customEndpointDraft.vision = true
        viewModel.openAICompatApiKeyInput = "test-key"
        viewModel.addOrUpdateOpenAICompatPreset()
        viewModel.newCustomEndpointModel(id: "second")
        XCTAssertFalse(viewModel.customEndpointDraft.vision)
        viewModel.customEndpointDraft.contextWindow = 32000
        viewModel.addOrUpdateOpenAICompatPreset()
        XCTAssertEqual(viewModel.selectedCustomEndpointModels.map(\.modelId), ["first", "second"])
        XCTAssertEqual(viewModel.openAICompatApiKeyInput, "test-key")
        viewModel.editCustomEndpointModel("first")
        XCTAssertTrue(viewModel.customEndpointDraft.vision)
        viewModel.customEndpointDraft.toolCall = true
        viewModel.addOrUpdateOpenAICompatPreset()
        XCTAssertEqual(viewModel.selectedCustomEndpointModels.count, 2)
        XCTAssertTrue(viewModel.selectedCustomEndpointModels[0].toolCall)
        viewModel.removeCustomEndpointModel("first")
        XCTAssertEqual(viewModel.selectedCustomEndpointModels.map(\.modelId), ["second"])
        XCTAssertEqual(viewModel.settings.defaultModel, "second")
        XCTAssertEqual(viewModel.customEndpointDraft.contextWindow, 32000)
    }
}
