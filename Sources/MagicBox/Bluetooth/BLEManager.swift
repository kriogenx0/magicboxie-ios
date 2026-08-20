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

/// Whether this app build and the connected device agree on the wire
/// protocol - see MediaControlProtocol.supportedAPIVersion.
enum APICompatibility: Equatable {
    /// Also covers "not known yet" (nothing read from the device so far) -
    /// there's nothing to warn about until there's an actual mismatch.
    case compatible
    /// The device speaks a newer protocol than this app build understands.
    case appOutdated
    /// This app build expects a newer protocol than the device provides.
    case deviceOutdated
}

/// Central-role BLE client: scans for the MagicBox peripheral, discovers the
/// Media Control Service, and exposes its state to SwiftUI.
///
/// Isolated to the main actor: without it, the unstructured Tasks that
/// sendDirectAPICommand spawns for every play/pause/queue action can resume
/// on background threads after their network await, racing each other's
/// reads/writes of `queue`/`pendingMovie` (plain, unsynchronized Array/enum
/// mutations) - this was observed to silently drop queued movies and reset
/// pendingMovie to nil under real device/network timing, alongside a
/// "Publishing changes from background threads" runtime warning.
@MainActor
final class BLEManager: NSObject, ObservableObject {
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var movies: [Movie] = []
    @Published private(set) var playbackState: PlaybackState = .idle
    /// The device's own HTTP base URL, once known - from whichever resolves
    /// first: mDNS (WiFiDeviceDiscovery, independent of BLE) or, as a
    /// fallback for when mDNS multicast doesn't reach the device, the BLE
    /// networkInfo characteristic. Used only for bulk data (movie/thumbnail
    /// uploads) - control always goes over BLE regardless of this.
    @Published private(set) var wifiBaseURL: URL?
    /// Set the instant a movie is tapped, before the device has confirmed
    /// anything - lets the UI show that movie in the controls with a loading
    /// state immediately, rather than waiting on a round trip first. Cleared
    /// once the device reports that movie as the active one.
    @Published private(set) var pendingMovie: Movie?
    /// The movie the mini player should show - set whenever playback of a
    /// movie starts and, unlike pendingMovie/playbackState.movieID, is NOT
    /// cleared just because the device reports "stopped": a movie reaching
    /// its natural end also reports stopped, and the mini player (plus
    /// whatever's still queued) should stay visible through that rather
    /// than vanish. Only an explicit stop() (or losing the connection)
    /// clears it.
    @Published private(set) var currentMovie: Movie?
    /// Up-next queue. The currently playing/loading movie is never in here -
    /// it's whichever was most recently popped off the front.
    @Published private(set) var queue: [Movie] = []
    /// What played before the current movie, most-recent-last - used by
    /// skipToPrevious(). Not surfaced in the UI; queue is the only
    /// user-visible list.
    private var history: [Movie] = []
    /// The movie id the device is currently re-encoding in its background
    /// transcode worker, if any - see TranscodeService on the device side.
    @Published private(set) var transcodingMovieID: Int?
    /// The connected device's own reported wire-protocol version, once
    /// known - see MediaControlProtocol.supportedAPIVersion and
    /// apiCompatibility.
    @Published private(set) var deviceAPIVersion: Int?

    var apiCompatibility: APICompatibility {
        guard let deviceAPIVersion else { return .compatible }
        if deviceAPIVersion > MediaControlProtocol.supportedAPIVersion { return .appOutdated }
        if deviceAPIVersion < MediaControlProtocol.supportedAPIVersion { return .deviceOutdated }
        return .compatible
    }

    private let mode = AppConfig.mode
    private var centralManager: CBCentralManager!
    private var devicePeripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var libraryCharacteristic: CBCharacteristic?
    private var networkInfoCharacteristic: CBCharacteristic?
    private var transcodeStatusCharacteristic: CBCharacteristic?
    private var apiVersionCharacteristic: CBCharacteristic?

    private let wifiDiscovery = WiFiDeviceDiscovery()
    private var deviceClient: DeviceHTTPClient?
    private var statusPollTask: Task<Void, Never>?
    private var blePollTask: Task<Void, Never>?

    override init() {
        super.init()
        switch mode {
        case .bluetooth:
            centralManager = CBCentralManager(delegate: self, queue: nil)
            wifiDiscovery.onResolve = { [weak self] url in self?.setWiFiBaseURL(url) }
            wifiDiscovery.start()
        case .directAPI:
            // Direct API is an optional development connection. Do not make
            // app launch depend on a server being available; the UI exposes
            // an explicit Connect button through `retry()`.
            break
        }
    }

    deinit {
        statusPollTask?.cancel()
        blePollTask?.cancel()
    }

    /// Accepts the first WiFi URL from whichever source resolves first (mDNS
    /// or the BLE networkInfo characteristic) and sticks with it for this
    /// BLEManager's lifetime - mirrors BLE's own "first peripheral found
    /// wins" behavior in `didDiscover`.
    private func setWiFiBaseURL(_ url: URL) {
        guard wifiBaseURL == nil else { return }
        wifiBaseURL = url
        deviceClient = DeviceHTTPClient(baseURL: url)
        // The initial library read (right after connecting) had to use
        // BLE, whose 512-byte cap may have silently truncated a real
        // library - upgrade to the uncapped HTTP source now that it's
        // available, rather than leaving that stuck until a manual refresh.
        refreshLibrary()
        Task { await flushPendingUploads() }
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

    // MARK: - Direct-API dev mode (no Bluetooth)

    /// Skips BLE entirely and talks to the device's own HTTP transport
    /// instead, so the real library/mpv logic can be exercised without BLE
    /// hardware or a Pi - e.g. against the Docker container on this Mac.
    private func startDirectAPISession() {
        connectionState = .connecting
        let client = DeviceHTTPClient(baseURL: AppConfig.deviceHTTPBaseURL)

        Task {
            do {
                let deviceMovies = try await client.fetchMovies()
                movies = deviceMovies.map {
                    Movie(id: $0.id, title: $0.title, durationSeconds: $0.durationSeconds, needsTranscoding: $0.needsTranscoding)
                }
                deviceClient = client
                connectionState = .connected
                startDirectAPIStatusPolling(using: client)
            } catch {
                connectionState = .failed("Direct API mode: \(error.localizedDescription)")
            }
        }
    }

    private func startDirectAPIStatusPolling(using client: DeviceHTTPClient) {
        statusPollTask?.cancel()
        statusPollTask = Task {
            while !Task.isCancelled {
                await refreshDirectAPIStatus(using: client)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    // MARK: - Importing a shared video file

    /// Surfaced by the UI as a dismissible banner - shares arrive via a Share
    /// Extension + URL handoff, with no other natural place to report status.
    enum ShareImportStatus: Equatable {
        case importing(title: String)
        case succeeded(title: String)
        case failed(title: String)
    }

    @Published private(set) var shareImportStatus: ShareImportStatus?

    /// Uploads a video shared in from another app (Photos/Dropbox/Files),
    /// unless a movie with the same title is already on the device. Requires
    /// an HTTP route - BLE alone can't carry a whole video file. Returns
    /// whether the upload actually happened, so callers that manage their
    /// own local copy (see RemoteLibraryView/queueForDeviceUpload) know
    /// whether it's now safe to delete it.
    @discardableResult
    func uploadMovieIfNeeded(fileURL: URL) async -> Bool {
        let title = fileURL.deletingPathExtension().lastPathComponent

        guard movies.first(where: { $0.title == title }) == nil else {
            shareImportStatus = .succeeded(title: title)
            return true
        }
        guard let client = deviceClient else {
            shareImportStatus = .failed(title: title)
            return false
        }

        shareImportStatus = .importing(title: title)
        do {
            let uploaded = try await client.uploadMovie(filename: fileURL.lastPathComponent, fileURL: fileURL)
            movies.append(
                Movie(id: uploaded.id, title: uploaded.title, durationSeconds: uploaded.durationSeconds, needsTranscoding: uploaded.needsTranscoding)
            )
            shareImportStatus = .succeeded(title: title)
            return true
        } catch {
            shareImportStatus = .failed(title: title)
            return false
        }
    }

    func dismissShareImportStatus() {
        shareImportStatus = nil
    }

    // MARK: - Relaying MagicBox-web downloads to the device when it isn't
    // reachable yet

    /// Where a movie downloaded from MagicBox-web waits when the device
    /// isn't reachable at download time (see RemoteLibraryView.downloadAndSend)
    /// - Application Support, not the OS-purgeable temporary directory,
    /// since these need to survive an unpredictable wait for the device to
    /// show up again.
    private static var pendingUploadsDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PendingDeviceUploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Moves a movie MagicBox-web has already handed to the phone into the
    /// pending-uploads directory, then immediately tries a flush in case
    /// the device is actually reachable by the time this runs.
    func queueForDeviceUpload(fileURL: URL) async {
        let destination = Self.pendingUploadsDirectory.appendingPathComponent(fileURL.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: fileURL, to: destination)
        await flushPendingUploads()
    }

    /// Pushes everything waiting in the pending-uploads directory to the
    /// device, deleting each file locally once it's confirmed to have
    /// arrived there. Called both right after queueing (the device may
    /// already be reachable) and from setWiFiBaseURL (the device may have
    /// just become reachable) - so a movie queued while offline goes out
    /// automatically the next time the device shows up, no further action
    /// needed from whoever queued it.
    func flushPendingUploads() async {
        guard deviceClient != nil else { return }
        let dir = Self.pendingUploadsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for fileURL in files {
            if await uploadMovieIfNeeded(fileURL: fileURL) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    // MARK: - Pushing official artwork back to the device

    private var uploadedThumbnailMovieIDs: Set<Int> = []

    /// Pushes a phone-fetched MagicBox-web poster back to the device so it's
    /// cached there for other devices (or this one, later, with no internet
    /// at all). Only possible when there's an HTTP route to the device at
    /// all - BLE's tiny ATT payloads can't carry an image, so this silently
    /// no-ops there.
    func pushThumbnailToDeviceIfNeeded(movie: Movie, artwork: RemoteMovie) async {
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
        updatePlaybackState(PlaybackState(
            status: PlaybackStatus(deviceString: status.status),
            movieID: status.movieID,
            positionSeconds: status.positionSeconds
        ))
    }

    /// Single point where the confirmed device status lands, so clearing the
    /// optimistic `pendingMovie` once it's confirmed can't be forgotten in
    /// one of the several places status arrives from (BLE notify, BLE poll,
    /// WiFi poll, post-command refresh).
    private func updatePlaybackState(_ newState: PlaybackState) {
        playbackState = newState
        if let pending = pendingMovie, newState.movieID == pending.id {
            pendingMovie = nil
        }
        // Nothing playing and nothing pending, but the queue has more - the
        // previous movie must have finished on its own. An explicit stop()
        // already empties the queue, so this can't misfire there.
        if newState.status == .stopped, pendingMovie == nil, !queue.isEmpty {
            playNextInQueue()
        }
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
        switch mode {
        case .bluetooth: sendCommand(.play)
        case .directAPI: sendDirectAPICommand(.play)
        }
    }

    func pause() {
        switch mode {
        case .bluetooth: sendCommand(.pause)
        case .directAPI: sendDirectAPICommand(.pause)
        }
    }

    /// Stops playback entirely and clears the queue - this is "stop", not
    /// "skip", so it shouldn't leave anything queued to auto-advance into.
    func stop() {
        pendingMovie = nil
        currentMovie = nil
        queue.removeAll()
        history.removeAll()
        switch mode {
        case .bluetooth: sendCommand(.stop)
        case .directAPI: sendDirectAPICommand(.stop)
        }
    }

    func seek(toSeconds seconds: Int) {
        switch mode {
        case .bluetooth: sendCommand(.seek, argument: UInt32(max(0, seconds)))
        case .directAPI: sendDirectAPICommand(.seek, argument: max(0, seconds))
        }
    }

    func skipForward15() {
        seek(toSeconds: playbackState.positionSeconds + 15)
    }

    func skipBackward15() {
        seek(toSeconds: playbackState.positionSeconds - 15)
    }

    /// Powers off the physical device entirely - not just stop playback.
    /// BLE-only: irrelevant in Direct-API dev mode, which talks to a Docker
    /// container on this Mac, not a real Pi. The UI must confirm before
    /// calling this - there's no remote way to turn the device back on,
    /// only physically power-cycling it.
    func shutdownDevice() {
        guard mode == .bluetooth else { return }
        sendCommand(.shutdown)
    }

    // MARK: - Forgetting the device

    /// Disconnects and clears everything the app itself has learned about
    /// the device, then starts a fresh scan. Useful after the device's BLE
    /// service has been redeployed/restarted, since that reassigns GATT
    /// attribute handles - iOS caches the old ones per peripheral and can
    /// get stuck trying to use them (surfaces as reads/writes silently
    /// failing or an "Invalid Handle" error at the protocol level). This
    /// only clears what the app can control; iOS's own system-level cache
    /// is outside any app's reach - if the problem persists after this,
    /// a real fix needs Settings > Bluetooth > (device) > Forget This
    /// Device, which only the user can do.
    func forgetDevice() {
        guard mode == .bluetooth else { return }
        if let peripheral = devicePeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        devicePeripheral = nil
        commandCharacteristic = nil
        statusCharacteristic = nil
        libraryCharacteristic = nil
        networkInfoCharacteristic = nil
        transcodeStatusCharacteristic = nil
        apiVersionCharacteristic = nil
        movies = []
        playbackState = .idle
        pendingMovie = nil
        currentMovie = nil
        queue.removeAll()
        transcodingMovieID = nil
        deviceAPIVersion = nil
        blePollTask?.cancel()
        connectionState = .disconnected
        startScanning()
    }

    // MARK: - Library

    /// Re-reads the movie library from the device. Useful because the app
    /// only ever reads it once, right after connecting - if that happened
    /// before the device finished scanning its content directory (BLE comes
    /// up well before that scan completes), the app is left showing an
    /// empty library forever with nothing to prompt a retry.
    ///
    /// Prefers WiFi/HTTP whenever it's available, in both modes: BLE's
    /// library characteristic is capped at 512 bytes (the hard maximum a
    /// single BLE attribute value can ever be - not a limit that can just
    /// be raised), which silently drops movies past that point once a real
    /// library's titles push the encoded size over it. HTTP has no such
    /// ceiling, matching how thumbnails already prefer WiFi over BLE for
    /// the same reason (bulk data over BLE's tiny ATT payloads).
    func refreshLibrary() {
        if let client = deviceClient {
            Task {
                guard let deviceMovies = try? await client.fetchMovies() else { return }
                movies = deviceMovies.map {
                    Movie(id: $0.id, title: $0.title, durationSeconds: $0.durationSeconds, needsTranscoding: $0.needsTranscoding)
                }
            }
            return
        }
        guard mode == .bluetooth, let peripheral = devicePeripheral, let characteristic = libraryCharacteristic else { return }
        peripheral.readValue(for: characteristic)
    }

    // MARK: - Queue

    /// Adds a movie to the end of the queue. If nothing is currently playing
    /// or about to, starts it immediately instead of leaving it stranded.
    func enqueue(_ movie: Movie) {
        queue.append(movie)
        if pendingMovie == nil && playbackState.movieID == nil {
            playNextInQueue()
        }
    }

    /// Jumps a movie to the front of the queue, ahead of everything else
    /// already there, and starts playing it right away.
    func playNow(_ movie: Movie) {
        queue.removeAll { $0.id == movie.id }
        queue.insert(movie, at: 0)
        playNextInQueue()
    }

    /// Skips the current movie in favor of whatever's next in the queue.
    /// Only meaningful when the queue isn't empty - the UI only shows a
    /// "Next" button in that case.
    func skipToNext() {
        playNextInQueue()
    }

    /// Drops a single movie out of the queue without touching whatever's
    /// currently playing - used by the queue list's swipe-to-remove.
    func removeFromQueue(_ movie: Movie) {
        queue.removeAll { $0.id == movie.id }
    }

    /// Standard media-player convention: restart the current movie if
    /// meaningfully into it, otherwise actually go back to whatever played
    /// before it (if anything) - re-queuing the current movie at the front
    /// rather than dropping it, so skipping back doesn't lose your place.
    func skipToPrevious() {
        guard playbackState.positionSeconds <= 3, let previous = history.popLast() else {
            seek(toSeconds: 0)
            return
        }
        if let current = currentMovie {
            queue.insert(current, at: 0)
        }
        playImmediately(previous)
    }

    private func playNextInQueue() {
        guard !queue.isEmpty else { return }
        if let current = currentMovie {
            history.append(current)
        }
        playImmediately(queue.removeFirst())
    }

    private func playImmediately(_ movie: Movie) {
        pendingMovie = movie
        currentMovie = movie
        switch mode {
        case .bluetooth:
            sendCommand(.selectMovie, argument: UInt32(movie.id))
            sendCommand(.play)
        case .directAPI:
            sendDirectAPICommand(.selectMovie, argument: movie.id)
            sendDirectAPICommand(.play)
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
        // wifiBaseURL/deviceClient are deliberately left as-is - WiFi
        // reachability doesn't depend on a live BLE session (the phone can
        // walk out of BLE range while staying on the same WiFi network).
        pendingMovie = nil
        currentMovie = nil
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
                    MediaControlProtocol.networkInfoCharacteristicUUID,
                    MediaControlProtocol.transcodeStatusCharacteristicUUID,
                    MediaControlProtocol.apiVersionCharacteristicUUID
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
            case MediaControlProtocol.transcodeStatusCharacteristicUUID:
                transcodeStatusCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                peripheral.readValue(for: characteristic)
            case MediaControlProtocol.apiVersionCharacteristicUUID:
                // No NOTIFY - a connected device's protocol version can't
                // change without a restart (which drops the connection
                // anyway), so a one-time read is enough.
                apiVersionCharacteristic = characteristic
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
                updatePlaybackState(state)
            }
        case MediaControlProtocol.libraryCharacteristicUUID:
            movies = MediaControlProtocol.decodeLibrary(data)
        case MediaControlProtocol.networkInfoCharacteristicUUID:
            if let url = MediaControlProtocol.decodeNetworkURL(data) { setWiFiBaseURL(url) }
        case MediaControlProtocol.transcodeStatusCharacteristicUUID:
            transcodingMovieID = MediaControlProtocol.decodeTranscodeStatus(data)
        case MediaControlProtocol.apiVersionCharacteristicUUID:
            deviceAPIVersion = MediaControlProtocol.decodeAPIVersion(data)
        default:
            break
        }
    }
}
