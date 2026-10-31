import XCTest
@testable import YamabikoChat

final class LicenseResourcesTests: XCTestCase {
    func testAppIncludesFullDependencyCopyrightNotices() throws {
        let documents = [
            "npm-license-texts": ["Haydn Paterson", "Anthropic, PBC", "Filip Skokan"],
            "swift-license-texts": ["Gwendal Roué", "The Swift Markdown Project", "John MacFarlane", "Kirill Simonov"],
            "python-core-license-texts": ["PYTHON SOFTWARE FOUNDATION", "Stefan Krah"],
            "python-package-license-texts": ["numpy", "matplotlib", "pillow"]
        ]
        for (name, attributions) in documents {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "legal"))
            let content = try String(contentsOf: url, encoding: .utf8)
            for attribution in attributions {
                XCTAssertTrue(content.contains(attribution), "\(name) must preserve \(attribution)")
            }
        }
    }

    func testAppIncludesPyodideLicenseAndSourceOffer() throws {
        let license = try XCTUnwrap(Bundle.main.url(forResource: "PYODIDE_LICENSE", withExtension: "txt", subdirectory: "legal"))
        XCTAssertTrue(try String(contentsOf: license, encoding: .utf8).contains("Mozilla Public License"))
        let sources = try XCTUnwrap(Bundle.main.url(forResource: "PYODIDE-SOURCES", withExtension: "md", subdirectory: "legal"))
        let content = try String(contentsOf: sources, encoding: .utf8)
        XCTAssertTrue(content.contains("b1e4fcc2488962f6360a97f19b9982d6fdb5d16f"))
        XCTAssertTrue(content.contains("memory-limit.patch"))
        XCTAssertTrue(content.contains("MPL-2.0"))
    }
}
