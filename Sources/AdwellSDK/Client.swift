import Foundation
import os
#if canImport(AdServices)
import AdServices
#endif
#if canImport(StoreKit)
import StoreKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Facts about the host app and device, read off the main thread.
struct Environment {
    var bundleID: () -> String = { Bundle.main.bundleIdentifier ?? "unknown" }
    var appVersion: () -> String = { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown" }
    var osVersion: () -> String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion == 0 ? "\(v.majorVersion).\(v.minorVersion)" : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
    var locale: () -> String? = { Locale.current.identifier }
    /// App Store country (ISO alpha-3), nil when unknown. Calls back once.
    var storefront: (@escaping (String?) -> Void) -> Void = Environment.appStoreStorefront
    /// Apple's AdServices token, or the reason there is none (ADR 0002 D5).
    var attributionToken: () -> (token: String?, error: String?) = Environment.adServicesToken
    var now: () -> Date = Date.init

    static func adServicesToken() -> (token: String?, error: String?) {
        #if canImport(AdServices)
        if #available(iOS 14.3, *) {
            do {
                return (try AAAttribution.attributionToken(), nil)
            } catch {
                return (nil, String(String(describing: error).prefix(200)))
            }
        }
        #endif
        return (nil, "unavailable: iOS earlier than 14.3")
    }

    static func appStoreStorefront(_ done: @escaping (String?) -> Void) {
        #if canImport(StoreKit)
        if #available(iOS 15.0, *) {
            Task.detached(priority: .utility) { done(await Storefront.current?.countryCode) }
            return
        }
        #endif
        done(nil)
    }
}

/// Sends the install once per install_id, retrying until the server
/// acknowledges it. All state lives on one serial background queue.
final class Client {
    private let queue = DispatchQueue(label: "com.runadwell.sdk", qos: .utility)
    private let identity: () -> InstallIdentity
    private let acked: ValueStore
    private let transport: Transport
    private let env: Environment
    private let log: Log
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void

    private var apiKey = ""
    private var endpoint: URL!
    private var bridge: String?
    private var started = false, inFlight = false, stopped = false
    private var attempt = 0

    init(identity: @escaping () -> InstallIdentity, acked: ValueStore, transport: Transport, env: Environment, log: Log,
         schedule: ((TimeInterval, @escaping () -> Void) -> Void)? = nil) {
        self.identity = identity
        self.acked = acked
        self.transport = transport
        self.env = env
        self.log = log
        self.schedule = schedule ?? { delay, work in DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: work) }
    }

    /// First call wins; later calls are no-ops (ADR 0002 D8).
    func start(apiKey: String, endpoint: URL, bridge: String?) {
        queue.async { [self] in
            guard !started else { return log.debug("configure called again; ignored") }
            started = true
            self.apiKey = apiKey
            self.endpoint = endpoint.appendingPathComponent("v1/ingest/install")
            self.bridge = bridge
            send()
        }
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.foreground()
        }
        #endif
    }

    /// A pending install is retried as soon as the app comes back.
    func foreground() {
        queue.async { [self] in
            guard started, !stopped else { return }
            attempt = 0
            send()
        }
    }

    /// Runs on queue.
    private func send() {
        let id = identity()
        guard !inFlight, !stopped, acked.read() != id.installID else { return }
        inFlight = true
        // A fresh token per attempt: tokens last 24h and a retry may come later.
        let token = env.attributionToken()
        var answered = false
        let finish: (String?) -> Void = { [self] storefront in
            queue.async { [self] in
                guard !answered else { return }
                answered = true
                post(id: id, token: token, storefront: storefront)
            }
        }
        env.storefront(finish)
        later(2) { finish(nil) } // never wait long for StoreKit
    }

    private func post(id: InstallIdentity, token: (token: String?, error: String?), storefront: String?) {
        let req = InstallRequest(installID: id.installID, bundleID: env.bundleID(),
                                 sdk: .init(name: "adwell-ios", version: Adwell.version, bridge: bridge),
                                 appVersion: env.appVersion(), osVersion: env.osVersion(), locale: env.locale(), storefront: storefront,
                                 isReinstall: id.isReinstall, attributionToken: token.token, tokenError: token.error, clientTS: env.now())
        guard let body = req.body() else {
            inFlight = false
            return log.debug("could not encode the install")
        }
        transport.post(endpoint, apiKey: apiKey, body: body) { [self] status, retryAfter in
            queue.async { [self] in handle(Outcome.from(status: status, retryAfter: retryAfter), id: id.installID) }
        }
    }

    private func handle(_ outcome: Outcome, id: String) {
        inFlight = false
        switch outcome {
        case .acknowledged:
            acked.write(id)
            log.debug("install \(id) acknowledged")
        case let .stop(reason):
            stopped = true
            log.debug("stopped: \(reason)")
        case let .retry(after):
            let delay = backoff(attempt: attempt, retryAfter: after)
            attempt += 1
            log.debug("will retry in \(Int(delay))s")
            later(delay) { [weak self] in self?.send() }
        }
    }

    /// Runs work on the queue after a delay.
    private func later(_ delay: TimeInterval, _ work: @escaping () -> Void) {
        schedule(delay) { [queue] in queue.async(execute: work) }
    }

    /// Waits for queued work, including work that work queues; tests only.
    func drain() { for _ in 0..<4 { queue.sync {} } }
}

/// Debug logging, off unless configure asks for it.
final class Log {
    var enabled = false
    private static let logger = Logger(subsystem: "com.runadwell.sdk", category: "Adwell")

    func debug(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let m = message()
        Log.logger.debug("\(m, privacy: .public)")
    }
}
