import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var bleManager: BLEManager

    private var deviceStatusText: String {
        switch bleManager.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .scanning: return "Scanning…"
        case .failed: return "Failed"
        case .disconnected: return "Not Connected"
        }
    }

    var body: some View {
        List {
            Section("Connection") {
                NavigationLink {
                    DeviceConnectionView()
                } label: {
                    row(title: "Connect to Device", systemImage: "antenna.radiowaves.left.and.right", detail: deviceStatusText)
                }
                NavigationLink {
                    WiFiConnectionView()
                } label: {
                    row(title: "Connect via WiFi", systemImage: "wifi", detail: bleManager.wifiBaseURL != nil ? "Discovered" : "Not Found")
                }
                NavigationLink {
                    RemoteLibraryView()
                } label: {
                    row(title: "Connect to API", systemImage: "icloud", detail: nil)
                }
            }
            .listRowBackground(Color.appElevatedSurface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Settings")
    }

    private func row(title: String, systemImage: String, detail: String?) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if let detail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(BLEManager())
}
