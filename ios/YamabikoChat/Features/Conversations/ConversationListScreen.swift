import Foundation
import SwiftUI

struct ConversationListScreen: View {
    enum NavigationState: Equatable {
        case conversations
        case projectList
        case projectDetail(Int64)
    }

    @ObservedObject var viewModel: ConversationListViewModel
    @Binding var selection: Int64?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appAccent) private var appAccent
    @Environment(\.windowControlsLeadingInset) private var windowControlsLeadingInset

    var onSelect: (Int64) -> Void
    var onOpenSettings: () -> Void
    var onClose: (() -> Void)? = nil
    var allowsRowSwipeActions = true
    var onNavigationStateChange: ((NavigationState) -> Void)? = nil

    @State private var isSearchPresented = false
    @FocusState private var isSearchFocused: Bool
    @State private var navigationState: NavigationState = .conversations
    @State private var isDeleteConfirmationPresented = false
    @State private var conversationPendingDeletion: Int64?

    var body: some View {
        ZStack {
            switch navigationState {
            case .conversations:
                conversationsMainView
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .projectList:
                ProjectListScreen(
                    viewModel: viewModel,
                    onBack: {
                        navigate(to: .conversations)
                    },
                    onSelectProject: { projectId in
                        navigate(to: .projectDetail(projectId))
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .projectDetail(let projectId):
                ProjectDetailScreen(
                    viewModel: viewModel,
                    projectId: projectId,
                    onBack: {
                        navigate(to: .projectList)
                    },
                    onSelectConversation: { conversationId in
                        openConversation(id: conversationId)
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(.hidden, for: .navigationBar)
        .background(Color(uiColor: .amoledSystemBackground))
        .onAppear {
            if AppStoreScreenshotRouting.launchConfiguration()?.scene == .project,
               navigationState == .conversations {
                navigationState = .projectList
            }
            onNavigationStateChange?(navigationState)
        }
        .safeAreaInset(edge: .bottom) {
            if let error = viewModel.visibleErrorMessage {
                HStack(alignment: .top) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button {
                        viewModel.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text(L10n.text("エラーを閉じる")))
                }
                .padding(.horizontal, 12)
                .background(AMOLEDMaterial(material: .regularMaterial))
                .accessibilityElement(children: .combine)
            }
        }
        .alert(
            L10n.format("%d 件の会話を削除しますか？", viewModel.selectedConversationIds.count),
            isPresented: $isDeleteConfirmationPresented
        ) {
            Button(L10n.text("削除"), role: .destructive) {
                if let current = selection, viewModel.selectedConversationIds.contains(current) {
                    selection = nil
                }
                viewModel.deleteSelectedConversations()
            }
            Button(L10n.text("キャンセル"), role: .cancel) {}
        }
    }

    // MARK: - Conversations Main View

    private var conversationsMainView: some View {
        VStack(spacing: 0) {
            topHeader

            if !viewModel.isSelectionMode {
                drawerActionRow(
                    title: L10n.text("プロジェクト"),
                    systemImage: "folder",
                    badgeCount: viewModel.projects.count
                ) {
                    navigate(to: .projectList)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                Divider()
                    .padding(.horizontal, 20)
            }

            List {
                if viewModel.filteredConversations.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass")
                                .font(.system(size: 28))
                                .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))

                            Text(L10n.text(viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "会話がありません" : "該当する会話がありません"))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))

                            if viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button {
                                    createConversation(secret: false)
                                } label: {
                                    // Keep the button content centered instead of inheriting
                                    // the surrounding List's leading icon column.
                                    HStack(spacing: 8) {
                                        Image(systemName: "square.and.pencil")
                                        Text(L10n.text("新しいチャット"))
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            } else {
                                Button(L10n.text("検索を消去")) {
                                    viewModel.searchQuery = ""
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowSeparator(.hidden)
                    }
                } else {
                    ForEach(groupedConversations, id: \.title) { group in
                        Section {
                            ForEach(group.entries) { entry in
                            conversationRow(entry)
                                .listRowInsets(
                                    EdgeInsets(
                                        top: 1,
                                        leading: 12,
                                        bottom: 1,
                                        trailing: 12
                                    )
                                )
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        } header: {
                            Text(group.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
                                .textCase(nil)
                                .padding(.leading, 4)
                                .padding(.top, 12)
                                .padding(.bottom, 6)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .background(Color.clear)
            .environment(\.defaultMinListRowHeight, 48)

            Divider()
                .padding(.horizontal, 20)

            if viewModel.isSelectionMode {
                selectionActionBar
            } else {
                HStack(spacing: 12) {
                    settingsFooter
                    createConversationButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Top Header

    private var topHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text(L10n.text(viewModel.isSelectionMode ? "会話を選択" : "会話"))
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                if viewModel.isSelectionMode {
                    Button {
                        viewModel.exitSelectionMode()
                    } label: {
                        Text(L10n.text("完了"))
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("conversation-selection-done")
                } else {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            isSearchPresented.toggle()
                        }
                        isSearchFocused = isSearchPresented
                        if !isSearchPresented { viewModel.searchQuery = "" }
                    } label: {
                        Image(systemName: isSearchPresented ? "xmark" : "magnifyingglass")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 44, height: 44)
                            .background(Color(uiColor: .amoledSecondarySystemFill), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(L10n.text(isSearchPresented ? "検索を消去" : "会話を検索")))
                    .accessibilityIdentifier("conversation-search-toggle")
                    selectionButton
                }

                if let onClose {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !viewModel.isSelectionMode && isSearchPresented {
                searchField
            }
        }
        .padding(.horizontal, 16)
        .padding(.leading, windowControlsLeadingInset)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))

            TextField(
                L10n.text("会話を検索"),
                text: $viewModel.searchQuery,
                prompt: Text(L10n.text("会話を検索"))
                    .foregroundStyle(Color(uiColor: .amoledPlaceholderText))
            )
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(L10n.text("検索を消去")))
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(Color(uiColor: .amoledSecondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("conversation-search-field")
    }

    private var selectionButton: some View {
        Button {
            viewModel.toggleSelectionMode()
        } label: {
            Image(systemName: "checklist")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(L10n.text("会話を選択")))
        .accessibilityIdentifier("conversation-selection-button")
    }

    private var createConversationButton: some View {
        Button {
            createConversation(secret: false)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .medium))
                Text(L10n.text("新しいチャット"))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(appAccent.onAccentColor)
            .padding(.horizontal, 12)
            .frame(maxWidth: 200, minHeight: 44)
            .background(appAccent.color, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(L10n.text("新しいチャット")))
        .accessibilityIdentifier("sidebar-new-chat")
    }

    private var groupedConversations: [(title: String, entries: [ConversationListEntry])] {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: today) ?? today

        var todayEntries: [ConversationListEntry] = []
        var yesterdayEntries: [ConversationListEntry] = []
        var weekEntries: [ConversationListEntry] = []
        var olderEntries: [ConversationListEntry] = []

        for entry in viewModel.filteredConversations {
            let date = Date(timeIntervalSince1970: Double(entry.updatedAtMs) / 1_000)
            if date >= today {
                todayEntries.append(entry)
            } else if date >= yesterday {
                yesterdayEntries.append(entry)
            } else if date >= lastWeek {
                weekEntries.append(entry)
            } else {
                olderEntries.append(entry)
            }
        }

        return [
            (L10n.text("今日"), todayEntries),
            (L10n.text("昨日"), yesterdayEntries),
            (L10n.text("過去7日間"), weekEntries),
            (L10n.text("それ以前"), olderEntries)
        ].filter { !$0.entries.isEmpty }
    }

    // MARK: - Settings Footer

    private var settingsFooter: some View {
        Button {
            onOpenSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
            .frame(width: 48, height: 48)
            .background(Color(uiColor: .amoledSecondarySystemFill), in: Circle())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("設定"))
        .accessibilityIdentifier("open-settings")
        .background(Color(uiColor: .amoledSystemBackground))
    }

    // MARK: - Selection Action Bar

    private var selectionActionBar: some View {
        HStack {
            Button {
                if viewModel.isAllSelected {
                    viewModel.deselectAll()
                } else {
                    viewModel.selectAll()
                }
            } label: {
                Text(viewModel.isAllSelected ? "全解除" : "すべて選択")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(L10n.format("%d 件選択中", viewModel.selectedConversationIds.count))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))

            Spacer()

            Button {
                isDeleteConfirmationPresented = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(viewModel.selectedConversationIds.isEmpty ? Color.secondary : Color.red)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.selectedConversationIds.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .amoledSystemBackground))
    }

    // MARK: - Drawer Action Row

    @ViewBuilder
    private func drawerActionRow(
        title: String,
        systemImage: String,
        badgeCount: Int? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(appAccent.color)
                    .frame(width: 24, height: 28)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                if let badgeCount, badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(uiColor: .amoledSecondarySystemFill))
                        )
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .amoledTertiaryLabel))
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Conversation Row

    @ViewBuilder
    private func conversationRow(_ entry: ConversationListEntry) -> some View {
        Button {
            if viewModel.isSelectionMode {
                viewModel.toggleSelection(id: entry.id)
            } else {
                openConversation(id: entry.id)
            }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isSelectionMode {
                    Image(systemName: viewModel.selectedConversationIds.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(viewModel.selectedConversationIds.contains(entry.id) ? appAccent.color : .secondary)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        Text(entry.title)
                            .font(.body)
                            .lineLimit(2)
                            .foregroundStyle(.primary)

                        if entry.isSecret {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(L10n.text("シークレット"))
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundStyle(appAccent.color)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(appAccent.color.opacity(0.12))
                            .clipShape(Capsule())
                        }

                        Spacer(minLength: 4)
                        if selection == entry.id && !viewModel.isSelectionMode {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(appAccent.color)
                                .accessibilityHidden(true)
                        }
                    }

                    if let projectTitle = entry.projectTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !projectTitle.isEmpty {
                        let project = viewModel.projects.first { $0.id == entry.projectId }
                        HStack(spacing: 4) {
                            Image(systemName: project?.iconName ?? "folder")
                            Text(projectTitle)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(project.map { Color(hex: $0.colorHex) } ?? Color(uiColor: .amoledSecondaryLabel))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(rowBackgroundColor(for: entry.id))
            )
        }
        .siriConversationContext(id: entry.id, isSecret: entry.isSecret)
        .buttonStyle(.plain)
        .accessibilityIdentifier("conversation-row-\(entry.id)")
        .accessibilityAddTraits(selection == entry.id && !viewModel.isSelectionMode ? .isSelected : [])
        // Anchor the popover to this row, not the entire sidebar.
        .confirmationDialog(
            L10n.text("この会話を削除しますか？"),
            isPresented: Binding(
                get: { conversationPendingDeletion == entry.id },
                set: { isPresented in
                    if !isPresented && conversationPendingDeletion == entry.id {
                        conversationPendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.text("削除"), role: .destructive) {
                if selection == entry.id { selection = nil }
                viewModel.deleteConversation(id: entry.id)
                conversationPendingDeletion = nil
            }
            Button(L10n.text("キャンセル"), role: .cancel) {
                conversationPendingDeletion = nil
            }
        }
        .accessibilityValue(viewModel.selectedConversationIds.contains(entry.id) ? Text(L10n.text("選択済み")) : Text(""))
        .contextMenu(viewModel.isSelectionMode ? nil : ContextMenu {
            Button {
                viewModel.isSelectionMode = true
                viewModel.selectedConversationIds.insert(entry.id)
            } label: {
                Label("選択", systemImage: "checkmark.circle")
            }

            if !allowsRowSwipeActions {
                Button(role: .destructive) {
                    conversationPendingDeletion = entry.id
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }

            if !viewModel.projects.isEmpty {
                ForEach(viewModel.projects) { project in
                    Button {
                        viewModel.assignConversation(id: entry.id, to: project.id)
                    } label: {
                        if entry.projectId == project.id {
                            Label(project.title, systemImage: "checkmark")
                        } else {
                            Text(project.title)
                        }
                    }
                }

                if entry.projectId != nil {
                    Button("プロジェクトから外す") {
                        viewModel.assignConversation(id: entry.id, to: nil)
                    }
                }
            }
        })
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if allowsRowSwipeActions && !viewModel.isSelectionMode {
                Button {
                    openConversation(id: entry.id)
                } label: {
                    Label("開く", systemImage: "arrow.up.forward.app")
                }
                .tint(.blue)

                Button(role: .destructive) {
                    conversationPendingDeletion = entry.id
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
        }
    }

    private func rowBackgroundColor(for id: Int64) -> Color {
        guard selection == id else { return .clear }
        return appAccent.color.opacity(0.12)
    }

    private func createConversation(secret: Bool) {
        if let id = viewModel.createConversation(secret: secret) {
            openConversation(id: id)
        }
    }

    private func openConversation(id: Int64) {
        onSelect(id)
    }

    private func navigate(to destination: NavigationState) {
        if reduceMotion {
            navigationState = destination
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                navigationState = destination
            }
        }
        onNavigationStateChange?(destination)
    }
}
