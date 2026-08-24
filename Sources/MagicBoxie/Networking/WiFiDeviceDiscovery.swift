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

    /// How long to wait before recreating the browser after it fails - e.g.
    /// the Local Network permission prompt hadn't been answered yet on the
    /// very first launch after a fresh install, so that first browse attempt
    /// dies before the user gets to it. Retrying (rather than the previous
    /// behavior of leaving `browser` permanently non-nil after one failed
    /// attempt, which made start() a silent no-op forever after) means
    /// granting permission later - without a full app relaunch - can still
    /// recover on its own.
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
            Self.logger.error("mDNS browser failed: \(String(describing: error), privacy: .public) - retrying in \(Self.retryDelaySeconds)s")
            retry()
        case .waiting(let error):
            // Commonly means the Local Network permission prompt hasn't
            // been answered yet (or was denied) - not fatal on its own
            // (NWBrowser can transition out of .waiting on its own once
            // permission is granted), but retrying from scratch covers the
            // case where it doesn't and just sits here indefinitely.
            Self.logger.error("mDNS browser waiting: \(String(describing: error), privacy: .public) - retrying in \(Self.retryDelaySeconds)s")
            retry()
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
