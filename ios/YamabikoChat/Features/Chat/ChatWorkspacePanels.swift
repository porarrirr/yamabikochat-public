import SwiftUI
import UIKit

struct ChatEmptyState: View {
    @Environment(\.appAccent) private var appAccent
    let title: String
    let systemImage: String
    let subtitle: String
    let onSelectStarter: (String) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(appAccent.color)
                .frame(width: 64, height: 64)
                .background(appAccent.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 22))
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                ForEach([
                    ("text.alignleft", "文章を整える", "次の文章を読みやすく整えてください。"),
                    ("lightbulb", "アイデアを広げる", "アイデアを一緒に考えてください。"),
                    ("chevron.left.forwardslash.chevron.right", "コードを相談", "次のコードについて相談したいです。")
                ], id: \.1) { symbol, title, prompt in
                    Button {
                        onSelectStarter(L10n.text(prompt) + "\n\n")
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: symbol)
                                .foregroundStyle(appAccent.color)
                                .frame(width: 22)
                            Text(L10n.text(title))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "plus")
                                .font(.caption)
                                .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .background(Color(uiColor: .amoledSecondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chat-starter-\(symbol)")
                }
            }
            .padding(.top, 12)
        }
        .padding(32)
        .frame(maxWidth: 420)
    }
}

struct ChatWorkspaceRouteSheet: View {
    let route: ChatWorkspaceRoute
    var timelineStore: ChatTimelineStore? = nil

    var body: some View {
        switch route {
        case let .runInspector(messageID, steps, side):
            if let row = timelineStore?.row(id: "\(side == nil ? "m" : "d")-\(messageID)") {
                ChatLiveInspector(row: row, side: side, showsThinking: false)
            } else {
                ChatRunInspector(steps: steps)
            }
        case let .thinkingInspector(messageID, text, side):
            if let row = timelineStore?.row(id: "\(side == nil ? "m" : "d")-\(messageID)") {
                ChatLiveInspector(row: row, side: side, showsThinking: true)
            } else {
                ChatThinkingInspector(text: text)
            }
        case let .artifactViewer(_, block):
            ChatArtifactViewer(block: block)
        case let .mermaidViewer(_, source):
            MermaidDiagramViewer(source: source)
        case let .genUIMap(configuration):
            GenUIMapView(configuration: configuration)
        case let .genUIEntity(detail):
            GenUIEntityDetailView(detail: detail)
        case .modelPicker, .modePicker:
            EmptyView()
        }
    }
}

// Observe the same row as the timeline. A sheet's route is only the selection;
// its captured payload must not freeze a running tool or thinking transcript.
struct ChatLiveInspector: View {
    @ObservedObject var row: ChatTimelineRowStore
    let side: DualResponseSide?
    let showsThinking: Bool

    var body: some View {
        if showsThinking {
            ChatThinkingInspector(text: row.inspectorThinking(side: side))
        } else {
            ChatRunInspector(steps: row.inspectorSteps(side: side))
        }
    }
}

private struct MermaidDiagramViewer: View {
    let source: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MermaidDiagramView(source: source, expanded: true)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Mermaid")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            UIPasteboard.general.string = source
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .accessibilityLabel(Text(L10n.text("コピー")))

                        Button(L10n.text("閉じる")) { dismiss() }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct ChatRunInspector: View {
    let steps: [ToolActivityStep]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AMOLEDList {
                ForEach(steps) { step in
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                statusIcon(step.status)
                                Text(step.title)
                                    .font(.headline)
                                Spacer()
                                if let duration = step.durationMs {
                                    Text(String(format: "%.1fs", Double(duration) / 1_000))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let detail = step.detail.trimmedNonEmpty {
                                Text(detail)
                                    .font(.subheadline)
                                    .textSelection(.enabled)
                            }
                            if let preview = step.resultPreview?.trimmedNonEmpty ?? step.outputPreview?.trimmedNonEmpty {
                                Text(preview)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(uiColor: .amoledSecondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                            }
                            if let error = step.errorMessage?.trimmedNonEmpty {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            }

                            ForEach(step.sources) { source in
                                if let url = URL(string: source.url) {
                                    Link(destination: url) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "link")
                                            Text(source.title.trimmedNonEmpty ?? source.url)
                                                .lineLimit(2)
                                            Spacer()
                                            Image(systemName: "arrow.up.right")
                                                .font(.caption)
                                        }
                                        .font(.subheadline)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text(step.isWebActivity ? L10n.text("Web検索") : step.toolName)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.text("実行の詳細"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("閉じる")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func statusIcon(_ status: ToolActivityStep.Status) -> some View {
        switch status {
        case .running:
            ProgressView().controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        }
    }
}

private struct ChatThinkingInspector: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ThinkingStreamTextView(text: text)
                .padding(16)
                .navigationTitle(L10n.text("Thinking"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.text("閉じる")) { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct ChatArtifactViewer: View {
    let block: ChatArtifactBlock
    @Environment(\.dismiss) private var dismiss
    @State private var htmlTitle = ""

    var body: some View {
        NavigationStack {
            Group {
                switch block {
                case let .html(content):
                    HtmlPreviewWebView(html: content, pageTitle: $htmlTitle)
                case let .svg(content):
                    SvgDiagramView(source: content, expanded: true)
                }
            }
            .navigationTitle(block.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if case let .svg(content) = block {
                        Button {
                            UIPasteboard.general.string = content
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .accessibilityLabel(Text(L10n.text("コピー")))
                    }

                    Button(L10n.text("閉じる")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
