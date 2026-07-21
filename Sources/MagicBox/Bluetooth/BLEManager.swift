import Combine
import CoreBluetooth
import Foundation

enum ConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
    case failed(String)
}

/// Which transport is actually carrying movies/status/commands right now.
/// Distinct from AppConfig.mode (a build-time choice): this tracks the
/// user's runtime choice to switch a BLE session over to WiFi once the
/// device's HTTP address has been discovered.
enum ActiveTransport: Equatable {
    case bluetooth
    case wifi(URL)
}

/// Central-role BLE client: scans for the MagicBox peripheral, discovers the
/// Media Control Service, and exposes its state to SwiftUI.
final class BLEManager: NSObject, ObservableObject {
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var movies: [Movie] = []
    @Published private(set) var playbackState: PlaybackState = .idle
    /// Set once a BLE-connected device reports its own HTTP address; the UI
    /// offers switching to it since WiFi carries bulk data far better than BLE.
    @Published private(set) var suggestedWiFiURL: URL?
    @Published private(set) var activeTransport: ActiveTransport = .bluetooth

    private let mode = AppConfig.mode
    private var centralManager: CBCentralManager!
    private var devicePeripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var libraryCharacteristic: CBCharacteristic?
    private var networkInfoCharacteristic: CBCharacteristic?

    private var deviceClient: DeviceHTTPClient?
    private var statusPollTask: Task<Void, Never>?
    private var blePollTask: Task<Void, Never>?

    /// What play/pause/etc. actually use: a build-time direct-API dev session
    /// always uses WiFi; otherwise it's whatever the user has chosen at runtime.
    private var effectiveTransport: ActiveTransport {
        mode == .directAPI ? .wifi(AppConfig.deviceHTTPBaseURL) : activeTransport
    }

    override init() {
        super.init()
        switch mode {
        case .bluetooth:
            centralManager = CBCentralManager(delegate: self, queue: nil)
        case .directAPI:
            startDirectAPISession()
        }
    }

    deinit {
        statusPollTask?.cancel()
        blePollTask?.cancel()
    }

    /// Safety net against a missed BLE notification: forces a fresh status
    /// read every 30s so the UI can't silently drift out of sync with the
    /// device (e.g. still shown as playing after it actually stopped).
    private func startBLEStatusPolling() {
        blePollTask?.cancel()
        blePollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self else { break }
                if let peripheral = self.devicePeripheral, let characteristic = self.statusCharacteristic {
                    peripheral.readValue(for: characteristic)
                }
            }
        }
    }

    func startScanning() {
        guard mode == .bluetooth, centralManager.state == .poweredOn else { return }
        connectionState = .scanning
        centralManager.scanForPeripherals(
            withServices: [MediaControlProtocol.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func disconnect() {
        guard mode == .bluetooth, let peripheral = devicePeripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    /// Re-attempts the connection regardless of mode: BLE re-scan or a fresh
    /// direct-API session, whichever this build is configured for.
    func retry() {
        switch mode {
        case .bluetooth:
            startScanning()
        case .directAPI:
            startDirectAPISession()
        }
    }

    // MARK: - Runtime WiFi switch (BLE mode only)

    /// Called when the user accepts the "switch to WiFi" suggestion: from then
    /// on, movies/status/commands go over HTTP to the address the device
    /// itself reported, instead of BLE GATT reads/writes/notifications.
    func switchToWiFi() {
        guard mode == .bluetooth, let url = suggestedWiFiURL else { return }
        let client = DeviceHTTPClient(baseURL: url)
        deviceClient = client
        activeTransport = .wifi(url)

        Task {
            do {
                let deviceMovies = try await client.fetchMovies()
                movies = deviceMovies.map { Movie(id: $0.id, title: $0.title, durationSeconds: $0.durationSeconds) }
            } catch {
                // WiFi turned out not to be reachable after all - fall back to BLE.
                activeTransport = .bluetooth
            }
        }

        statusPollTask?.cancel()
        statusPollTask = Task {
            while !Task.isCancelled {
                await refreshDirectAPIStatus(using: client)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    /// Dismisses the suggestion without switching; stays on BLE.
    func dismissWiFiSuggestion() {
        suggestedWiFiURL = nil
    }

    // MARK: - Direct-API dev mode (no Bluetooth)

    /// Skips BLE entirely and talks to the device's own HTTP transport
    /// instead, so the real library/mpv logic can be exercised without BLE
    /// hardware or a Pi - e.g. against the Docker container on this Mac.
    private func startDirectAPISession() {
        connectionState = .connected
        let client = DeviceHTTPClient(baseURL: AppConfig.deviceHTTPBaseURL)
        deviceClient = client

        Task {
            do {
                let deviceMovies = try await client.fetchMovies()
                movies = deviceMovies.map { Movie(id: $0.id, title: $0.title, durationSeconds: $0.durationSeconds) }
            } catch {
                connectionState = .failed("Direct API mode: \(error.localizedDescription)")
            }
        }

        statusPollTask?.cancel()
        statusPollTask = Task {
            while !Task.isCancelled {
                await refreshDirectAPIStatus(using: client)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    // MARK: - Pushing official artwork back to the device

    private var uploadedThumbnailMovieIDs: Set<Int> = []

    /// Pushes a phone-fetched TMDB poster back to the device so it's cached
    /// there for other devices (or this one, later, with no internet at all).
    /// Only possible when there's an HTTP route to the device at all - BLE's
    /// tiny ATT payloads can't carry an image, so this silently no-ops there.
    func pushThumbnailToDeviceIfNeeded(movie: Movie, artwork: TMDBMovie) async {
        guard let client = deviceClient, !uploadedThumbnailMovieIDs.contains(movie.id) else { return }
        guard let posterURL = artwork.posterURL else { return }
        uploadedThumbnailMovieIDs.insert(movie.id)

        do {
            let (imageData, _) = try await URLSession.shared.data(from: posterURL)
            try await client.uploadThumbnail(movieID: movie.id, imageData: imageData)
        } catch {
            // Best-effort - the device's own ffmpeg-generated thumbnail remains
            // as a fallback either way. Allow a retry on a future connection.
            uploadedThumbnailMovieIDs.remove(movie.id)
        }
    }

    private func refreshDirectAPIStatus(using client: DeviceHTTPClient) async {
        guard let status = try? await client.fetchStatus() else { return }
        playbackState = PlaybackState(
            status: PlaybackStatus(deviceString: status.status),
            movieID: status.movieID,
            positionSeconds: status.positionSeconds
        )
    }

    private func sendDirectAPICommand(_ opcode: DeviceOpcode, argument: Int? = nil) {
        guard let client = deviceClient else { return }
        Task {
            try? await client.sendCommand(opcode, argument: argument)
            await refreshDirectAPIStatus(using: client)
        }
    }

    // MARK: - Transport commands

    func play() {
        switch effectiveTransport {
        case .bluetooth: sendCommand(.play)
        case .wifi: sendDirectAPICommand(.play)
        }
    }

    func pause() {
        switch effectiveTransport {
        case .bluetooth: sendCommand(.pause)
        case .wifi: sendDirectAPICommand(.pause)
        }
    }

    func stop() {
        switch effectiveTransport {
        case .bluetooth: sendCommand(.stop)
        case .wifi: sendDirectAPICommand(.stop)
        }
    }

    func seek(toSeconds seconds: Int) {
        switch effectiveTransport {
        case .bluetooth: sendCommand(.seek, argument: UInt32(max(0, seconds)))
        case .wifi: sendDirectAPICommand(.seek, argument: max(0, seconds))
        }
    }

    func selectMovie(_ movie: Movie) {
        switch effectiveTransport {
        case .bluetooth: sendCommand(.selectMovie, argument: UInt32(movie.id))
        case .wifi: sendDirectAPICommand(.selectMovie, argument: movie.id)
        }
    }

    private func sendCommand(_ opcode: MediaControlProtocol.Opcode, argument: UInt32? = nil) {
        guard let peripheral = devicePeripheral, let characteristic = commandCharacteristic else { return }
        let data = MediaControlProtocol.encodeCommand(opcode, argument: argument)
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            startScanning()
        case .poweredOff, .unauthorized, .unsupported:
            connectionState = .failed("Bluetooth is unavailable")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        centralManager.stopScan()
        devicePeripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting
        centralManager.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([MediaControlProtocol.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .failed(error?.localizedDescription ?? "Failed to connect")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        blePollTask?.cancel()
        commandCharacteristic = nil
        statusCharacteristic = nil
        libraryCharacteristic = nil
        networkInfoCharacteristic = nil
        suggestedWiFiURL = nil
        activeTransport = .bluetooth
        connectionState = .disconnected
        startScanning()
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == MediaControlProtocol.serviceUUID {
            peripheral.discoverCharacteristics(
                [
                    MediaControlProtocol.commandCharacteristicUUID,
                    MediaControlProtocol.statusCharacteristicUUID,
                    MediaControlProtocol.libraryCharacteristicUUID,
                    MediaControlProtocol.networkInfoCharacteristicUUID
                ],
                for: service
            )
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            switch characteristic.uuid {
            case MediaControlProtocol.commandCharacteristicUUID:
                commandCharacteristic = characteristic
            case MediaControlProtocol.statusCharacteristicUUID:
                statusCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                peripheral.readValue(for: characteristic)
            case MediaControlProtocol.libraryCharacteristicUUID:
                libraryCharacteristic = characteristic
                peripheral.readValue(for: characteristic)
            case MediaControlProtocol.networkInfoCharacteristicUUID:
                networkInfoCharacteristic = characteristic
                peripheral.readValue(for: characteristic)
            default:
                break
            }
        }
        if commandCharacteristic != nil, statusCharacteristic != nil {
            connectionState = .connected
            startBLEStatusPolling()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        switch characteristic.uuid {
        case MediaControlProtocol.statusCharacteristicUUID:
            if let state = MediaControlProtocol.decodeStatus(data) {
                playbackState = state
            }
        case MediaControlProtocol.libraryCharacteristicUUID:
            movies = MediaControlProtocol.decodeLibrary(data)
        case MediaControlProtocol.networkInfoCharacteristicUUID:
            suggestedWiFiURL = MediaControlProtocol.decodeNetworkURL(data)
        default:
            break
        }
    }
}
