import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var bleManager: BLEManager

    var body: some View {
        NavigationStack {
            Group {
                if bleManager.connectionState == .connected {
                    MovieLibraryView()
                } else {
                    ConnectionStatusView()
                }
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    if AppConfig.mode == .directAPI {
                        Text("DEV MODE — Direct API (no Bluetooth)")
                            .font(.caption)
                            .padding(6)
                            .frame(maxWidth: .infinity)
                            .background(Color.yellow.opacity(0.3))
                    }
                    if AppConfig.mode == .bluetooth,
                       bleManager.activeTransport == .bluetooth,
                       let wifiURL = bleManager.suggestedWiFiURL {
                        WiFiSuggestionBanner(
                            url: wifiURL,
                            onSwitch: { bleManager.switchToWiFi() },
                            onDismiss: { bleManager.dismissWiFiSuggestion() }
                        )
                    }
                }
            }
        }
    }
}

/// Offers switching from BLE to WiFi once the device has reported its own
/// HTTP address - BLE is fine for control, but a poor fit for the bulk data
/// (movie library, thumbnails) that mode also needs to fetch.
private struct WiFiSuggestionBanner: View {
    let url: URL
    let onSwitch: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Text("MagicBox is available over WiFi for faster loading.")
                .font(.caption)
            Spacer()
            Button("Switch", action: onSwitch)
                .font(.caption.bold())
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color.blue.opacity(0.2))
    }
}

#Preview {
    ContentView()
        .environmentObject(BLEManager())
        .environmentObject(MovieArtworkStore())
}
