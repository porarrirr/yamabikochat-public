import Foundation
import XCTest
@testable import YamabikoChat

final class ShortcutIntentDiagnosticsTests: XCTestCase {
    func testResolutionStageFailureIsRecordedInDiagnosticsLogAndRethrown() async throws {
        let marker = UUID().uuidString
        let failure = NSError(domain: "ShortcutIntentDiagnosticsTests", code: 42,
                              userInfo: [NSLocalizedDescriptionKey: "catalog unavailable \(marker)"])

        do {
            _ = try await ShortcutIntentSupport.logged("model options", metadata: ["provider": marker]) { () async throws -> [String] in
                throw failure
            }
            XCTFail("Expected the resolution error to be rethrown")
        } catch {
            XCTAssertEqual((error as NSError).code, 42)
        }

        let log = DiagnosticsLogger.read()
        XCTAssertTrue(log.contains("Shortcut model options failed"))
        XCTAssertTrue(log.contains("provider=\(marker)"))
        XCTAssertTrue(log.contains("ShortcutIntentDiagnosticsTests (42)"))
    }
}
