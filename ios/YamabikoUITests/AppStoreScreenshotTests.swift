import XCTest

final class AppStoreScreenshotTests: XCTestCase {
    private var reviewOutputDirectory: URL?

    private var outputDirectory: URL {
        if let reviewOutputDirectory { return reviewOutputDirectory }
        let env = ProcessInfo.processInfo.environment["SCREENSHOT_OUTPUT_DIR"] ?? ""
        if env.isEmpty {
            return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("AppStoreScreenshots", isDirectory: true)
        }
        return URL(fileURLWithPath: env, isDirectory: true)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    func testUIPolishScreenSet() throws {
        let directory = outputDirectory.appendingPathComponent("ui-review-\(UUID().uuidString)", isDirectory: true)
        reviewOutputDirectory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print("UI_REVIEW_OUTPUT=\(directory.path)")
        let app = XCUIApplication()
        for appearance in ["light", "dark"] {
            let arguments = ["-AppStoreScreenshotDemo", "-UIPolishFixture", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
                + (appearance == "dark" ? ["-GenUIDarkFixture"] : [])
            app.launchArguments = arguments + ["-ScreenshotScene", "list"]
            app.launch()
            XCTAssertTrue(app.buttons["open-settings"].waitForExistence(timeout: 15))
            capture("\(appearance)-01-conversations", app: app)
            XCTAssertTrue(openSettings(app: app))
            capture("\(appearance)-02-settings", app: app)
            for (index, category, subtitle) in [
                (3, "接続", "API・モデル"), (4, "会話", "プロンプト・モード"),
                (5, "表示", "テーマ・プリセット"), (6, "管理", "使用状況・診断")
            ] {
                XCTAssertTrue(openSettingsCategory(app: app, subtitle: subtitle, title: category))
                sleep(2)
                capture("\(appearance)-0\(index)-\(category)", app: app)
                XCTAssertTrue(returnToSettingsIndex(app: app))
            }
            app.terminate()
            app.launchArguments = arguments + ["-ScreenshotScene", "chat"]
            app.launch()
            XCTAssertTrue(app.buttons["chat-model-button"].waitForExistence(timeout: 15))
            sleep(2)
            capture("\(appearance)-07-chat", app: app)
            app.buttons["chat-model-button"].tap()
            sleep(1)
            capture("\(appearance)-08-model-picker", app: app)
            app.buttons["閉じる"].tap()
            app.buttons["その他"].tap()
            app.buttons["会話モード"].tap()
            XCTAssertTrue(app.navigationBars["会話モード"].waitForExistence(timeout: 5))
            capture("\(appearance)-11-mode-picker", app: app)
            app.terminate()
            app.launchArguments = arguments + ["-ScreenshotScene", "project"]
            app.launch()
            XCTAssertTrue(app.buttons["新しいプロジェクト"].waitForExistence(timeout: 15))
            capture("\(appearance)-09-projects", app: app)
            app.terminate()
            app.launchArguments = arguments + ["-ScreenshotScene", "temporary-chat"]
            app.launch()
            XCTAssertTrue(app.buttons["chat-model-button"].waitForExistence(timeout: 15))
            sleep(1)
            capture("\(appearance)-10-new-chat", app: app)
            app.terminate()
        }
        try Data("complete".utf8).write(to: directory.appendingPathComponent("capture-complete"))
    }

    func testChatStarterFillsComposerAndFocusesKeyboard() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppStoreScreenshotDemo", "-UIPolishFixture", "-ScreenshotScene", "temporary-chat",
            "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"
        ]
        app.launch()

        let starter = app.buttons["chat-starter-text.alignleft"]
        XCTAssertTrue(starter.waitForExistence(timeout: 15))
        capture("chat-starter-ready", app: app)
        starter.tap()

        let composer = app.descendants(matching: .any)["chat-composer"].firstMatch
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "次の文章を読みやすく整えてください。\n\n")
        XCTAssertFalse(starter.exists, "Suggestions must yield to the user's draft")
        composer.typeText("メモ")
        XCTAssertEqual(composer.value as? String, "次の文章を読みやすく整えてください。\n\nメモ")
    }

    func testSettingsThemePickerKeepsNavigationVisible() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppStoreScreenshotDemo", "-UIPolishFixture", "-ScreenshotScene", "list",
            "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"
        ]
        app.launch()
        XCTAssertTrue(openSettings(app: app))
        XCTAssertTrue(openSettingsCategory(app: app, subtitle: "テーマ・プリセット", title: "表示"))
        let dark = app.segmentedControls.buttons["ダーク"]
        XCTAssertTrue(dark.waitForExistence(timeout: 5))
        dark.tap()
        XCTAssertTrue(dark.isSelected)
        XCTAssertTrue(app.navigationBars["表示"].exists)
        app.segmentedControls.buttons["ライト"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["ライト"].isSelected)
        XCTAssertTrue(app.navigationBars["表示"].exists)
        XCTAssertTrue(returnToSettingsIndex(app: app))
    }

    func testUIPolishPopulatedUsage() {
        let app = XCUIApplication()
        for appearance in ["light", "dark"] {
            app.launchArguments = [
                "-AppStoreScreenshotDemo", "-UIPolishFixture", "-UIPolishUsageFixture",
                "-ScreenshotScene", "list", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"
            ] + (appearance == "dark" ? ["-GenUIDarkFixture"] : [])
            app.launch()
            XCTAssertTrue(openSettings(app: app))
            XCTAssertTrue(openSettingsCategory(app: app, subtitle: "使用状況・診断", title: "管理"))
            XCTAssertTrue(app.staticTexts["30"].waitForExistence(timeout: 5))
            capture("\(appearance)-populated-usage", app: app)
            app.terminate()
        }
    }

    func testAMOLEDSurfacesAndLightAppearance() {
        let app = XCUIApplication()
        for appearance in ["dark", "light"] {
            app.launchArguments = [
                "-AppStoreScreenshotDemo", "-ScreenshotScene", "list",
                "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"
            ] + (appearance == "dark" ? ["-GenUIDarkFixture"] : [])
            app.launch()
            XCTAssertTrue(openSettings(app: app))
            capture("amoled-\(appearance)-settings-index", app: app)

            for (subtitle, title) in [
                ("API・モデル", "接続"),
                ("プロンプト・モード", "会話"),
                ("テーマ・プリセット・数式", "表示"),
                ("使用状況・診断", "管理")
            ] {
                XCTAssertTrue(openSettingsCategory(app: app, subtitle: subtitle, title: title))
                capture("amoled-\(appearance)-settings-\(title)", app: app)
                XCTAssertTrue(returnToSettingsIndex(app: app))
            }
            closeSettings(app: app)
            capture("amoled-\(appearance)-conversation-list", app: app)
            app.terminate()
            // Route directly so the capture does not depend on sidebar selection state.
            let sceneIndex = app.launchArguments.firstIndex(of: "-ScreenshotScene")! + 1
            app.launchArguments[sceneIndex] = "chat"
            app.launch()
            XCTAssertTrue(app.buttons["chat-model-button"].waitForExistence(timeout: 10))
            capture("amoled-\(appearance)-chat", app: app)
            app.terminate()
        }
    }

    func testSettingsConnectionNavigationCanBeRepeated() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppStoreScreenshotDemo", "-ScreenshotScene", "list",
            "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        for _ in 0..<2 {
            XCTAssertTrue(openSettings(app: app))
            for _ in 0..<3 {
                XCTAssertTrue(openSettingsCategory(app: app, subtitle: "API・モデル", title: "接続"))
                XCTAssertTrue(app.buttons["provider-picker-field"].waitForExistence(timeout: 5))
                XCTAssertTrue(returnToSettingsIndex(app: app))
            }
            closeSettings(app: app)
        }
    }



    func testSystemPromptEditorAndPresetFlow() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppStoreScreenshotDemo", "-ScreenshotScene", "list",
            "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"
        ]
        app.launch()
        XCTAssertTrue(openSettings(app: app))
        XCTAssertTrue(openSettingsCategory(app: app, subtitle: "プロンプト・モード", title: "会話"))

        let enabled = app.switches["system-prompt-enabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 5))
        if enabled.value as? String == "0" { enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        let editor = app.descendants(matching: .any)["system-prompt-editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        capture("system-prompt-redesign", app: app)

        enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))

        let presets = app.buttons["system-prompt-presets"]
        presets.tap()
        XCTAssertTrue(app.navigationBars["プリセットを選ぶ"].waitForExistence(timeout: 5))
        app.navigationBars["プリセットを選ぶ"].buttons["閉じる"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))

        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.1)).tap()
        editor.typeText(" UI test prompt")
        XCTAssertFalse(app.buttons["完了"].exists)
        capture("system-prompt-editing", app: app)
        let name = app.textFields["system-prompt-preset-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(" UI test preset")
        XCTAssertFalse(app.buttons["完了"].exists)
        XCTAssertFalse(app.buttons["system-prompt-save-preset"].exists)
        capture("system-prompt-after-autosave", app: app)

        if !presets.isHittable { app.swipeDown() }
        presets.tap()
        let preset = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UI test preset")).firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        capture("system-prompt-preset-picker", app: app)
        preset.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))

        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.1)).tap()
        editor.typeText(" unsaved edit")
        XCTAssertFalse(app.buttons["完了"].exists)
        if !presets.isHittable { app.swipeDown() }
        presets.tap()
        preset.tap()
        XCTAssertFalse(app.buttons["置き換える"].exists)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String ?? "").contains("unsaved edit"))
        capture("system-prompt-updated", app: app)

        XCTAssertTrue(returnToSettingsIndex(app: app))
        XCTAssertTrue(openSettingsCategory(app: app, subtitle: "使用状況・診断", title: "管理"))
        XCTAssertTrue(scrollToText(app: app, text: "診断ログ"))
        capture("diagnostics-actions", app: app)
    }

    func testCaptureAppStoreScreenshots() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["YAMABIKO_CAPTURE_SCREENSHOTS"] == "1",
            "App Store capture is opt-in; set YAMABIKO_CAPTURE_SCREENSHOTS=1 in the test scheme environment."
        )
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        sleep(3)

        navigateToConversationList(app: app)
        sleep(1)
        capture("01-conversation-list", app: app)

        openConversation(app: app, title: "Markdown 数式", fallbackTitle: "旅行プラン")
        sleep(4)
        capture("02-chat-markdown", app: app)

        XCTAssertTrue(openSettings(app: app))
        XCTAssertTrue(openSettingsCategory(app: app, subtitle: "API・モデル", title: "接続"))
        capture("03-settings-api", app: app)

        XCTAssertTrue(returnToSettingsIndex(app: app))
        XCTAssertTrue(openSettingsCategory(app: app, subtitle: "テーマ・プリセット・数式", title: "表示"))
        capture("04-settings-appearance", app: app)

        XCTAssertTrue(returnToSettingsIndex(app: app))
        XCTAssertTrue(openSettingsCategory(app: app, subtitle: "プロンプト・モード", title: "会話"))
        XCTAssertTrue(scrollToText(app: app, text: "デュアルモード"))
        capture("05-settings-dual", app: app)

        XCTAssertTrue(scrollToText(app: app, text: "自動会話"))
        capture("08-settings-auto", app: app)

        XCTAssertTrue(returnToSettingsIndex(app: app))
        closeSettings(app: app)

        if UIDevice.current.userInterfaceIdiom == .pad {
            capture("06-ipad-split-view", app: app)
            XCUIDevice.shared.orientation = .landscapeLeft
            sleep(2)
            capture("07-ipad-landscape", app: app)
            XCUIDevice.shared.orientation = .portrait
            sleep(1)
        } else {
            navigateToConversationList(app: app)
            if app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "仕事用")).firstMatch.waitForExistence(timeout: 3) {
                app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "仕事用")).firstMatch.tap()
                sleep(1)
                capture("06-project-conversations", app: app)
            }
        }

    }

    func testProjectSourcesWorkspaceUI() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppStoreScreenshotDemo",
            "-ScreenshotScene", "project"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        let project = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-row-"))
            .firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()

        let sourcesTab = app.buttons["project-tab-sources"]
        XCTAssertTrue(sourcesTab.waitForExistence(timeout: 10))
        sourcesTab.tap()

        let addFiles = app.buttons["project-add-files"]
        XCTAssertTrue(addFiles.waitForExistence(timeout: 5))
        XCTAssertTrue(addFiles.isHittable)
        capture("project-information-sources-empty", app: app)
    }

    func testProviderSelectionChangesProvider() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        XCTAssertTrue(openSettings(app: app))
        let connectionRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "API・モデル")
        ).firstMatch
        XCTAssertTrue(connectionRow.waitForExistence(timeout: 5))
        XCTAssertTrue(connectionRow.isHittable)
        connectionRow.tap()
        XCTAssertTrue(app.navigationBars["接続"].waitForExistence(timeout: 5))

        let providerField = app.buttons["provider-picker-field"].firstMatch
        XCTAssertTrue(providerField.waitForExistence(timeout: 5))
        XCTAssertTrue(providerField.isHittable)
        providerField.tap()

        XCTAssertTrue(app.navigationBars["プロバイダー"].waitForExistence(timeout: 5))
        let geminiRow = app.buttons["provider-row-GEMINI"].firstMatch
        XCTAssertTrue(geminiRow.waitForExistence(timeout: 5))
        XCTAssertTrue(geminiRow.isHittable)
        geminiRow.tap()

        XCTAssertTrue(app.navigationBars["接続"].waitForExistence(timeout: 5))
        let updatedProviderField = app.buttons["provider-picker-field"].firstMatch
        XCTAssertTrue(updatedProviderField.waitForExistence(timeout: 5))
        XCTAssertTrue(updatedProviderField.label.contains("Google Gemini"))
    }

    func testSwipingDownProviderPickerReturnsToConnectionSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        XCTAssertTrue(openSettings(app: app))

        let connectionRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "API・モデル")
        ).firstMatch
        XCTAssertTrue(connectionRow.waitForExistence(timeout: 5))
        connectionRow.tap()
        XCTAssertTrue(app.navigationBars["接続"].waitForExistence(timeout: 5))

        let providerField = app.buttons["provider-picker-field"].firstMatch
        XCTAssertTrue(providerField.waitForExistence(timeout: 5))
        providerField.tap()

        let providerNavigationBar = app.navigationBars["プロバイダー"].firstMatch
        XCTAssertTrue(providerNavigationBar.waitForExistence(timeout: 5))
        providerNavigationBar.swipeDown()

        XCTAssertTrue(app.navigationBars["接続"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons["provider-picker-field"].firstMatch.waitForExistence(timeout: 5),
            "Dismissing the provider picker must keep the parent settings sheet open"
        )
        XCTAssertFalse(providerNavigationBar.exists)
    }

    func testCaptureTemporaryChatIconStates() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppStoreScreenshotDemo",
            "-ScreenshotScene", "temporary-chat"
        ]
        app.launch()

        let button = app.buttons["chat-primary-action-button"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        XCTAssertEqual(button.label, "シークレットチャットに切り替え")
        capture("temporary-chat-icon-inactive", element: button)

        button.tap()
        let selectedButton = app.buttons["chat-primary-action-button"].firstMatch
        XCTAssertTrue(selectedButton.waitForExistence(timeout: 5))
        XCTAssertEqual(selectedButton.label, "通常チャットに戻す")
        capture("temporary-chat-icon-selected", element: selectedButton)
    }

    func testNativeTimelineKeepsTheLastMessageInsideTheViewport() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppStoreScreenshotDemo",
            "-ChatTimelinePerformanceFixture",
            "-ScreenshotScene", "performance"
        ]
        app.launch()

        let timeline = app.collectionViews["chat-timeline"].firstMatch
        let composer = app.descendants(matching: .any)
            .matching(identifier: "chat-composer")
            .firstMatch
        XCTAssertTrue(timeline.waitForExistence(timeout: 20))
        XCTAssertTrue(composer.waitForExistence(timeout: 20))

        let finalMessage = app.textViews
            .matching(identifier: "selectable-chat-text")
            .matching(NSPredicate(format: "value BEGINSWITH %@", "Fixture message 199"))
            .firstMatch
        XCTAssertTrue(finalMessage.waitForExistence(timeout: 20))
        XCTAssertTrue(finalMessage.isHittable)
        XCTAssertLessThanOrEqual(finalMessage.frame.maxY, composer.frame.minY + 1)

        timeline.swipeDown()
        timeline.swipeDown()
        XCTAssertTrue(app.buttons["chat-latest-button"].waitForExistence(timeout: 5))

        composer.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chat-latest-button"].exists)
    }

    func testChatComposerKeepsSoftwareKeyboardVisibleAcrossTypingAndNewline() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppStoreScreenshotDemo",
            "-ScreenshotScene", "chat"
        ]
        app.launch()

        let composer = app.descendants(matching: .any)
            .matching(identifier: "chat-composer")
            .firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 20))

        composer.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))

        composer.typeText("あ")
        XCTAssertTrue(keyboard.exists, "The first edit must not resign the native text view")
        XCTAssertEqual(composer.value as? String, "あ")

        composer.typeText("\nい")
        XCTAssertTrue(keyboard.exists, "A newline must keep the composer focused")
        XCTAssertEqual(composer.value as? String, "あ\nい")
    }

    func testReasoningEffortMeterOnlyAppearsWithKeyboardAndSliderChangesEffort() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppStoreScreenshotDemo",
            "-ReasoningEffortSliderFixture",
            "-ScreenshotScene", "chat"
        ]
        app.launch()

        let composer = app.descendants(matching: .any)
            .matching(identifier: "chat-composer")
            .firstMatch
        let meter = app.buttons["chat-reasoning-effort-button"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 20))
        XCTAssertFalse(meter.exists)

        composer.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertTrue(meter.waitForExistence(timeout: 5))
        XCTAssertEqual(meter.value as? String, "medium")

        meter.tap()
        let slider = app.descendants(matching: .any)
            .matching(identifier: "chat-reasoning-effort-slider")
            .firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        capture("reasoning-effort-slider-medium", app: app)

        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            .press(
                forDuration: 0.1,
                thenDragTo: slider.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)
                )
            )
        let selectedLabel = app.descendants(matching: .any)
            .matching(identifier: "chat-reasoning-effort-value")
            .firstMatch
        XCTAssertTrue(selectedLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(
            selectedLabel.label.contains("ultra"),
            "The slider must expose the exact selected effort label"
        )
        XCTAssertTrue(keyboard.exists, "Adjusting effort must keep the software keyboard visible")
    }

    func testLongPressOnChatTextUsesNativeTextSelection() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppStoreScreenshotDemo",
            "-ChatTextSelectionFixture",
            "-ScreenshotScene", "list"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        openConversation(app: app, title: "Text Selection Fixture", fallbackTitle: "Text Selection Fixture")

        let expectedSelection = """
        First selectable paragraph.
        Second selectable paragraph.
        Third selectable paragraph.
        """
        let selectableText = app.textViews
            .matching(identifier: "selectable-chat-text")
            .matching(NSPredicate(format: "value BEGINSWITH %@", "First selectable paragraph."))
            .firstMatch
        XCTAssertTrue(selectableText.waitForExistence(timeout: 20))
        XCTAssertEqual(
            selectableText.value as? String,
            expectedSelection,
            "All Markdown paragraphs must share one native selectable text view"
        )

        selectableText.press(forDuration: 1)

        XCTAssertTrue(
            app.menuItems["コピー"].firstMatch.waitForExistence(timeout: 5),
            "Long-pressing message text should open the native text-selection menu"
        )
        XCTAssertTrue(app.menuItems["チャットで質問する"].firstMatch.exists)
        XCTAssertTrue(app.menuItems["すべて"].firstMatch.exists)
        XCTAssertFalse(
            app.buttons["ここからブランチ"].firstMatch.exists,
            "The message-wide context menu must not intercept text selection"
        )
    }

    private func navigateToConversationList(app: XCUIApplication) {
        if listIsVisible(app: app) {
            return
        }

        revealSidebarWithEdgeSwipe(app: app)
        if listIsVisible(app: app) {
            return
        }

        for label in ["openai/gpt-4o-mini", "Sidebar", "会話"] {
            let button = app.navigationBars.buttons[label].firstMatch
            if button.waitForExistence(timeout: 1), button.isHittable {
                button.tap()
                sleep(1)
                if listIsVisible(app: app) {
                    return
                }
            }
        }

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.waitForExistence(timeout: 1), backButton.isHittable {
            backButton.tap()
            sleep(1)
        }
    }

    private func listIsVisible(app: XCUIApplication) -> Bool {
        ["旅行プラン", "Markdown 数式", "API 設計レビュー"].contains { title in
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch.exists
        }
    }

    private func revealSidebarWithEdgeSwipe(app: XCUIApplication) {
        let window = app.windows.element(boundBy: 0)
        guard window.exists else { return }
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        start.press(forDuration: 0.15, thenDragTo: end)
        sleep(1)
    }

    private func openConversation(app: XCUIApplication, title: String, fallbackTitle: String) {
        navigateToConversationList(app: app)
        let primary = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        if primary.waitForExistence(timeout: 5) {
            primary.tap()
            return
        }
        let fallback = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", fallbackTitle)).firstMatch
        XCTAssertTrue(fallback.waitForExistence(timeout: 5), "Conversation row was not found")
        fallback.tap()
    }

    @discardableResult
    private func openSettings(app: XCUIApplication) -> Bool {
        navigateToConversationList(app: app)
        let settings = app.buttons["open-settings"].firstMatch
        if settings.waitForExistence(timeout: 5), settings.isHittable {
            settings.tap()
            sleep(1)
            return app.navigationBars["設定"].waitForExistence(timeout: 5)
        }

        let labeled = app.buttons["設定"].firstMatch
        if labeled.waitForExistence(timeout: 3), labeled.isHittable {
            labeled.tap()
            sleep(1)
            return app.navigationBars["設定"].waitForExistence(timeout: 5)
        }
        return false
    }

    private func closeSettings(app: XCUIApplication) {
        let close = app.navigationBars.buttons["閉じる"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 3), "Settings close button was not found")
        XCTAssertTrue(close.isHittable)
        close.tap()
        sleep(1)
    }

    private func openSettingsCategory(app: XCUIApplication, subtitle: String, title: String) -> Bool {
        let row = app.buttons["settings-category-\(title)"].firstMatch
        guard row.waitForExistence(timeout: 5), row.isHittable else { return false }
        row.tap()
        return app.navigationBars[title].waitForExistence(timeout: 5)
    }

    private func returnToSettingsIndex(app: XCUIApplication) -> Bool {
        let back = app.navigationBars.buttons["設定"].firstMatch
        guard back.waitForExistence(timeout: 3), back.isHittable else { return false }
        back.tap()
        return app.navigationBars["設定"].waitForExistence(timeout: 5)
    }

    private func scrollToText(app: XCUIApplication, text: String) -> Bool {
        let target = app.staticTexts[text].firstMatch
        for _ in 0..<8 {
            if target.exists, target.isHittable { return true }
            app.swipeUp()
        }
        return target.exists
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let url = outputDirectory.appendingPathComponent("\(name).png")
        let image = screenshot.image
        guard let data = image.pngData() else {
            XCTFail("Could not encode screenshot \(name)")
            return
        }
        XCTAssertNoThrow(try data.write(to: url, options: .atomic))
    }

    private func capture(_ name: String, element: XCUIElement) {
        let screenshot = element.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let url = outputDirectory.appendingPathComponent("\(name).png")
        guard let data = screenshot.image.pngData() else {
            XCTFail("Could not encode screenshot \(name)")
            return
        }
        XCTAssertNoThrow(try data.write(to: url, options: .atomic))
    }
}
