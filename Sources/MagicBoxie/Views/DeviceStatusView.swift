import SwiftUI

/// Sync status, sourced from MagicBoxie-web: when the device last checked in
/// (GET /api/devices) and which movies are flagged to sync to it, each
/// cross-referenced against BLEManager.movies to show whether it's actually
/// landed on the device yet or is still waiting. Device-reported fields
/// (IP, what's downloading right now) come straight from the device itself
/// over HTTP instead - see BLEManager.refreshDeviceInfo.
struct DeviceStatusView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @EnvironmentObject private var webClient: MagicBoxieWebClient
    @State private var isRefreshing = false
    @State private var showingShutdownConfirmation = false

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
        Group {
            if webClient.isAuthenticated {
                deviceDetails
            } else {
                notConnected
            }
        }
        .navigationTitle("Device")
    }

    private var notConnected: some View {
        VStack(spacing: 12) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Not Connected to Media Library")
                .font(.headline)
            Text("Connect from the Media Library tab to see device status.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
    }

    private var deviceDetails: some View {
        List {
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
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground.ignoresSafeArea())
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

    private func refresh() async {
        isRefreshing = true
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
