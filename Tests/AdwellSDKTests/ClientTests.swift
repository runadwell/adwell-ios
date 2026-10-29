import XCTest
@testable import AdwellSDK

final class FakeTransport: Transport {
    var answers: [(Int?, String?)]
    var bodies: [[String: Any]] = []
    var keys: [String] = []
    var urls: [URL] = []
    init(_ answers: [(Int?, String?)]) { self.answers = answers }

    func post(_ url: URL, apiKey: String, body: Data, completion: @escaping (Int?, String?) -> Void) {
        urls.append(url)
        keys.append(apiKey)
        bodies.append(try! JSONSerialization.jsonObject(with: body) as! [String: Any])
        let a = answers.isEmpty ? (202, nil) : answers.removeFirst()
        completion(a.0, a.1)
    }
}

/// Collects delayed work so tests run it by hand.
final class Timers {
    var pending: [(TimeInterval, () -> Void)] = []
    func schedule(_ d: TimeInterval, _ work: @escaping () -> Void) { pending.append((d, work)) }
    /// Runs and removes timers of the given delay.
    func fire(_ d: TimeInterval) {
        let due = pending.filter { $0.0 == d }
        pending.removeAll { $0.0 == d }
        due.forEach { $0.1() }
    }
}

final class ClientTests: XCTestCase {
    let id = InstallIdentity(installID: "6f1c0e3a-6c4b-4f53-9d2a-0b7a1f2e3d4c", isReinstall: true)
    let api = URL(string: "https://api.example.test")!

    func env(token: String? = "tok", storefront: String? = "CAN") -> Environment {
        var e = Environment()
        e.bundleID = { "co.smartreceipts.ios" }
        e.appVersion = { "4.12.0" }
        e.osVersion = { "18.1" }
        e.locale = { "en_CA" }
        e.storefront = { $0(storefront) }
        e.attributionToken = { (token, token == nil ? "no token" : nil) }
        e.now = { Date(timeIntervalSince1970: 1_792_000_000) }
        return e
    }

    func client(_ t: Transport, acked: MemoryStore, timers: Timers, env: Environment? = nil) -> Client {
        Client(identity: { self.id }, acked: acked, transport: t, env: env ?? self.env(), log: Log(), schedule: timers.schedule)
    }

    func testSendsTheContractBodyOnceAndRemembersTheAck() {
        let t = FakeTransport([(202, nil)]), acked = MemoryStore(), timers = Timers()
        let c = client(t, acked: acked, timers: timers)
        c.start(apiKey: "pk_test_x", endpoint: api, bridge: nil)
        c.drain()
        XCTAssertEqual(t.urls, [URL(string: "https://api.example.test/v1/ingest/install")!])
        XCTAssertEqual(t.keys, ["pk_test_x"])
        let b = t.bodies[0]
        XCTAssertEqual(b["install_id"] as? String, id.installID)
        XCTAssertEqual(b["bundle_id"] as? String, "co.smartreceipts.ios")
        XCTAssertEqual(b["platform"] as? String, "ios")
        XCTAssertEqual((b["sdk"] as? [String: Any])?["name"] as? String, "adwell-ios")
        XCTAssertEqual((b["sdk"] as? [String: Any])?["version"] as? String, Adwell.version)
        XCTAssertTrue((b["sdk"] as? [String: Any])?["bridge"] is NSNull)
        XCTAssertEqual(b["storefront"] as? String, "CAN")
        XCTAssertEqual(b["is_reinstall"] as? Bool, true)
        XCTAssertEqual(b["attribution_token"] as? String, "tok")
        XCTAssertTrue(b["token_error"] is NSNull)
        XCTAssertEqual(b["client_ts"] as? String, "2026-10-14T17:46:40Z")
        XCTAssertEqual(acked.value, id.installID)

        timers.fire(2) // the StoreKit timeout after an answer does nothing
        c.foreground(); c.drain()
        XCTAssertEqual(t.bodies.count, 1, "an acknowledged install is never sent again")
    }

    func testAlreadyAcknowledgedSendsNothingAndConfigureTwiceIsANoop() {
        let t = FakeTransport([]), timers = Timers()
        let c = client(t, acked: MemoryStore(id.installID), timers: timers)
        c.start(apiKey: "pk_test_x", endpoint: api, bridge: nil)
        c.start(apiKey: "pk_test_y", endpoint: api, bridge: nil)
        c.drain()
        XCTAssertTrue(t.bodies.isEmpty)
    }

    func testRetriesWithBackoffAndRetryAfterThenStops() {
        let t = FakeTransport([(nil, nil), (503, "120"), (202, nil)]), acked = MemoryStore(), timers = Timers()
        let c = client(t, acked: acked, timers: timers, env: env(token: nil, storefront: nil))
        c.start(apiKey: "pk_test_x", endpoint: api, bridge: "flutter")
        c.drain()
        XCTAssertEqual(t.bodies.count, 1)
        XCTAssertEqual(t.bodies[0]["token_error"] as? String, "no token")
        XCTAssertEqual((t.bodies[0]["sdk"] as? [String: Any])?["bridge"] as? String, "flutter")
        XCTAssertNotNil(timers.pending.first { $0.0 == 15 }, "offline: first retry after 15s")

        timers.fire(15); c.drain()
        XCTAssertEqual(t.bodies.count, 2)
        XCTAssertNotNil(timers.pending.first { $0.0 == 120 }, "Retry-After beats the 60s step")
        XCTAssertNil(acked.value)

        timers.fire(120); c.drain()
        XCTAssertEqual(t.bodies.count, 3)
        XCTAssertEqual(acked.value, id.installID)
    }

    func testABadKeyStopsUntilNextLaunch() {
        let t = FakeTransport([(401, nil)]), timers = Timers()
        let c = client(t, acked: MemoryStore(), timers: timers)
        c.start(apiKey: "pk_test_bad", endpoint: api, bridge: nil)
        c.drain()
        c.foreground(); c.drain()
        XCTAssertEqual(t.bodies.count, 1)
        XCTAssertTrue(timers.pending.allSatisfy { $0.0 == 2 }, "no retry scheduled")
    }

    func testStorefrontTimeoutSendsWithout() {
        var e = env()
        e.storefront = { _ in } // StoreKit never answers
        let t = FakeTransport([(202, nil)]), timers = Timers()
        let c = client(t, acked: MemoryStore(), timers: timers, env: e)
        c.start(apiKey: "pk_test_x", endpoint: api, bridge: nil)
        c.drain()
        XCTAssertTrue(t.bodies.isEmpty)
        timers.fire(2); c.drain()
        XCTAssertTrue(t.bodies[0]["storefront"] is NSNull)
    }

    func testOutcomes() {
        XCTAssertEqual(Outcome.from(status: 202, retryAfter: nil), .acknowledged)
        XCTAssertEqual(Outcome.from(status: 429, retryAfter: "9999"), .retry(after: 3600))
        XCTAssertEqual(Outcome.from(status: 500, retryAfter: "soon"), .retry(after: nil))
        XCTAssertEqual(Outcome.from(status: 403, retryAfter: nil), .stop(reason: "the key belongs to another bundle id or platform"))
        XCTAssertEqual(backoff(attempt: 9, retryAfter: nil), 900)
    }

    func testPublicIDsAgree() {
        XCTAssertEqual(Adwell.appAccountToken.uuidString.lowercased(), Adwell.installID)
        XCTAssertEqual(Adwell.installID, Adwell.installID)
    }
}
