import UIKit
import WebKit
import XCTest
@testable import YamabikoChat

final class WebContentNetworkPolicyTests: XCTestCase {
    @MainActor
    func testNetworkPolicyCompilesWhenNoStoredPolicyExists() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try XCTUnwrap(WKContentRuleListStore(url: directory))

        let policy = try await YamabikoWebKitSupport.loadNetworkPolicy(from: store)

        XCTAssertEqual(policy.identifier, "YamabikoWebNoNetworkV1")
        let stored = try await store.contentRuleList(forIdentifier: policy.identifier)
        XCTAssertNotNil(stored)
    }

    @MainActor
    func testStoredNetworkPolicyIsReusedWithoutRecompilation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try XCTUnwrap(WKContentRuleListStore(url: directory))
        // A distinct compiled payload makes recompilation observable without network access.
        _ = try await store.compileContentRuleList(
            forIdentifier: "YamabikoWebNoNetworkV1",
            encodedContentRuleList: ##"[{"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":"#cache-probe"}}]"##
        )
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.isEmpty)
        let originalData = try files.map { try Data(contentsOf: $0) }

        let policy = try await YamabikoWebKitSupport.loadNetworkPolicy(from: store)

        XCTAssertEqual(policy.identifier, "YamabikoWebNoNetworkV1")
        XCTAssertEqual(try files.map { try Data(contentsOf: $0) }, originalData)
    }

    @MainActor
    private func fetchOutcome(for network: YamabikoWebKitSupport.NetworkAccess) async throws -> String {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                                configuration: YamabikoWebKitSupport.makeConfiguration(network: network))
        // No CSP: only the configuration decides whether the load happens.
        webView.loadHTMLString("<p>probe</p>", baseURL: nil)
        try await Task.sleep(nanoseconds: 300_000_000)
        let outcome = try await webView.callAsyncJavaScript("""
            try { await fetch('https://www.apple.com/library/test/success.html', {mode: 'no-cors', cache: 'no-store'}); return 'loaded' }
            catch (error) { return 'failed' }
            """, contentWorld: .page)
        return outcome as? String ?? "unknown"
    }

    @MainActor
    func testBlockedConfigurationPreventsNetworkLoadsWithoutPageCSP() async throws {
        // http is already refused by ATS inside WebKit, so the control must use real HTTPS.
        let control = try await fetchOutcome(for: .youTubeEmbed)
        guard control == "loaded" else {
            throw XCTSkip("Control HTTPS load failed: WebKit has no network in this environment")
        }
        let blocked = try await fetchOutcome(for: .blocked)
        XCTAssertEqual(blocked, "failed")
    }

    @MainActor
    func testFactoryNeverPersistsWebsiteData() {
        XCTAssertFalse(YamabikoWebKitSupport.makeConfiguration().websiteDataStore.isPersistent)
        XCTAssertFalse(YamabikoWebKitSupport.makeConfiguration(network: .youTubeEmbed).websiteDataStore.isPersistent)
    }

    func testGenUIDocumentURLsNeverWidenTheCanvasPolicy() throws {
        let document = GenUIDocument(title: "Images", ui: GenUINode(
            type: "AsyncImage", props: ["src": .string("https://attacker.example/x.png?d=secret")]))
        let html = try XCTUnwrap(GenUIRichWebView.Coordinator.html(
            document: document, snapshot: nil, dark: false,
            externalImages: ["https://images.example/a.png": "data:image/png;base64,AAAA", "https://images.example/b.png": nil]))
        let policy = try XCTUnwrap(html.range(of: #"Content-Security-Policy" content="[^"]*""#, options: .regularExpression).map { String(html[$0]) })
        XCTAssertTrue(policy.contains("img-src data:;"))
        XCTAssertTrue(policy.contains("connect-src 'none'"))
        XCTAssertTrue(policy.contains("media-src 'none'"))
        XCTAssertTrue(policy.contains("frame-src 'none'"))
        XCTAssertFalse(policy.contains("attacker.example"))
        XCTAssertFalse(policy.contains("https:"))
        let encoded = try XCTUnwrap(html.range(of: #"__GENUI_EXTERNAL_IMAGES__=decode\('([^']*)'"#, options: .regularExpression)
            .map { String(html[$0].dropFirst("__GENUI_EXTERNAL_IMAGES__=decode('".count).dropLast()) })
        let images = try JSONDecoder().decode([String: String?].self, from: XCTUnwrap(Data(base64Encoded: encoded)))
        let expected: [String: String?] = ["https://images.example/a.png": "data:image/png;base64,AAAA", "https://images.example/b.png": nil]
        XCTAssertEqual(images, expected)
    }

    private final class StubImageProtocol: URLProtocol {
        nonisolated(unsafe) static var responses: [String: (String, Data)] = [:]
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let (type, data) = Self.responses[request.url!.absoluteString] ?? ("text/plain", Data())
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": type])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    func testExternalImageLoaderReturnsDataURLsOnlyForDecodableImages() async throws {
        let png = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { _ in }.pngData())
        StubImageProtocol.responses = [
            "https://images.example/ok.png": ("image/png", png),
            "https://images.example/page": ("text/html", Data("<html>".utf8)),
            "https://images.example/fake.png": ("image/png", Data("not an image".utf8))
        ]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubImageProtocol.self]
        let urls = StubImageProtocol.responses.keys.compactMap(URL.init(string:))
        let images = await GenUIExternalImageLoader.load(urls, session: URLSession(configuration: configuration))
        XCTAssertEqual(images["https://images.example/ok.png"], .some("data:image/png;base64,\(png.base64EncodedString())"))
        XCTAssertEqual(images["https://images.example/page"], .some(nil))
        XCTAssertEqual(images["https://images.example/fake.png"], .some(nil))
    }
}
