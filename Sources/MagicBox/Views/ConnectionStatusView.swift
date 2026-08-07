import SwiftUI

struct ConnectionStatusView: View {
    @EnvironmentObject private var bleManager: BLEManager

    var body: some View {
        VStack(spacing: 16) {
            switch bleManager.connectionState {
            case .disconnected:
                Text("Not connected")
                Button("Scan for MagicBox") { bleManager.retry() }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
            case .scanning:
                ProgressView()
                Text("Scanning for MagicBox…")
            case .connecting:
                ProgressView()
                Text("Connecting…")
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
                Button("Retry") { bleManager.retry() }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
            case .connected:
                EmptyView()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
    }
}

#Preview {
    ConnectionStatusView()
        .environmentObject(BLEManager())
}
