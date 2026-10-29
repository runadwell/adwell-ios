import XCTest
@testable import AdwellSDK

final class MemoryStore: ValueStore {
    var value: String?
    init(_ value: String? = nil) { self.value = value }
    func read() -> String? { value }
    func write(_ v: String) { value = v }
}

final class IdentityTests: XCTestCase {
    let a = "6f1c0e3a-6c4b-4f53-9d2a-0b7a1f2e3d4c"
    let b = "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"

    func testFreshInstallGeneratesAndStoresBoth() {
        let k = MemoryStore(), d = MemoryStore()
        let id = InstallIdentity.resolve(keychain: k, defaults: d, generate: { self.a })
        XCTAssertEqual(id, InstallIdentity(installID: a, isReinstall: false))
        XCTAssertEqual(k.value, a)
        XCTAssertEqual(d.value, a)
    }

    func testKeychainOnlyIsAReinstallWithTheSameID() {
        let k = MemoryStore(a), d = MemoryStore()
        let id = InstallIdentity.resolve(keychain: k, defaults: d, generate: { XCTFail("never regenerate"); return self.b })
        XCTAssertEqual(id, InstallIdentity(installID: a, isReinstall: true))
        XCTAssertEqual(d.value, a, "the missing copy is repaired")
    }

    func testDefaultsOnlyRepairsTheKeychain() {
        let k = MemoryStore(), d = MemoryStore(a)
        let id = InstallIdentity.resolve(keychain: k, defaults: d, generate: { XCTFail("never regenerate"); return self.b })
        XCTAssertEqual(id, InstallIdentity(installID: a, isReinstall: false))
        XCTAssertEqual(k.value, a)
    }

    func testKeychainWinsWhenTheyDisagree() {
        let k = MemoryStore(a), d = MemoryStore(b)
        XCTAssertEqual(InstallIdentity.resolve(keychain: k, defaults: d).installID, a)
        XCTAssertEqual(d.value, a)
    }

    func testUppercaseIsNormalisedAndGarbageIgnored() {
        let k = MemoryStore(a.uppercased()), d = MemoryStore("not-a-uuid")
        let id = InstallIdentity.resolve(keychain: k, defaults: d)
        XCTAssertEqual(id, InstallIdentity(installID: a, isReinstall: true))
    }

    func testGeneratedIDIsLowercaseUUID() {
        let id = InstallIdentity.resolve(keychain: MemoryStore(), defaults: MemoryStore()).installID
        XCTAssertEqual(id, id.lowercased())
        XCTAssertNotNil(UUID(uuidString: id))
    }

    func testRealKeychainRoundTrip() throws {
        let k = KeychainStore(service: "com.runadwell.sdk.tests", account: UUID().uuidString)
        XCTAssertNil(k.read())
        k.write(a)
        if k.read() == nil { throw XCTSkip("no keychain without a host app (errSecMissingEntitlement)") }
        k.write(b) // update, not a duplicate add
        XCTAssertEqual(k.read(), b)
    }
}
