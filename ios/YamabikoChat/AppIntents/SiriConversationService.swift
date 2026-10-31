import Foundation
import Combine

/// Shared navigation boundary for foreground App Intents, including cold launches.
@MainActor
final class SiriNavigation: ObservableObject {
    enum Request: Equatable {
        case conversation(Int64)
        case search(String)
    }

    static let shared = SiriNavigation()
    @Published private(set) var pendingRequest: Request?

    func request(_ request: Request) {
        pendingRequest = request
    }

    func consume() -> Request? {
        let request = pendingRequest
        pendingRequest = nil
        return request
    }
}

enum SiriConversationError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        L10n.text("Siri: 会話が見つからないか、利用できません。")
    }
}

enum SiriConversationService {
    static func conversationID(from url: URL) -> Int64? {
        guard url.scheme == "yamabikochat", url.host == "conversation",
              url.query == nil, url.fragment == nil,
              url.pathComponents.count == 2,
              let id = Int64(url.lastPathComponent), id > 0 else { return nil }
        return id
    }

    static func resolve(id: Int64, repository: ConversationRepository) throws -> ConversationEntity {
        guard let summary = try repository.externalConversationSummaries(ids: [id]).first else {
            throw SiriConversationError.unavailable
        }
        return ConversationEntity(summary)
    }
}
