import Foundation

/// Adwell joins Apple Ads installs to subscription revenue. Call
/// `configure` once at launch, then give `installID` to your billing SDK.
///
/// Nothing here throws, blocks the main thread for network, or crashes the
/// app: failures are dropped and logged only with `logLevel: .debug`.
public enum Adwell {
    public static let version = "0.1.0"

    /// Starts sending this install to Adwell in the background. Calling it
    /// again is a no-op.
    public static func configure(apiKey: String, options: AdwellOptions = .init()) {
        log.enabled = options.logLevel == .debug
        let url = endpointOverride ?? options.environment.url
        client.start(apiKey: apiKey, endpoint: url, bridge: options.bridge)
    }

    /// This install's id: a lowercase UUID, stable across launches and, on
    /// the same device, across reinstalls. Set it on your billing SDK as the
    /// `adwell_install_id` attribute on every launch.
    public static var installID: String { identity.value.installID }

    /// The same id as a UUID, for StoreKit 2's `appAccountToken` purchase option.
    public static var appAccountToken: UUID { UUID(uuidString: installID) ?? UUID() }

    // MARK: - Internals

    static var endpointOverride: URL? // local API in tests
    private static let log = Log()
    private static let identity = IdentityCache {
        InstallIdentity.resolve(keychain: KeychainStore(), defaults: DefaultsStore(key: "com.runadwell.install_id"))
    }
    private static let client = Client(identity: { identity.value }, acked: DefaultsStore(key: "com.runadwell.acknowledged"),
                                       transport: URLSessionTransport(), env: Environment(), log: log)
}

public struct AdwellOptions {
    public enum Environment {
        case production, staging

        var url: URL {
            switch self {
            case .production: return URL(string: "https://api.runadwell.com")!
            case .staging: return URL(string: "https://api.staging.runadwell.com")!
            }
        }
    }

    public enum LogLevel { case off, debug }

    public var environment: Environment
    public var logLevel: LogLevel
    /// Set by the Flutter plugin (`"flutter"`); apps leave it nil.
    @_spi(Bridge) public var bridge: String?

    public init(environment: Environment = .production, logLevel: LogLevel = .off) {
        self.environment = environment
        self.logLevel = logLevel
    }
}

/// Resolves the identity once per launch, from any thread.
final class IdentityCache {
    private let lock = NSLock()
    private let resolve: () -> InstallIdentity
    private var cached: InstallIdentity?

    init(_ resolve: @escaping () -> InstallIdentity) { self.resolve = resolve }

    var value: InstallIdentity {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let v = resolve()
        cached = v
        return v
    }
}
