import XCTest
@testable import AdwellSDK

/// Sends one install to a local API. Runs only when TEST_RUNNER_ADWELL_LOCAL_KEY
/// (a pk_test_ key for bundle co.adwell.sdktest) is set for xcodebuild.
final class LocalAPITests: XCTestCase {
    func testSendsToTheLocalAPI() throws {
        let key = try XCTUnwrap(ProcessInfo.processInfo.environment["ADWELL_LOCAL_KEY"].flatMap { $0.isEmpty ? nil : $0 } ?? { throw XCTSkip("ADWELL_LOCAL_KEY not set") }())
        let id = InstallIdentity(installID: UUID().uuidString.lowercased(), isReinstall: false)
        let acked = MemoryStore()
        var env = Environment()
        env.bundleID = { "co.adwell.sdktest" }
        env.attributionToken = { ("local-test-token", nil) }
        let c = Client(identity: { id }, acked: acked, transport: URLSessionTransport(), env: env, log: Log())
        c.start(apiKey: key, endpoint: URL(string: "http://localhost:8080")!, bridge: nil)
        let deadline = Date().addingTimeInterval(15)
        while acked.value == nil, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        XCTAssertEqual(acked.value, id.installID, "the local API acknowledged the install")
        print("LOCAL_INSTALL_ID=\(id.installID)")
    }
}
