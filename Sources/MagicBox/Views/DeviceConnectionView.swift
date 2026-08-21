import SwiftUI

/// Full-screen device connection status/control, reached from Settings.
/// Shows the same BLEManager.connectionState the Movies view's inline
/// prompt does (ConnectionStatusView), just with room to breathe.
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

            if bleManager.connectionState == .connected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(bleManager.movies.count) movies on device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                apiCompatibilitySection
                movieList
            } else {
                ConnectionStatusView()
            }

            if AppConfig.mode == .bluetooth {
                forgetDeviceSection
            }
        }
        .padding(.horizontal)
        .padding(.top)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Device Bluetooth")
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

    /// Warns when this app build and the connected device disagree on the
    /// wire protocol (BLEManager.apiCompatibility) - most likely direction
    /// in practice is the device being ahead, since redeploying it is a
    /// much lighter operation than shipping a new build of this app to a
    /// physical phone.
    @ViewBuilder
    private var apiCompatibilitySection: some View {
        switch bleManager.apiCompatibility {
        case .compatible:
            EmptyView()
        case .appOutdated:
            compatibilityWarning("This device has been updated - download a new version of MagicBox to keep using all of its features.")
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
        .padding(10)
        .background(Color.appElevatedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(movie.title)
                            .foregroundStyle(.white)
                        Text(Self.duration(movie.durationSeconds))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if bleManager.transcodingMovieID == movie.id {
                        Spacer()
                        Label("Transcoding", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(Color.appAccent)
                    }
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
