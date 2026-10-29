import XCTest
@testable import AdwellSDK

final class ProblemsTests: XCTestCase {
    let live = "pk_live_" + String(repeating: "Ab3_", count: 8)
    let test = "pk_test_" + String(repeating: "x-9Z", count: 8)

    func testGoodKeysPass() {
        XCTAssertNil(Problems.key(live, environment: .production))
        XCTAssertNil(Problems.key(test, environment: .staging))
    }

    func testEachMistakeIsNamed() {
        let cases: [(String, AdwellOptions.Environment, String)] = [
            ("", .production, "No API key."),
            (live + "\n", .production, "spaces or a line break"),
            ("sk_live_abcdefghijklmnop", .production, "\"sk_live_abcd…\" is not an Adwell publishable key"),
            (String(live.dropLast(3)), .production, "cut short or has extra characters"),
            ("pk_live_" + String(repeating: "é", count: 32), .production, "cut short or has extra characters"),
            (test, .production, "pk_test_ keys only work with the staging environment"),
            (live, .staging, "pk_live_ keys only work with the production environment"),
        ]
        for (key, env, want) in cases {
            let got = Problems.key(key, environment: env) ?? "nil"
            XCTAssertTrue(got.contains(want), "\(key): \(got)")
        }
    }

    func testTheKeyIsNeverLoggedWhole() {
        let got = Problems.key(String(live.dropLast(1)), environment: .production) ?? ""
        XCTAssertFalse(got.contains(String(live.dropLast(1))))
        XCTAssertTrue(got.contains("pk_live_Ab3_…"))
    }

    func testConfigureWithABadKeyPrintsAndSendsNothing() {
        var lines: [String] = []
        let old = Adwell.log.sink
        Adwell.log.sink = { lines.append($0) }
        defer { Adwell.log.sink = old }
        Adwell.configure(apiKey: "pk_test_short")
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].hasPrefix("[Adwell] Error: \"pk_test_shor…\" is cut short"), lines[0])
        XCTAssertTrue(lines[0].hasSuffix("Adwell is not sending anything."))
    }

    func testRejectionWithoutABody() {
        XCTAssertTrue(Problems.rejected(status: 418, body: Data("<html>".utf8), bundleID: "b").contains("status 418"))
    }
}
