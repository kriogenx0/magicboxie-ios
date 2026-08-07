import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @EnvironmentObject private var artworkStore: MovieArtworkStore
    // Owned here (above the List) so pushing/popping MovieDetailView via
    // navigationDestination never rebuilds MovieLibraryView's List, which is
    // what would happen with a .sheet - this way scroll position survives.
    // Array-based path (rather than navigationDestination(item:)) since that
    // needs iOS 17 and this project targets 16.
    @State private var path: [Movie] = []
    @State private var showingRemoteLibrary = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if bleManager.connectionState == .connected {
                    MovieLibraryView(path: $path)
                } else {
                    ConnectionStatusView()
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: Movie.self) { movie in
                MovieDetailView(movie: movie, artwork: artworkStore.artwork(for: movie.title))
            }
            .overlay(alignment: .topTrailing) {
                // Downloading from MagicBox-web pushes onward via
                // BLEManager.uploadMovieIfNeeded, so this only makes sense
                // once actually connected to a device.
                if bleManager.connectionState == .connected {
                    Button {
                        showingRemoteLibrary = true
                    } label: {
                        Image(systemName: "icloud.and.arrow.down")
                            .foregroundStyle(.white)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                    .padding(.top, 7)
                    .padding(.trailing, 12)
                }
            }
            .sheet(isPresented: $showingRemoteLibrary) {
                NavigationStack {
                    RemoteLibraryView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Close") { showingRemoteLibrary = false }
                            }
                        }
                }
            }
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
                    if let status = bleManager.shareImportStatus {
                        ShareImportBanner(status: status, onDismiss: { bleManager.dismissShareImportStatus() })
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

/// Feedback for a share sent in from Photos/Dropbox/Files - there's no other
/// natural place to show this, since the import happens via a background
/// URL handoff from the Share Extension, not a screen the user is on.
private struct ShareImportBanner: View {
    let status: BLEManager.ShareImportStatus
    let onDismiss: () -> Void

    private var text: String {
        switch status {
        case .importing(let title): return "Importing \u{201C}\(title)\u{201D}…"
        case .succeeded(let title): return "\u{201C}\(title)\u{201D} added to MagicBox."
        case .failed(let title): return "Couldn\u{2019}t import \u{201C}\(title)\u{201D}."
        }
    }

    var body: some View {
        HStack {
            Text(text)
                .font(.caption)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color.green.opacity(0.2))
    }
}

#Preview {
    ContentView()
        .environmentObject(BLEManager())
        .environmentObject(MovieArtworkStore())
}
