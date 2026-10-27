import SwiftUI

private struct PinnedListSearchField: View {
    @Binding var text: String
    let prompt: String
    var usesRaisedBackground = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
                .accessibilityHidden(true)
            TextField(prompt, text: $text, prompt: Text(prompt).foregroundStyle(Color(uiColor: .amoledPlaceholderText)))
                .font(.subheadline)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)
                .onSubmit { isFocused = false }
                .accessibilityLabel(Text(prompt))
                .accessibilityIdentifier("picker-search-field")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(L10n.text("クリア")))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, text.isEmpty ? 14 : 0)
        .frame(minHeight: 44)
        .background(Color(uiColor: usesRaisedBackground ? .amoledSecondarySystemFill : .amoledTertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(uiColor: usesRaisedBackground ? .amoledSecondarySystemBackground : .amoledSystemGroupedBackground))
    }
}

extension View {
    /// Keep picker search directly above the results, including while scrolling.
    func pinnedListSearch(text: Binding<String>, prompt: String, usesRaisedBackground: Bool = false) -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) {
                PinnedListSearchField(text: text, prompt: prompt, usesRaisedBackground: usesRaisedBackground)
            }
    }
}
