import XCTest
import UIKit
import SwiftUI
@testable import YamabikoChat

@MainActor
final class ScrollablePlainTextViewTests: XCTestCase {
    func testLargeLogUsesScrollableViewportWithoutMeasuringEntireDocument() {
        let view = ScrollablePlainTextView.makeTextView(textStyle: .caption1, inset: 16, lineSpacing: 0)
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 600)
        let text = String(repeating: "runtime 日本語 https://example.com/" + String(repeating: "x", count: 1000) + "\n", count: 2000)
        view.text = text
        view.layoutIfNeeded()

        XCTAssertEqual(view.text, text)
        XCTAssertEqual(view.bounds.height, 600)
        XCTAssertTrue(view.isScrollEnabled)
        XCTAssertTrue(view.isSelectable)
        XCTAssertFalse(view.isEditable)
        XCTAssertNil(view.textLayoutManager)
        XCTAssertTrue(view.layoutManager.allowsNonContiguousLayout)
        let paragraph = view.textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(paragraph?.hyphenationFactor ?? 0, 0)
    }

    func testChatSelectionRetainsLongUnbrokenMessageAndDisablesHyphenation() {
        let view = ScrollablePlainTextView.makeTextView()
        let text = String(repeating: "longword", count: 10000) + " 日本語 👨‍👩‍👧‍👦 e\u{301}"
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 300)
        view.text = text
        view.layoutIfNeeded()

        XCTAssertEqual(view.text, text)
        XCTAssertEqual(view.font, .preferredFont(forTextStyle: .body))
        XCTAssertEqual(view.textContainerInset.left, 20)
        let paragraph = view.textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertNotNil(paragraph)
        XCTAssertEqual(paragraph?.hyphenationFactor, 0)
        XCTAssertEqual(paragraph?.lineBreakStrategy, [])
        XCTAssertEqual(paragraph?.lineSpacing, 2)
    }

    func testSwiftUIReaderFillsViewportForMultiMegabyteDocument() throws {
        let text = String(repeating: "日本語 longword https://example.com/\n", count: 100000)
        let host = UIHostingController(rootView: ScrollablePlainTextView(text: text))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        func findReader(_ view: UIView) -> UITextView? {
            if let reader = view as? UITextView { return reader }
            return view.subviews.lazy.compactMap { findReader($0) }.first
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let reader = try XCTUnwrap(findReader(host.view))
        XCTAssertTrue(reader.text == text)
        XCTAssertGreaterThan(reader.bounds.width, 0)
        XCTAssertGreaterThan(reader.bounds.height, 0)
        XCTAssertLessThanOrEqual(reader.bounds.height, 600)
    }

    func testThinkingAppendPreservesSelectionAndReadingPosition() async {
        let (view, coordinator) = makeThinkingReader()
        let text = String(repeating: "Thinking 日本語 👨‍👩‍👧‍👦 e\u{301}\n", count: 200)
        coordinator.update(text, in: view)
        await drainThinkingUpdates()
        coordinator.scrollViewWillBeginDragging(view)
        view.setContentOffset(CGPoint(x: 0, y: 160), animated: false)
        coordinator.scrollViewDidEndDragging(view, willDecelerate: false)
        view.selectedRange = NSRange(location: 10, length: 3)
        let offset = view.contentOffset

        for index in 0..<20 {
            coordinator.update(text + String(repeating: "追記 👋🏽\n", count: index + 1), in: view)
            await drainThinkingUpdates()
        }

        XCTAssertEqual(view.text, text + String(repeating: "追記 👋🏽\n", count: 20))
        XCTAssertEqual(view.selectedRange, NSRange(location: 10, length: 3))
        XCTAssertEqual(view.contentOffset.y, offset.y, accuracy: 1)
        XCTAssertFalse(coordinator.isFollowing)
    }

    func testThinkingDragCancelsQueuedFollowAndWaitsForDeceleration() async {
        let (view, coordinator) = makeThinkingReader()
        let text = String(repeating: "thinking line\n", count: 200)
        coordinator.update(text, in: view)
        // Begin dragging before the initial queued auto-scroll executes.
        coordinator.scrollViewWillBeginDragging(view)
        view.setContentOffset(CGPoint(x: 0, y: 80), animated: false)
        coordinator.scrollViewDidEndDragging(view, willDecelerate: true)
        coordinator.update(text + "new thought\n", in: view)
        await drainThinkingUpdates()

        XCTAssertEqual(view.contentOffset.y, 80, accuracy: 1)
        XCTAssertFalse(coordinator.isFollowing)
        coordinator.scrollViewDidEndDecelerating(view)
        XCTAssertFalse(coordinator.isFollowing)
    }

    func testThinkingFollowsAgainAfterReaderReturnsToBottom() async {
        let (view, coordinator) = makeThinkingReader()
        let text = String(repeating: "thinking line\n", count: 200)
        coordinator.update(text, in: view)
        await drainThinkingUpdates()
        XCTAssertEqual(view.contentOffset.y, view.contentSize.height - view.bounds.height, accuracy: 1)

        coordinator.scrollViewWillBeginDragging(view)
        // Even near the bottom, a stream delta must not move a held gesture.
        view.setContentOffset(CGPoint(x: 0, y: view.contentOffset.y - 20), animated: false)
        let heldOffset = view.contentOffset.y
        coordinator.update(text + "next\n", in: view)
        await drainThinkingUpdates()
        XCTAssertEqual(view.contentOffset.y, heldOffset, accuracy: 1)
        view.setContentOffset(CGPoint(x: 0, y: view.contentSize.height - view.bounds.height), animated: false)
        coordinator.scrollViewDidEndDragging(view, willDecelerate: true)
        coordinator.scrollViewDidEndDecelerating(view)
        coordinator.update(text + "next\nmore\n", in: view)
        await drainThinkingUpdates()

        XCTAssertTrue(coordinator.isFollowing)
        XCTAssertEqual(view.contentOffset.y, view.contentSize.height - view.bounds.height, accuracy: 1)
    }

    func testThinkingHandlesReplacementAndUnicodeAppend() async {
        let (view, coordinator) = makeThinkingReader()
        coordinator.update("日本語 👨‍👩‍👧‍👦 e", in: view)
        coordinator.update("日本語 👨‍👩‍👧‍👦 e\u{301} 思考", in: view)
        XCTAssertEqual(view.text, "日本語 👨‍👩‍👧‍👦 e\u{301} 思考")
        coordinator.update("新しい内容", in: view)
        await drainThinkingUpdates()
        XCTAssertEqual(view.text, "新しい内容")
    }

    private func makeThinkingReader() -> (UITextView, ThinkingTextViewRepresentable.Coordinator) {
        let view = UITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        view.font = .preferredFont(forTextStyle: .body)
        view.isEditable = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        let coordinator = ThinkingTextViewRepresentable.Coordinator()
        view.delegate = coordinator
        return (view, coordinator)
    }

    private func drainThinkingUpdates() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

}
