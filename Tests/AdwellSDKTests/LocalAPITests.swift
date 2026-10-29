import XCTest
@testable import AdwellSDK

/// Sends one install to a local API. Runs only when TEST_RUNNER_ADWELL_LOCAL_KEY
/// (a pk_test_ key for bundle co.adwell.sdktest) is set for xcodebuild.
final class LocalAPITests: XCTestCase {
    func testSendsToTheLocalAPI() throws {
        guard let key = ProcessInfo.processInfo.environment["ADWELL_LOCAL_KEY"], !key.isEmpty else {
            throw XCTSkip("ADWELL_LOCAL_KEY not set")
        }
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

    func testAnUnknownKeyIsExplained() throws {
        guard ProcessInfo.processInfo.environment["ADWELL_LOCAL_KEY"] != nil else { throw XCTSkip("ADWELL_LOCAL_KEY not set") }
        var lines: [String] = []
        let log = Log()
        log.sink = { lines.append($0) }
        var env = Environment()
        env.bundleID = { "co.adwell.sdktest" }
        let id = InstallIdentity(installID: UUID().uuidString.lowercased(), isReinstall: false)
        let c = Client(identity: { id }, acked: MemoryStore(), transport: URLSessionTransport(), env: env, log: log)
        c.start(apiKey: "pk_test_" + String(repeating: "A", count: 32), endpoint: URL(string: "http://localhost:8080")!, bridge: nil)
        let deadline = Date().addingTimeInterval(15)
        while lines.isEmpty, Date() < deadline { Thread.sleep(forTimeInterval: 0.2); c.drain() }
        XCTAssertEqual(lines.count, 1)
        print("LOCAL_LINE=\(lines.first ?? "")")
    }
}
