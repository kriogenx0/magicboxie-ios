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
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Connect to Device")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        DeviceConnectionView()
    }
    .environmentObject(BLEManager())
}
