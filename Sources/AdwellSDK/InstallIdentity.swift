import Foundation
import Security

/// A string slot that may fail silently. Keychain and UserDefaults both
/// implement it; tests use memory.
protocol ValueStore {
    func read() -> String?
    func write(_ value: String)
}

/// The install_id and whether this launch is a reinstall (ADR 0002 D4).
struct InstallIdentity: Equatable {
    let installID: String
    let isReinstall: Bool

    /// Read order: Keychain, then UserDefaults, then generate. Never
    /// regenerates while either holds a value; repairs the missing copy.
    /// Keychain without UserDefaults is a reinstall on the same device.
    static func resolve(keychain: ValueStore, defaults: ValueStore, generate: () -> String = { UUID().uuidString.lowercased() }) -> InstallIdentity {
        let k = valid(keychain.read())
        let d = valid(defaults.read())
        switch (k, d) {
        case let (k?, d?):
            if k != d { defaults.write(k) } // the Keychain survives reinstalls; it wins
            return InstallIdentity(installID: k, isReinstall: false)
        case let (k?, nil):
            defaults.write(k)
            return InstallIdentity(installID: k, isReinstall: true)
        case let (nil, d?):
            keychain.write(d)
            return InstallIdentity(installID: d, isReinstall: false)
        case (nil, nil):
            let id = generate()
            keychain.write(id)
            defaults.write(id)
            return InstallIdentity(installID: id, isReinstall: false)
        }
    }

    /// A lowercase UUID, or nil for anything else found in storage.
    private static func valid(_ s: String?) -> String? {
        guard let s, let u = UUID(uuidString: s) else { return nil }
        return u.uuidString.lowercased()
    }
}

struct DefaultsStore: ValueStore {
    let key: String
    var defaults: UserDefaults = .standard

    func read() -> String? { defaults.string(forKey: key) }
    func write(_ value: String) { defaults.set(value, forKey: key) }
}

/// Generic password item, AfterFirstUnlockThisDeviceOnly: readable in the
/// background after the first unlock, never synced or restored to another
/// device.
struct KeychainStore: ValueStore {
    var service = "com.runadwell.sdk"
    var account = "install_id"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String) {
        let data = Data(value.utf8)
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            var add = query
            add.merge(attrs) { $1 }
            _ = SecItemAdd(add as CFDictionary, nil)
        }
    }
}
