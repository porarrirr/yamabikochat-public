import SwiftUI

struct ChatModelPickerSheet: View {
    @Environment(\.appAccent) private var appAccent
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""

    private var presets: [ModelPreset] {
        let values = viewModel.availableChatPresets()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return values }
        return values.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
                $0.model.localizedCaseInsensitiveContains(query) ||
                ProviderCatalog.displayName(for: $0.apiProvider).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            AMOLEDList(usesRaisedBackground: true) {
                if presets.isEmpty {
                    ContentUnavailableView.search(text: searchQuery)
                } else {
                    ForEach(groupedProviders, id: \.provider) { group in
                        Section(group.displayName) {
                            ForEach(group.presets) { preset in
                                Button {
                                    viewModel.applyChatPreset(preset)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(preset.model)
                                                .font(.body.weight(.medium))
                                                .foregroundStyle(.primary)
                                            Text((preset.id ?? 0) < 0 ? L10n.text("設定で選んだモデル") : preset.name)
                                                .font(.subheadline)
                                                .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
                                                .lineLimit(2)
                                        }
                                        Spacer()
                                        if isActive(preset) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(appAccent.color)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .contentMargins(.top, 8, for: .scrollContent)
            .listSectionSpacing(16)
            .pinnedListSearch(text: $searchQuery, prompt: L10n.text("モデルまたは接続先を検索"), usesRaisedBackground: true)
            .navigationTitle(L10n.text("モデルを選択"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("閉じる")) { dismiss() }
                        .foregroundStyle(appAccent.color)
                }
            }
        }
    }

    private var groupedProviders: [(provider: String, displayName: String, presets: [ModelPreset])] {
        let grouped = Dictionary(grouping: presets) { $0.apiProvider.uppercased() }
        return grouped.map { provider, values in
            (provider, ProviderCatalog.displayName(for: provider), values)
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func isActive(_ preset: ModelPreset) -> Bool {
        preset.apiProvider.caseInsensitiveCompare(viewModel.conversationProvider) == .orderedSame &&
            preset.model == viewModel.conversationModel
    }
}

struct ChatModePickerSheet: View {
    @Environment(\.appAccent) private var appAccent
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    private var activeMode: ChatMode { ChatMode(settings: viewModel.settings) }

    var body: some View {
        NavigationStack {
            AMOLEDList(usesRaisedBackground: true) {
                Section {
                    ForEach(ChatMode.allCases) { mode in
                        Button {
                            viewModel.setChatMode(mode)
                            dismiss()
                        } label: {
                            HStack(spacing: 13) {
                                Image(systemName: mode.systemImage)
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundStyle(appAccent.color)
                                    .frame(width: 40, height: 40)
                                    .background(appAccent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(mode.title)
                                        .font(.body.weight(.semibold))
                                    Group {
                                        switch mode {
                                        case .standard: Text("1つのモデルと会話")
                                        case .dual: Text("2つのモデルの回答を比較")
                                        case .autoConversation: Text("2つのモデルが交互に会話")
                                        }
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
                                }
                                Spacer()
                                if mode == activeMode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(appAccent.color)
                                }
                            }
                            .foregroundStyle(.primary)
                            .contentShape(Rectangle())
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .contentMargins(.top, 8, for: .scrollContent)
            .navigationTitle(L10n.text("会話モード"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("閉じる")) { dismiss() }
                        .foregroundStyle(appAccent.color)
                }
            }
        }
    }
}
