import SwiftUI

/// Sync status, sourced from MagicBox-web: when the device last checked in
/// (GET /api/devices) and which movies are flagged to sync to it, each
/// cross-referenced against BLEManager.movies to show whether it's actually
/// landed on the device yet or is still waiting.
struct DeviceStatusView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @EnvironmentObject private var webClient: MagicBoxWebClient
    @State private var isRefreshing = false

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
            Section {
                if let lastCheckIn {
                    LabeledContent("Device", value: lastCheckIn.deviceID)
                    if let date = lastCheckIn.lastSeenAt {
                        LabeledContent("Last Checked In", value: date.formatted(.relative(presentation: .named)))
                    }
                } else {
                    Text("No device has checked in yet")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Check-In")
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
        .navigationTitle("Device")
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    private func refresh() async {
        isRefreshing = true
        async let devices: () = webClient.fetchDevices()
        async let movies: () = webClient.fetchMovies()
        _ = await (devices, movies)
        isRefreshing = false
    }
}

#Preview {
    NavigationStack {
        DeviceStatusView()
            .environmentObject(BLEManager())
            .environmentObject(MagicBoxWebClient())
    }
}
