import Foundation

/// Setup mistakes, explained so the developer can fix them from the console.
enum Problems {
    /// Why this key cannot work in this environment, or nil if it looks right.
    /// Keys are `pk_live_` or `pk_test_` plus 32 base64url characters.
    static func key(_ key: String, environment: AdwellOptions.Environment) -> String? {
        let fix = "Copy the publishable key from Adwell → Setup → Keys into Adwell.configure(apiKey:)."
        if key.isEmpty {
            return "No API key. \(fix)"
        }
        if key != key.trimmingCharacters(in: .whitespacesAndNewlines) {
            return "The API key has spaces or a line break around it. \(fix)"
        }
        let live = key.hasPrefix("pk_live_"), test = key.hasPrefix("pk_test_")
        guard live || test else {
            return "\"\(redact(key))\" is not an Adwell publishable key; those start with pk_live_ or pk_test_. \(fix)"
        }
        let rest = key.dropFirst(8)
        guard rest.count == 32, rest.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            return "\"\(redact(key))\" is cut short or has extra characters. \(fix)"
        }
        switch (environment, test) {
        case (.production, true):
            return "pk_test_ keys only work with the staging environment. Use your pk_live_ key, or pass AdwellOptions(environment: .staging)."
        case (.staging, false):
            return "pk_live_ keys only work with the production environment. Use a pk_test_ key for staging, or drop environment: .staging."
        default:
            return nil
        }
    }

    /// The server's reason for refusing an install, with what to do about it.
    static func rejected(status: Int, body: Data?, bundleID: String) -> String {
        let e = (body.flatMap { try? JSONDecoder().decode(ErrorBody.self, from: $0) })?.error
        let said = e.map { " Adwell said: \($0.message)." } ?? ""
        switch status {
        case 401:
            return "Adwell did not accept the API key.\(said) Check it in Adwell → Setup → Keys: it may be revoked, or a pk_live_/pk_test_ key used in the wrong environment."
        case 403:
            return "This API key belongs to another app.\(said) It does not match bundle id \(bundleID) on iOS; create a key for this app in Adwell → Setup → Keys."
        case 409:
            return "This install id is registered to another Adwell app.\(said) Check that the key is for \(bundleID)."
        default:
            let field = e?.field.map { " (field \($0))" } ?? ""
            return "Adwell rejected the install with status \(status)\(field).\(said) Please report this with SDK version \(Adwell.version)."
        }
    }

    /// Enough of a key to recognise it in a log, not to use it.
    static func redact(_ key: String) -> String {
        key.count <= 12 ? key : key.prefix(12) + "…"
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable {
            let code: String
            let message: String
            let field: String?
        }
        let error: Detail
    }
}
