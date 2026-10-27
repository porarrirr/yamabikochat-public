import XCTest
@testable import YamabikoChat

final class GenerationPresentationTests: XCTestCase {
    @MainActor
    func testStreamingAnswerPreservesGeneratedCodeAndCompletedTools() throws {
        // Already-coalesced native events, at the production 10 Hz preview rate.
        // Text, thinking, Python/Web status and growing GenUI code share one row.
        let answer = (1...12).map { "## 結果\($0)\n\n日本語の **説明** と [資料](https://example.com)。\n\n" }.joined()
        let code = "const values = [12, 18, 30];\nreturn DIL.h('col', {}, [" +
            (1...24).map { "DIL.h('text', {}, '項目\($0)：合計60')" }.joined(separator: ",\n") + "]);"
        let textCharacters = Array(answer), codeCharacters = Array(code)
        let frames = try (1...180).map { index -> (String, ToolActivityEvent?) in
            let text = String(textCharacters.prefix((textCharacters.count * index + 179) / 180))
            guard index.isMultiple(of: 3) || index == 1 else { return (text, nil) }
            let partial = String(codeCharacters.prefix((codeCharacters.count * index + 179) / 180))
            let data = try JSONSerialization.data(withJSONObject: ["title": "計算結果", "code": partial])
            return (text, ToolActivityEvent(phase: .generating,
                call: ToolCall(id: "genui", name: GenUITool.name, argumentsJSON: String(decoding: data, as: UTF8.self)),
                createdAtMs: Int64(index * 33)))
        }
        let statuses = [
            ToolActivityEvent(phase: .finished, call: ToolCall(id: "python", name: PythonExecuteTool.name,
                argumentsJSON: #"{"code":"sum([12,18,30])"}"#),
                result: ToolResult(callId: "python", name: PythonExecuteTool.name,
                    content: #"{"status":"ok","result_repr":"60","duration_ms":12}"#), createdAtMs: 0),
            ToolActivityEvent(phase: .finished, call: ToolCall(id: "web", name: FetchUrlTool.name,
                argumentsJSON: #"{"url":"https://example.com","goal":"資料"}"#),
                result: ToolResult(callId: "web", name: FetchUrlTool.name,
                    content: #"{"results":[{"text":"Example Domain"}]}"#), createdAtMs: 1)
        ]
        let row = ChatTimelineRowStore(item: .message(FullChatMessage(id: 1,
            message: ChatMessage(id: 1, conversationId: 1, role: "model", text: ""), thinkingStream: nil, variants: [])))
        var activity = ToolActivityPayload()
        for status in statuses { activity.apply(status) }
        for frame in frames {
            if let event = frame.1 { activity.apply(event) }
            row.apply(snapshot: ChatStreamingSnapshot(targetId: 1, text: frame.0,
                thinking: "計算と出典を確認しています。", toolActivity: activity, isFinal: false))
        }
        XCTAssertEqual(row.streamingSnapshot?.text, answer)
        XCTAssertEqual(row.streamingMarkdownBlocks, NativeMarkdownParser.parse(answer, rendersMath: false))
        XCTAssertEqual(row.streamingSnapshot?.toolActivity?.steps.last?.genUIDocument?.code, code)
        XCTAssertEqual(row.streamingSnapshot?.toolActivity?.steps.prefix(2).map(\.status), [.completed, .completed])
    }

    @MainActor
    func testCachedAnswerRefreshesForCompletionReplacementAndNextStream() {
        let row = ChatTimelineRowStore(item: .message(FullChatMessage(
            id: 1, message: ChatMessage(id: 1, conversationId: 1, role: "model", text: ""),
            thinkingStream: nil, variants: [])))
        let answer = "本文\n\n```html\n<div>preview</div>\n```"
        row.apply(snapshot: ChatStreamingSnapshot(targetId: 1, text: answer, thinking: "", isFinal: false))
        let streaming = row.streamingMarkdownBlocks
        row.apply(snapshot: ChatStreamingSnapshot(targetId: 1, text: answer, thinking: "思考", isFinal: false))
        XCTAssertEqual(row.streamingMarkdownBlocks, streaming)
        row.apply(snapshot: ChatStreamingSnapshot(targetId: 1, text: answer, thinking: "思考", isFinal: true))
        XCTAssertEqual(row.streamingMarkdownBlocks?.count, 1, "Completed HTML fences move into the artifact card")
        row.apply(snapshot: ChatStreamingSnapshot(targetId: 1, text: "# 新しい回答", thinking: "", isFinal: false))
        XCTAssertEqual(row.streamingMarkdownBlocks, NativeMarkdownParser.parse("# 新しい回答", rendersMath: false))
        row.apply(snapshot: nil)
        row.apply(snapshot: ChatStreamingSnapshot(targetId: 1, text: answer, thinking: "", isFinal: false))
        XCTAssertEqual(row.streamingMarkdownBlocks, streaming)
    }

    func testEntityDecodingPreservesUnicodeAndUnknownEntities() {
        XCTAssertEqual(HTMLTextExtractor.decodeEntities("👨‍👩‍👧‍👦 e\u{301} &AMP; &#x6771;&#20140; &#128512; &unknown; &#x110000;"),
                       "👨‍👩‍👧‍👦 e\u{301} & 東京 😀 &unknown; &#x110000;")
        XCTAssertEqual(HTMLTextExtractor.decodeEntities("&amp;#65; &quot;引用&quot; &nbsp;&apos;"), "A \"引用\"  '")
    }
}
