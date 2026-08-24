import SwiftUI

/// Everything about the physical device in one place: Bluetooth connection
/// status/control (absorbed from the old Settings > Device Bluetooth
/// screen), a WiFi reachability check (absorbed from Settings > Device
/// WiFi), and sync status sourced from MagicBoxie-web (when the device last
/// checked in, which movies are flagged to sync to it, and - live - what
/// it's downloading right now).
struct DeviceStatusView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @EnvironmentObject private var webClient: MagicBoxieWebClient
    @State private var isRefreshing = false
    @State private var showingShutdownConfirmation = false
    @State private var wifiTestState: WiFiTestState = .idle

    private enum WiFiTestState: Equatable {
        case idle
        case testing
        case success(movieCount: Int)
        case failure(String)
    }

    /// Ordered last_seen_at desc by the server - the most recently-checked-in
    /// device is what this single-device-oriented product cares about, even
    /// though the schema (and this list) technically supports more than one.
    private var lastCheckIn: RemoteDevice? {
        webClient.devices.first
    }

    private var syncedMovies: [RemoteMovie] {
        webClient.movies.filter { $0.syncEnabled }
    }

    var body: some View {
        List {
            bluetoothSection
            wifiSection
            if webClient.isAuthenticated {
                deviceInfoSection
                syncedMoviesSection
            } else {
                mediaLibraryPromptSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Device")
        .refreshable { await refresh() }
        .task { await refresh() }
        .alert("Power Off Device?", isPresented: $showingShutdownConfirmation) {
            Button("Power Off", role: .destructive) {
                bleManager.shutdownDevice()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The device will shut down completely. There's no way to turn it back on remotely - you'll need to physically power-cycle it.")
        }
    }

    // MARK: - Bluetooth

    @ViewBuilder
    private var bluetoothSection: some View {
        Section {
            if bleManager.connectionState == .connected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                LabeledContent("Movies on Device", value: "\(bleManager.movies.count)")
                apiCompatibilityWarning
            } else {
                ConnectionStatusView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        } header: {
            Text("Bluetooth")
        }
        .listRowBackground(Color.appElevatedSurface)

        if bleManager.connectionState == .connected, AppConfig.mode == .bluetooth {
            Section {
                Button("Forget Device", role: .destructive) {
                    bleManager.forgetDevice()
                }
            } footer: {
                Text("Clears this app's own connection info and rescans. If problems persist, also use iOS Settings ▸ Bluetooth ▸ MagicBoxieDevice ▸ Forget This Device.")
            }
            .listRowBackground(Color.appElevatedSurface)
        }
    }

    /// Warns when this app build and the connected device disagree on the
    /// wire protocol (BLEManager.apiCompatibility) - most likely direction
    /// in practice is the device being ahead, since redeploying it is a
    /// much lighter operation than shipping a new build of this app to a
    /// physical phone.
    @ViewBuilder
    private var apiCompatibilityWarning: some View {
        switch bleManager.apiCompatibility {
        case .compatible:
            EmptyView()
        case .appOutdated:
            compatibilityWarning("This device has been updated - download a new version of MagicBoxie to keep using all of its features.")
        case .deviceOutdated:
            compatibilityWarning("This device is running older software than this app expects - redeploy the latest version to it.")
        }
    }

    private func compatibilityWarning(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
    }

    // MARK: - WiFi

    /// Read-only: deliberately doesn't add a WiFi control path, since BLE
    /// always carries commands regardless of what this shows - see
    /// BLEManager.uploadMovieIfNeeded/pushThumbnailToDeviceIfNeeded for
    /// WiFi's actual job (bulk data only).
    private var wifiSection: some View {
        Section {
            if let url = bleManager.wifiBaseURL {
                LabeledContent("Address", value: url.absoluteString)
            } else {
                Text("Device not yet discovered on WiFi")
                    .foregroundStyle(.secondary)
            }

            wifiTestResult

            Button("Test Connection") {
                Task { await testWiFiConnection() }
            }
            .disabled(bleManager.wifiBaseURL == nil || wifiTestState == .testing)
        } header: {
            Text("WiFi")
        }
        .listRowBackground(Color.appElevatedSurface)
    }

    @ViewBuilder
    private var wifiTestResult: some View {
        switch wifiTestState {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView()
        case .success(let count):
            Label("Connected — \(count) movie(s) found", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Text(message)
                .foregroundStyle(.red)
        }
    }

    private func testWiFiConnection() async {
        guard let url = bleManager.wifiBaseURL else { return }
        wifiTestState = .testing
        do {
            let movies = try await DeviceHTTPClient(baseURL: url).fetchMovies()
            wifiTestState = .success(movieCount: movies.count)
        } catch {
            wifiTestState = .failure(error.localizedDescription)
        }
    }

    // MARK: - Device info / sync (MagicBoxie-web)

    private var deviceInfoSection: some View {
        Section {
            if let ip = bleManager.deviceIPAddress {
                LabeledContent("IP Address", value: ip)
            }
            if let title = bleManager.syncingMovieTitle {
                LabeledContent("Downloading", value: title)
            } else if let lastCheckIn {
                if let date = lastCheckIn.lastSeenAt {
                    LabeledContent("Last Checked In", value: date.formatted(.relative(presentation: .named)))
                }
            } else {
                Text("No device has checked in yet")
                    .foregroundStyle(.secondary)
            }
            if AppConfig.mode == .bluetooth {
                Button("Power Off Device", role: .destructive) {
                    showingShutdownConfirmation = true
                }
            }
        } header: {
            Text("Device")
        }
        .listRowBackground(Color.appElevatedSurface)
    }

    private var syncedMoviesSection: some View {
        Section {
            if syncedMovies.isEmpty && isRefreshing {
                ProgressView()
            } else if syncedMovies.isEmpty {
                Text("No movies are set to sync to a device")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(syncedMovies) { movie in
                    HStack {
                        Text(movie.name)
                        Spacer()
                        if bleManager.movies.contains(where: { $0.title == movie.name }) {
                            Label("On device", systemImage: "checkmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.green)
                        } else if bleManager.syncingMovieTitle == movie.name {
                            ProgressView()
                        } else {
                            Label("Waiting to sync", systemImage: "clock")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Syncing to Device")
        }
        .listRowBackground(Color.appElevatedSurface)
    }

    private var mediaLibraryPromptSection: some View {
        Section {
            Text("Connect from the Media Library tab to see sync status.")
                .foregroundStyle(.secondary)
        } header: {
            Text("Syncing to Device")
        }
        .listRowBackground(Color.appElevatedSurface)
    }

    private func refresh() async {
        isRefreshing = true
        bleManager.refreshLibrary()
        async let devices: () = webClient.fetchDevices()
        async let movies: () = webClient.fetchMovies()
        async let deviceInfo: () = bleManager.refreshDeviceInfo()
        _ = await (devices, movies, deviceInfo)
        isRefreshing = false
    }
}

#Preview {
    NavigationStack {
        DeviceStatusView()
            .environmentObject(BLEManager())
            .environmentObject(MagicBoxieWebClient())
    }
}
