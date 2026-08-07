import SwiftUI

struct ConnectionStatusView: View {
    @EnvironmentObject private var bleManager: BLEManager

    var body: some View {
        VStack(spacing: 16) {
            Image("MBMark")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                .padding(.bottom, 8)

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
