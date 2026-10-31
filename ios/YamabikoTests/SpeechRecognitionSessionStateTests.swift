import Combine
import XCTest
@testable import YamabikoChat

final class SpeechRecognitionSessionStateTests: XCTestCase {
    @MainActor
    func testStoppingUnusedServiceDoesNotPublishRecordingChanges() {
        let service = SpeechRecognitionService()
        var recordingChanges: [Bool] = []
        let observation = service.$isRecording.dropFirst().sink { recordingChanges.append($0) }
        defer { observation.cancel() }

        service.stopRecording()
        service.stopRecording()

        XCTAssertFalse(service.isRecording)
        XCTAssertNil(service.error)
        XCTAssertTrue(recordingChanges.isEmpty, "Keyboard sends must not perform audio-session teardown")
    }

    func testEndInvalidatesCallbacksFromStoppedSession() {
        var state = SpeechRecognitionSessionState()
        let stoppedSessionID = state.begin()

        state.end()

        XCTAssertFalse(state.isActive(stoppedSessionID))
    }

    func testBeginningNewSessionInvalidatesCallbacksFromPreviousSession() {
        var state = SpeechRecognitionSessionState()
        let previousSessionID = state.begin()

        let currentSessionID = state.begin()

        XCTAssertFalse(state.isActive(previousSessionID))
        XCTAssertTrue(state.isActive(currentSessionID))
    }
}

final class SpeechAudioLevelHistoryTests: XCTestCase {
    func testAppendKeepsFixedCapacityAndAddsNewestLevelAtEnd() {
        var history = SpeechAudioLevelHistory()

        history.append(0.75)

        XCTAssertEqual(history.values.count, SpeechAudioLevelHistory.capacity)
        XCTAssertEqual(history.values.last, 0.75)
    }

    func testAppendClampsAudioLevelsToDisplayRange() {
        var history = SpeechAudioLevelHistory()

        history.append(1.5)
        XCTAssertEqual(history.values.last, 1)

        history.append(-0.5)
        XCTAssertEqual(history.values.last, 0)
    }

    func testResetClearsRecordedLevels() {
        var history = SpeechAudioLevelHistory()
        history.append(0.8)

        history.reset()

        XCTAssertTrue(history.values.allSatisfy { $0 == 0 })
    }
}
