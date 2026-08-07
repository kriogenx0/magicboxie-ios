import Foundation
import Network

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

    var onResolve: ((URL) -> Void)?

    private var browser: NWBrowser?
    // Keyed by endpoint so a result seen again (e.g. a re-advertise) while a
    // prior resolve is still in flight doesn't spawn a duplicate connection.
    private var resolvingConnections: [NWEndpoint: NWConnection] = [:]

    func start() {
        guard browser == nil else { return }
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
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
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
        let connection = NWConnection(to: endpoint, using: .tcp)
        resolvingConnections[endpoint] = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard case .ready = state else { return }
            Task { @MainActor in
                defer {
                    connection.cancel()
                    self?.resolvingConnections[endpoint] = nil
                }
                guard let path = connection.currentPath,
                      let remote = path.remoteEndpoint,
                      case let .hostPort(host, port) = remote,
                      let url = URL(string: "http://\(Self.hostString(host)):\(port.rawValue)")
                else { return }
                self?.onResolve?(url)
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
