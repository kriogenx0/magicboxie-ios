import SwiftUI

struct ConnectionStatusView: View {
    @EnvironmentObject private var bleManager: BLEManager

    var body: some View {
        HStack(spacing: 12) {
            switch bleManager.connectionState {
            case .disconnected:
                status("Not connected", systemImage: "wifi.slash")
                Spacer()
                connectButton
            case .scanning:
                ProgressView()
                Text("Scanning for MagicBox…")
                Spacer()
            case .connecting:
                ProgressView()
                Text("Connecting…")
                Spacer()
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.red)
                Spacer()
                connectButton
            case .connected:
                EmptyView()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.appBackground.opacity(0.96))
    }

    private var connectButton: some View {
        Button(AppConfig.mode == .directAPI ? "Connect to Server" : "Scan for MagicBox") {
            bleManager.retry()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(.appAccent)
    }

    private func status(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    ConnectionStatusView()
        .environmentObject(BLEManager())
}
