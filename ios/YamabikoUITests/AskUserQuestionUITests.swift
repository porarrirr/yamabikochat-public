import XCTest

final class AskUserQuestionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFreeTextQuestionFitsContentAndCanBeAnsweredWithKeyboardVisible() {
        let app = launch()
        let question = app.staticTexts["ask-user-question-text"]
        let field = app.textFields["ask-user-question-custom-answer"]
        let submit = app.buttons["ask-user-question-submit"]
        XCTAssertTrue(question.waitForExistence(timeout: 10))
        XCTAssertEqual(question.label, "あなたが一番尊敬するのは誰ですか？")
        XCTAssertLessThan(field.frame.minY - question.frame.maxY, 60)
        XCTAssertLessThan(submit.frame.maxY - question.frame.minY, 220)
        XCTAssertFalse(submit.isEnabled)
        capture("question-free-text")

        field.tap()
        field.typeText("福沢諭吉")
        XCTAssertTrue(submit.isEnabled)
        XCTAssertTrue(submit.isHittable)
        capture("question-keyboard")
        submit.tap()
        XCTAssertTrue(question.waitForNonExistence(timeout: 5))
    }

    func testDiagnosticFragmentDoesNotExpandIntoEmptyPanels() {
        let app = launch("-QuestionFragmentFixture")
        let question = app.staticTexts["ask-user-question-text"]
        let field = app.textFields["ask-user-question-custom-answer"]
        let submit = app.buttons["ask-user-question-submit"]
        XCTAssertTrue(question.waitForExistence(timeout: 10))
        XCTAssertEqual(question.label, "質")
        XCTAssertLessThan(field.frame.minY - question.frame.maxY, 60)
        XCTAssertLessThan(submit.frame.maxY - question.frame.minY, 200)
        capture("question-diagnostic-fragment")
        app.buttons["質問をキャンセル"].tap()
        XCTAssertTrue(question.waitForNonExistence(timeout: 5))
    }

    func testPagingResizesForOptionsAndPreservesDrafts() {
        let app = launch("-QuestionChoicesFixture")
        let question = app.staticTexts["ask-user-question-text"]
        let field = app.textFields["ask-user-question-custom-answer"]
        XCTAssertTrue(question.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("福沢諭吉")
        app.buttons["ask-user-question-submit"].tap()
        let option = app.buttons["考え方"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        XCTAssertTrue(option.isHittable)
        option.tap()
        app.buttons["行動力"].tap()
        capture("question-multiple-choice")

        app.buttons["前の質問"].tap()
        XCTAssertEqual(field.value as? String, "福沢諭吉")
        app.buttons["次の質問"].tap()
        XCTAssertEqual(option.value as? String, "選択済み")
        app.buttons["ask-user-question-submit"].tap()
        XCTAssertTrue(question.waitForNonExistence(timeout: 5))
    }

    func testLongQuestionAndOptionsScrollWhileActionsRemainVisible() {
        let app = launch("-QuestionLongFixture")
        let question = app.staticTexts["ask-user-question-text"]
        XCTAssertTrue(question.waitForExistence(timeout: 10))
        let submit = app.buttons["ask-user-question-submit"]
        XCTAssertTrue(submit.isHittable)
        let lastOption = app.buttons["選択肢12"]
        let scroll = app.scrollViews.containing(.staticText, identifier: "ask-user-question-text").firstMatch
        for _ in 0..<12 {
            if lastOption.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(lastOption.isHittable)
        lastOption.tap()
        XCTAssertTrue(submit.isHittable)
        XCTAssertTrue(submit.isEnabled)
        capture("question-long-content")
        submit.tap()
        XCTAssertTrue(question.waitForNonExistence(timeout: 5))
    }

    private func launch(_ fixture: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppStoreScreenshotDemo", "-AskUserQuestionFixture", "-ScreenshotScene", "chat",
            "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"
        ]
        if let fixture { app.launchArguments.append(fixture) }
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
