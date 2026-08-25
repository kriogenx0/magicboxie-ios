import Foundation
import Network
import os

/// Browses for the device's Bonjour advertisement and resolves it to an
/// "http://host:port" URL. Independent of BLE - this is the WiFi-first path
/// for learning the device's address; BLEManager's own networkInfo
/// characteristic read is the fallback path for when mDNS multicast doesn't
/// reach the device (e.g. client-isolated WiFi).
///
/// @MainActor to match BLEManager, which owns this and mutates its own
/// @Published state from the onResolve callback - see BLEManager's class
/// doc comment for why cross-thread mutation there is unsafe.
@MainActor
final class WiFiDeviceDiscovery {
    /// Must match mdns_service.py's SERVICE_TYPE (sans the ".local." suffix
    /// zeroconf requires but NWBrowser's `domain: nil` supplies implicitly).
    static let serviceType = "_magicboxie._tcp"

    private static let logger = Logger(subsystem: "com.alexv.magicboxie.app", category: "WiFiDeviceDiscovery")

    /// How long to wait before recreating the browser after it enters
    /// .failed (not .waiting - see handleStateUpdate). Retrying at all
    /// (rather than the original behavior of leaving `browser` permanently
    /// non-nil after one failed attempt, which made start() a silent no-op
    /// forever after) means a transient failure doesn't require a full app
    /// relaunch to recover from.
    private static let retryDelaySeconds: UInt64 = 5

    var onResolve: ((URL) -> Void)?

    private var browser: NWBrowser?
    private var stopped = false
    // Keyed by endpoint so a result seen again (e.g. a re-advertise) while a
    // prior resolve is still in flight doesn't spawn a duplicate connection.
    private var resolvingConnections: [NWEndpoint: NWConnection] = [:]

    func start() {
        guard browser == nil else { return }
        stopped = false
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters)
        // NWBrowser's handler closures are @Sendable and not statically known
        // to run on the main queue even though `.start(queue: .main)` makes
        // that true at runtime - hop back onto the actor explicitly before
        // touching any of this class's state.
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let first = results.first else { return }
            Task { @MainActor in self?.resolve(first.endpoint) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handleStateUpdate(state) }
        }
        browser.start(queue: .main)
        self.browser = browser
        Self.logger.info("mDNS browse started for \(Self.serviceType, privacy: .public)")
    }

    private func handleStateUpdate(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            Self.logger.info("mDNS browser ready")
        case .failed(let error):
            // Per Network.framework's documented contract, .failed is the
            // one state a browser does NOT recover from on its own - the
            // caller is expected to create a new one, which is what retry()
            // does.
            Self.logger.error("mDNS browser failed: \(String(describing: error), privacy: .public) - retrying in \(Self.retryDelaySeconds)s")
            retry()
        case .waiting(let error):
            // Unlike .failed, .waiting means the browser expects to recover
            // ON ITS OWN once whatever's blocking it clears (e.g. the Local
            // Network permission prompt not answered yet) - it keeps
            // retrying internally and will transition to .ready by itself.
            // Tearing it down and recreating it here (as an earlier version
            // of this code did) fought that: if a fresh browser re-enters
            // .waiting for the same reason, which is exactly what happens
            // while the blocking condition is still true, it gets killed
            // again before it can ever recover - a destroy-before-recovery
            // loop that can keep discovery permanently stuck. Log only.
            Self.logger.info("mDNS browser waiting: \(String(describing: error), privacy: .public)")
        case .cancelled:
            break
        default:
            break
        }
    }

    private func retry() {
        guard !stopped else { return }
        browser?.cancel()
        browser = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.retryDelaySeconds * 1_000_000_000)
            self?.start()
        }
    }

    func stop() {
        stopped = true
        browser?.cancel()
        browser = nil
        resolvingConnections.values.forEach { $0.cancel() }
        resolvingConnections.removeAll()
    }

    /// NWBrowser only hands back an opaque .service endpoint; resolving it to
    /// a usable host/port requires opening (and immediately parking) a
    /// connection and reading its resolved remote endpoint once ready.
    private func resolve(_ endpoint: NWEndpoint) {
        guard resolvingConnections[endpoint] == nil else { return }
        Self.logger.info("Resolving mDNS result: \(String(describing: endpoint), privacy: .public)")
        let connection = NWConnection(to: endpoint, using: .tcp)
        resolvingConnections[endpoint] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { @MainActor in
                    defer {
                        connection.cancel()
                        self?.resolvingConnections[endpoint] = nil
                    }
                    guard let path = connection.currentPath,
                          let remote = path.remoteEndpoint,
                          case let .hostPort(host, port) = remote,
                          let url = URL(string: "http://\(Self.hostString(host)):\(port.rawValue)")
                    else {
                        Self.logger.error("mDNS result resolved to a connection but no usable host/port")
                        return
                    }
                    Self.logger.info("mDNS resolved to \(url.absoluteString, privacy: .public)")
                    self?.onResolve?(url)
                }
            case .failed(let error):
                Self.logger.error("Resolving mDNS result failed: \(String(describing: error), privacy: .public)")
                Task { @MainActor in
                    connection.cancel()
                    self?.resolvingConnections[endpoint] = nil
                }
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    private static func hostString(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let address): return "\(address)"
        case .ipv6(let address): return "\(address)"
        case .name(let name, _): return name
        @unknown default: return "\(host)"
        }
    }
}
