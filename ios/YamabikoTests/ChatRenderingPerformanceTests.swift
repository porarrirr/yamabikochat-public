import Darwin
import os.signpost
import UIKit
import SwiftUI
import XCTest
@testable import YamabikoChat

/// Real hosting cells, layout, text selection and display commits, without network variance.
/// Opt in through the xctestrun environment: YAMABIKO_RENDER_BENCHMARK=1.
final class ChatRenderingPerformanceTests: XCTestCase {
    @MainActor
    func testGeneratedFileLinksRenderInResponse() async throws {
        let file = URL(fileURLWithPath: "/support/YamabikoChat/GeneratedFiles/Workspace 1/outputs/csv-analysis/SKILL.md")
        let source = "## 生成ファイル\n\n- `outputs/csv-analysis/SKILL.md` — スキル本体\n- [スキルを開く](outputs/csv-analysis/SKILL.md)\n\n作成したファイルをタップして確認できます。"
        let view = NativeMarkdownView(markdownText: source, isStreaming: true,
            preparsedBlocks: NativeMarkdownParser.parse(source))
            .environment(\.chatFileURLs, [file])
        let host = UIHostingController(rootView: view)
        host.safeAreaRegions = []
        let size = host.sizeThatFits(in: CGSize(width: 366, height: 2_000))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(100))
        host.view.layoutIfNeeded()
        func textViews(in view: UIView) -> [UITextView] {
            (view as? UITextView).map { [$0] } ?? view.subviews.flatMap { textViews(in: $0) }
        }
        let views = textViews(in: host.view)
        XCTAssertFalse(views.isEmpty)
        var destinations: [URL] = []
        for view in views {
            view.attributedText.enumerateAttribute(.link, in: NSRange(location: 0, length: view.attributedText.length)) { value, _, _ in
                if let url = value as? URL { destinations.append(url) }
            }
        }
        XCTAssertEqual(destinations, [file, file])
    }

    @MainActor
    func testCompactActivityAndGeneratedFilesFitPhoneWidth() throws {
        let steps = (1...5).map { index in
            ToolActivityStep(id: "step-\(index)", round: index, toolName: "python_execute",
                title: "Python", detail: "", status: .completed, sources: [], createdAtMs: 0)
        }
        let paths = ["/tmp/analyze_csv.py", "/tmp/SKILL.md", "/tmp/sample.csv"]
        let attachments = String(decoding: try JSONEncoder().encode(paths), as: UTF8.self)
        let message = FullChatMessage(id: 1,
            message: ChatMessage(id: 1, conversationId: 1, role: "model", text: "", attachmentsJSON: attachments),
            thinkingStream: "Considering the CSV skill", variants: [])
        let snapshot = ChatStreamingSnapshot(targetId: 1, text: "", thinking: "Considering the CSV skill",
            toolActivity: ToolActivityPayload(steps: steps), isFinal: false)
        let row = ChatMessageRow(message: message, streamingSnapshot: snapshot, streamingMarkdownBlocks: nil,
            canRegenerate: false, onRoute: { _ in }, onPreviousVariant: { _ in }, onNextVariant: { _ in },
            onBranch: { _ in }, onRegenerate: {}, onEditUserMessage: { _ in },
            onSelectUserMessageText: { _ in }, onMarkdownLayoutChange: {})
        let host = UIHostingController(rootView: row.environment(\.locale, Locale(identifier: "ja_JP")))
        host.safeAreaRegions = []
        let size = host.sizeThatFits(in: CGSize(width: 366, height: 1_000))
        // Files are a single footer control even when multiple files exist.
        XCTAssertLessThanOrEqual(size.height, 100)
        XCTAssertLessThanOrEqual(size.width, 366)
    }

    @MainActor
    func testGeneratedFilesFooterHeightDoesNotGrowWithFileCount() throws {
        let source = "CSV分析スキルを作成しました。ファイルは回答の下から開けます。"
        func host(fileCount: Int) throws -> UIHostingController<ChatMessageRow> {
            let paths = (0..<fileCount).map { "/tmp/generated-file-\($0).csv" }
            let json = String(decoding: try JSONEncoder().encode(paths), as: UTF8.self)
            let message = FullChatMessage(id: 1,
                message: ChatMessage(id: 1, conversationId: 1, role: "model", text: source, attachmentsJSON: json),
                thinkingStream: nil, variants: [])
            return UIHostingController(rootView: ChatMessageRow(
                message: message, streamingSnapshot: nil, streamingMarkdownBlocks: NativeMarkdownParser.parse(source),
                canRegenerate: true, onRoute: { _ in }, onPreviousVariant: { _ in }, onNextVariant: { _ in },
                onBranch: { _ in }, onRegenerate: {}, onEditUserMessage: { _ in },
                onSelectUserMessageText: { _ in }, onMarkdownLayoutChange: {}))
        }
        let single = try host(fileCount: 1)
        let many = try host(fileCount: 40)
        let proposal = CGSize(width: 366, height: 2_000)
        XCTAssertEqual(single.sizeThatFits(in: proposal).height, many.sizeThatFits(in: proposal).height, accuracy: 1)
    }

    @MainActor
    func testGeneratedFilesWrapAndConstrainLongNames() {
        let files = ["analyze_csv.py", "SKILL.md", "sample.csv"].map {
            ChatAttachmentItem(rawValue: "/tmp/" + $0)
        }
        let compact = UIHostingController(rootView: MessageAttachmentList(attachments: files, isOutgoing: false))
        let wide = compact.sizeThatFits(in: CGSize(width: 760, height: 1_000))
        let narrow = compact.sizeThatFits(in: CGSize(width: 200, height: 1_000))
        XCTAssertEqual(wide.height, 44, accuracy: 1)
        XCTAssertGreaterThan(narrow.height, wide.height)
        XCTAssertLessThanOrEqual(narrow.width, 200)

        let longName = ChatAttachmentItem(rawValue: "/tmp/" + String(repeating: "long_filename_", count: 20) + ".csv")
        let accessible = UIHostingController(rootView:
            MessageAttachmentList(attachments: files + [longName], isOutgoing: false)
                .environment(\.dynamicTypeSize, .accessibility3))
        let size = accessible.sizeThatFits(in: CGSize(width: 280, height: 2_000))
        XCTAssertLessThanOrEqual(size.width, 280)
        XCTAssertGreaterThan(size.height, narrow.height)
    }

    @MainActor
    func testRenderingWorkloads() async throws {
        guard ProcessInfo.processInfo.environment["YAMABIKO_RENDER_BENCHMARK"] == "1" else {
            throw XCTSkip("Explicit rendering benchmark only")
        }
        let log = OSLog(subsystem: "org.example.yamabikochat.performance", category: .pointsOfInterest)
        let prose = (1...24).map {
            "## 手順\($0)\n\n日本語の **説明** と [出典](https://example.com/\($0))。計算結果を確認してから次に進みます。\n\n"
        }.joined() + "```swift\nlet values = [12, 18, 30]\nprint(values.reduce(0, +))\n```\n\n最終回答は **60** です。"
        let list = (1...100).map {
            "\($0). 日本語の **手順\($0)** と `code`。[資料](https://example.com/\($0))を確認します。\n"
        }.joined() + "\n最終回答は **60** です。"
        for sample in 0..<3 {
            for workload in ["prose", "list", "thinking", "scroll", "idle"] {
                let store = ChatTimelineStore()
                let source = workload == "list" ? list : prose
                var messages = (1...100).map { index in
                    message(id: Int64(index), text: "## 履歴\(index)\n\n" + String(repeating: "日本語の **回答** と [資料](https://example.com)。\n\n", count: index % 4 + 1))
                }
                messages.append(message(id: 101, text: workload == "thinking" || workload == "scroll" || workload == "idle" ? source : ""))
                store.update(messages: messages)
                let controller = ChatTimelineViewController()
                controller.loadViewIfNeeded()
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.configure(store: store, scrollToLatestRequest: 1, regeneratableMessageID: nil,
                    dualSplitLayout: "VERTICAL", dualSplitRatio: 0.5,
                    onRoute: { _ in }, onPreviousVariant: { _ in },
                    onNextVariant: { _ in }, onBranch: { _ in }, onRegenerate: {}, onAskChatWithSelection: { _ in },
                    onEditUserMessage: { _ in }, onSelectUserMessageText: { _ in })
                controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(750))
                let collection = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UICollectionView }.first)
                let characters = Array(source)
                let frames = (1...120).map { String(characters.prefix((characters.count * $0 + 119) / 120)) }
                if workload == "scroll" { controller.scrollViewWillBeginDragging(collection) }
                let signpostID = OSSignpostID(log: log)
                os_signpost(.begin, log: log, name: "RenderingWorkload", signpostID: signpostID, "%{public}@", workload as NSString)
                let cpuStart = cpuSeconds()
                let start = ContinuousClock.now
                for frame in 0..<120 {
                    if workload == "prose" || workload == "list" || workload == "thinking" {
                        store.applyStreamingSnapshot(ChatStreamingSnapshot(targetId: 101,
                            text: workload == "thinking" ? source : frames[frame],
                            thinking: workload == "thinking" ? String(repeating: "検討中。", count: frame + 1) : "",
                            isFinal: false))
                    } else if workload == "scroll" {
                        let fraction = CGFloat(frame % 60) / 59
                        let progress = frame < 60 ? 1 - fraction : fraction
                        collection.setContentOffset(CGPoint(x: 0, y: max(0, collection.contentSize.height - collection.bounds.height) * progress), animated: false)
                        controller.scrollViewDidScroll(collection)
                    }
                    controller.view.layoutIfNeeded()
                    // Absolute pacing: every input is applied, without dropping slow frames.
                    try await Task.sleep(until: start + .nanoseconds(Int64(frame + 1) * 33_333_333), clock: .continuous)
                }
                if workload == "scroll" { controller.scrollViewDidEndDragging(collection, willDecelerate: false) }
                if workload == "prose" || workload == "list" || workload == "thinking" {
                    store.applyStreamingSnapshot(ChatStreamingSnapshot(targetId: 101, text: source, thinking: "", isFinal: true))
                }
                // Include the final Markdown parse and pending display/layout commits.
                try await Task.sleep(for: .milliseconds(250))
                controller.view.layoutIfNeeded()
                let cpu = cpuSeconds() - cpuStart
                let elapsed = start.duration(to: .now).components
                os_signpost(.end, log: log, name: "RenderingWorkload", signpostID: signpostID)
                let cells = collection.visibleCells.compactMap { $0 as? ChatTimelineCollectionCell }
                let measurements = cells.reduce(0) { $0 + $1.contentHeightMeasurementCount }
                let result: [String: Any] = ["workload": workload, "sample": sample, "cpu_seconds": cpu,
                    "wall_seconds": Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
                    "visible_cell_measurements": measurements, "content_height": collection.contentSize.height,
                    "response_height": collection.layoutAttributesForItem(at: IndexPath(item: 100, section: 0))?.frame.height ?? 0]
                let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
                print("RENDER_BENCHMARK " + String(decoding: data, as: UTF8.self))
                XCTAssertFalse(collection.visibleCells.isEmpty)
                let attributes = collection.indexPathsForVisibleItems.sorted().compactMap { collection.layoutAttributesForItem(at: $0) }
                for (a, b) in zip(attributes, attributes.dropFirst()) { XCTAssertLessThanOrEqual(a.frame.maxY, b.frame.minY) }
                if workload == "prose" || workload == "list" || workload == "thinking" {
                    let row = try XCTUnwrap(store.row(id: "m-101"))
                    if case let .message(message) = row.item {
                        XCTAssertEqual(row.streamingSnapshot?.text ?? message.displayText, source)
                    } else {
                        XCTFail("Expected the response row")
                    }
                }
                window.isHidden = true
                window.rootViewController = nil
            }
        }
    }

    private func message(id: Int64, text: String) -> FullChatMessage {
        FullChatMessage(id: id, message: ChatMessage(id: id, conversationId: 1, role: "model", text: text, createdAtMs: id), thinkingStream: nil, variants: [])
    }

    private func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    }
}
