import Foundation

/// Body of POST /v1/ingest/install (ADR 0002 D6).
struct InstallRequest: Encodable, Equatable {
    struct SDK: Encodable, Equatable {
        let name: String
        let version: String
        let bridge: String?

        enum CodingKeys: CodingKey { case name, version, bridge }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name)
            try c.encode(version, forKey: .version)
            try c.encode(bridge, forKey: .bridge) // null, not missing
        }
    }

    let installID: String
    let bundleID: String
    let platform = "ios"
    let sdk: SDK
    let appVersion: String
    let osVersion: String
    let locale: String?
    let storefront: String?
    let isReinstall: Bool
    let attributionToken: String?
    let tokenError: String?
    let clientTS: Date

    enum CodingKeys: String, CodingKey {
        case installID = "install_id", bundleID = "bundle_id", platform, sdk, appVersion = "app_version", osVersion = "os_version"
        case locale, storefront, isReinstall = "is_reinstall", attributionToken = "attribution_token", tokenError = "token_error"
        case clientTS = "client_ts"
    }

    // Nulls are written out so the archived body shows what was missing.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(installID, forKey: .installID)
        try c.encode(bundleID, forKey: .bundleID)
        try c.encode(platform, forKey: .platform)
        try c.encode(sdk, forKey: .sdk)
        try c.encode(appVersion, forKey: .appVersion)
        try c.encode(osVersion, forKey: .osVersion)
        try c.encode(locale, forKey: .locale)
        try c.encode(storefront, forKey: .storefront)
        try c.encode(isReinstall, forKey: .isReinstall)
        try c.encode(attributionToken, forKey: .attributionToken)
        try c.encode(tokenError, forKey: .tokenError)
        try c.encode(clientTS, forKey: .clientTS)
    }

    func body() -> Data? {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return try? e.encode(self)
    }
}

/// What to do after one ingest attempt.
enum Outcome: Equatable {
    case acknowledged
    /// Retrying this launch will not help (bad key, wrong bundle, our bug).
    case stop(reason: String)
    /// Offline, rate limited or the server is down: try again later.
    case retry(after: TimeInterval?)

    static func from(status: Int?, retryAfter: String?) -> Outcome {
        guard let status else { return .retry(after: nil) } // no response: offline, DNS, TLS
        switch status {
        case 200..<300: return .acknowledged
        case 401: return .stop(reason: "invalid publishable key")
        case 403: return .stop(reason: "the key belongs to another bundle id or platform")
        case 400, 409, 413: return .stop(reason: "request rejected (\(status))")
        case 408, 429, 500...: return .retry(after: retryAfter.flatMap(TimeInterval.init).map { min(max($0, 1), 3600) })
        default: return .stop(reason: "unexpected status \(status)")
        }
    }
}

/// Delay before attempt n+1 within one launch: 15s, 1m, 5m, then every 15m.
func backoff(attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
    let steps: [TimeInterval] = [15, 60, 300, 900]
    return max(retryAfter ?? 0, steps[min(max(attempt, 0), steps.count - 1)])
}

/// Sends one request; nil status means no HTTP response.
protocol Transport {
    func post(_ url: URL, apiKey: String, body: Data, completion: @escaping (_ status: Int?, _ retryAfter: String?) -> Void)
}

struct URLSessionTransport: Transport {
    let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral // no cookies, no cache
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 60
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    func post(_ url: URL, apiKey: String, body: Data, completion: @escaping (Int?, String?) -> Void) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        session.dataTask(with: req) { _, response, _ in
            let http = response as? HTTPURLResponse
            completion(http?.statusCode, http?.value(forHTTPHeaderField: "Retry-After"))
        }.resume()
    }
}
