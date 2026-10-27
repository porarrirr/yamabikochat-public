import Combine

/// Reconnects a conversation's screen to its existing run after navigation.
@MainActor
final class ChatViewModelStore: ObservableObject {
    private struct Entry {
        weak var viewModel: ChatViewModel?
    }

    private var entries: [Int64: Entry] = [:]
    // Keep the current draft/run alive while SwiftUI replaces navigation containers.
    private var presentedViewModel: ChatViewModel?
    private var presentedConversationID: Int64?

    func viewModel(conversationID: Int64) -> ChatViewModel {
        entries = entries.filter { $0.value.viewModel != nil }
        if let viewModel = entries[conversationID]?.viewModel {
            retainPresentation(viewModel, conversationID: conversationID)
            return viewModel
        }

        let viewModel = ChatViewModel(conversationID: conversationID)
        // Only the presented conversation is retained; other entries remain weak.
        entries[conversationID] = Entry(viewModel: viewModel)
        retainPresentation(viewModel, conversationID: conversationID)
        return viewModel
    }

    private func retainPresentation(_ viewModel: ChatViewModel, conversationID: Int64) {
        if let previousID = presentedConversationID, previousID != conversationID {
            releasePresentation(conversationID: previousID)
        }
        presentedViewModel = viewModel
        presentedConversationID = conversationID
    }

    func releasePresentation(conversationID: Int64) {
        entries[conversationID]?.viewModel?.handleWorkspaceDisappearance()
        if presentedConversationID == conversationID {
            presentedViewModel = nil
            presentedConversationID = nil
        }
    }

    func removeConversations(ids: Set<Int64>) {
        for id in ids {
            let viewModel = entries[id]?.viewModel
            releasePresentation(conversationID: id)
            entries.removeValue(forKey: id)
            viewModel?.cancelActiveRun()
            if viewModel?.isAutoConversationRunning == true || viewModel?.isAutoConversationPaused == true {
                viewModel?.stopAutoConversation()
            }
        }
    }
}
