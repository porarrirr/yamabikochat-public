import XCTest
import Combine
import GRDB
@testable import YamabikoChat

final class SiriConversationTests: XCTestCase {
    private func repository() throws -> ConversationRepository {
        let db = try DatabaseQueue()
        try AppDatabase.migrator.migrate(db)
        return ConversationRepository(dbQueue: db)
    }

    func testExternalSummariesMatchTitlesOnlyLiterallyAndExcludeSecret() throws {
        let repository = try repository()
        let titleID = try repository.createConversation(title: "Budget 100%_", model: "model", provider: "TEST")
        let bodyID = try repository.createConversation(title: "Travel", model: "model", provider: "TEST")
        _ = try repository.insertMessage(ChatMessage(conversationId: bodyID, role: "user", text: "Budget 100%_"))
        _ = try repository.insertMessage(ChatMessage(conversationId: bodyID, role: "model", text: "A later reply"))
        let secretID = try repository.createConversation(title: "Budget 100%_", model: "model", provider: "TEST", isSecret: true)
        _ = try repository.insertMessage(ChatMessage(conversationId: secretID, role: "user", text: "Budget 100%_"))
        let unrelatedID = try repository.createConversation(title: "Anything", model: "model", provider: "TEST")

        XCTAssertEqual(try repository.externalConversationSummaries(matching: " BUDGET 100%_ ").map(\.id), [titleID])
        XCTAssertFalse(try repository.externalConversationSummaries().contains { $0.id == secretID })
        XCTAssertTrue(try repository.externalConversationSummaries(ids: [secretID]).isEmpty)
        XCTAssertEqual(try repository.externalConversationSummaries(matching: "%_").map(\.id), [titleID])
        XCTAssertEqual(try repository.externalConversationSummaries(ids: [unrelatedID]).first?.id, unrelatedID)
        XCTAssertTrue(try repository.externalConversationSummaries(ids: []).isEmpty)
    }

    func testInAppSearchAlsoMatchesMessageBodiesAndExcludesSecret() throws {
        let repository = try repository()
        let titleID = try repository.createConversation(title: "Budget 100%_", model: "model", provider: "TEST")
        let bodyID = try repository.createConversation(title: "Travel", model: "model", provider: "TEST")
        _ = try repository.insertMessage(ChatMessage(conversationId: bodyID, role: "user", text: "Budget 100%_"))
        let secretID = try repository.createConversation(title: "Budget 100%_", model: "model", provider: "TEST", isSecret: true)
        _ = try repository.insertMessage(ChatMessage(conversationId: secretID, role: "user", text: "Budget 100%_"))

        XCTAssertEqual(Set(try repository.searchConversations(matching: " BUDGET 100%_ ").compactMap(\.id)), [titleID, bodyID])
        XCTAssertTrue(try repository.searchConversations(matching: "  ").isEmpty)
    }

    func testObservedExternalSummariesExcludeSecretConversations() throws {
        let repository = try repository()
        let visibleID = try repository.createConversation(title: "Visible", model: "model", provider: "TEST")
        _ = try repository.createConversation(title: "Hidden", model: "model", provider: "TEST", isSecret: true)
        let received = expectation(description: "summaries")
        var summaries: [ExternalConversationSummary] = []
        let cancellable = repository.observeExternalConversationSummaries().first().sink {
            summaries = $0
            received.fulfill()
        }
        wait(for: [received], timeout: 5)
        cancellable.cancel()
        XCTAssertEqual(summaries.map(\.id), [visibleID])
    }

    func testResolutionRechecksDeletedAndSecretEntities() throws {
        let repository = try repository()
        let id = try repository.createConversation(title: "Visible", model: "model", provider: "TEST")
        XCTAssertEqual(try SiriConversationService.resolve(id: id, repository: repository).title, "Visible")
        _ = try repository.setSecretModeIfEmpty(id: id, enabled: true)
        XCTAssertThrowsError(try SiriConversationService.resolve(id: id, repository: repository))
        try repository.deleteConversation(id: id)
        XCTAssertThrowsError(try SiriConversationService.resolve(id: id, repository: repository))
    }

    func testSuggestionsOrderAndLimit() throws {
        let repository = try repository()
        let older = try repository.upsertConversation(Conversation(title: "Old", model: "model", updatedAtMs: 1))
        let newer = try repository.upsertConversation(Conversation(title: "New", model: "model", updatedAtMs: 10))
        XCTAssertEqual(try repository.externalConversationSummaries(limit: 1).map(\.id), [newer])
        XCTAssertEqual(try repository.externalConversationSummaries(ids: [older]).map(\.id), [older])
    }

    func testIndexRemovesDeletedConversationsAndUpdatesRenames() {
        let first = ExternalConversationSummary(id: 1, title: "Old", updatedAtMs: 1)
        let second = ExternalConversationSummary(id: 2, title: "Became secret", updatedAtMs: 1)
        let deleted = ExternalConversationSummary(id: 3, title: "Deleted", updatedAtMs: 1)
        let renamed = ExternalConversationSummary(id: 1, title: "Renamed", updatedAtMs: 1)
        let plan = ConversationIndexPlan(previous: [1: first, 2: second, 3: deleted], entries: [renamed])
        XCTAssertEqual(Set(plan.removedIDs), [2, 3])
        XCTAssertEqual(plan.changed.map(\.title), ["Renamed"])
        XCTAssertEqual(Set(plan.current.keys), [1])
        let unchanged = ConversationIndexPlan(previous: plan.current, entries: [renamed])
        XCTAssertTrue(unchanged.changed.isEmpty)
        XCTAssertTrue(unchanged.removedIDs.isEmpty)
    }

    func testConversationLinksAreStrictlyParsed() {
        XCTAssertEqual(SiriConversationService.conversationID(from: URL(string: "yamabikochat://conversation/42")!), 42)
        for link in ["https://conversation/42", "yamabikochat://import-share/42", "yamabikochat://conversation/-1", "yamabikochat://conversation/0", "yamabikochat://conversation/42/extra", "yamabikochat://conversation/42?secret=1"] {
            XCTAssertNil(SiriConversationService.conversationID(from: URL(string: link)!))
        }
    }

    @MainActor
    func testNavigationSurvivesColdLaunchAndIsConsumedOnce() {
        let navigation = SiriNavigation()
        navigation.request(.conversation(42))
        XCTAssertEqual(navigation.consume(), .conversation(42))
        XCTAssertNil(navigation.consume())
        navigation.request(.search("travel"))
        XCTAssertEqual(navigation.consume(), .search("travel"))
    }
}
