import SwiftUI

/// Full-screen device connection status/control, reached from Settings.
/// Shows the same BLEManager.connectionState the Movies tab's compact
/// top banner does (ConnectionStatusView), just with room to breathe.
struct DeviceConnectionView: View {
    @EnvironmentObject private var bleManager: BLEManager

    var body: some View {
        VStack(spacing: 20) {
            Image("MBMark")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)

            switch bleManager.connectionState {
            case .disconnected:
                Text("Not connected")
                    .foregroundStyle(.secondary)
                Button(AppConfig.mode == .directAPI ? "Connect to Server" : "Scan for MagicBox") {
                    bleManager.retry()
                }
                .buttonStyle(.borderedProminent)
                .tint(.appAccent)
            case .scanning:
                ProgressView()
                Text("Scanning for MagicBox…")
                    .foregroundStyle(.secondary)
            case .connecting:
                ProgressView()
                Text("Connecting…")
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Retry") { bleManager.retry() }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
            case .connected:
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(bleManager.movies.count) movies on device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                movieList
            }

            if AppConfig.mode == .bluetooth {
                forgetDeviceSection
            }
        }
        .padding(.horizontal)
        .padding(.top)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Connect to Device")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if bleManager.connectionState == .connected {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        bleManager.refreshLibrary()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }

    /// Raw list of whatever the device is currently reporting over its
    /// library characteristic - deliberately no artwork/shelving/grouping,
    /// so it's useful for confirming what the device actually sees (e.g.
    /// while debugging a scan that hasn't finished yet) independent of the
    /// Movies tab's own presentation of the same data.
    @ViewBuilder
    private var movieList: some View {
        if bleManager.movies.isEmpty {
            Text("No movies found on device")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            List(bleManager.movies) { movie in
                VStack(alignment: .leading, spacing: 2) {
                    Text(movie.title)
                        .foregroundStyle(.white)
                    Text(Self.duration(movie.durationSeconds))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.appBackground)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
    }

    /// Clears what the app itself knows about the device and rescans - see
    /// BLEManager.forgetDevice(). Deliberately honest in the caption that
    /// this can't reach iOS's own system-level Bluetooth cache: only
    /// Settings > Bluetooth > Forget This Device can do that, and no app
    /// can trigger it programmatically.
    private var forgetDeviceSection: some View {
        VStack(spacing: 6) {
            Divider()
                .padding(.vertical, 8)
            Button("Forget Device", role: .destructive) {
                bleManager.forgetDevice()
            }
            .buttonStyle(.bordered)
            Text("Clears this app's own connection info and rescans. If problems persist, also use iOS Settings ▸ Bluetooth ▸ MagicBoxieDevice ▸ Forget This Device.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private static func duration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "Unknown duration" }
        let minutes = seconds / 60
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

#Preview {
    NavigationStack {
        DeviceConnectionView()
    }
    .environmentObject(BLEManager())
}
