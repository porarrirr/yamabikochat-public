import XCTest
@testable import YamabikoChat

/// Test bundle principal class. App web views require the WebKit network block that
/// the app bootstrap compiles; tests create web views without waiting for that UI.
@objc(YamabikoTestObserver)
final class YamabikoTestObserver: NSObject, XCTestObservation {
    override init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testBundleWillStart(_ testBundle: Bundle) {
        var failure: Error?
        var finished = false
        Task { @MainActor in
            do { try await YamabikoWebKitSupport.prepareNetworkPolicy() } catch { failure = error }
            finished = true
        }
        // WebKit completes compilation on the main run loop, so spin it instead of blocking.
        while !finished { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        if let failure { fatalError("WebKit network policy unavailable: \(failure)") }
    }
}
