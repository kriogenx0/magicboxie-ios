import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @EnvironmentObject private var artworkStore: MovieArtworkStore
    @EnvironmentObject private var webClient: MagicBoxWebClient
    // Owned here (above the List) so pushing/popping MovieDetailView via
    // navigationDestination never rebuilds MovieLibraryView's List, which is
    // what would happen with a .sheet - this way scroll position survives.
    // Array-based path (rather than navigationDestination(item:)) since that
    // needs iOS 17 and this project targets 16.
    @State private var path: [Movie] = []

    var body: some View {
        // TabView always draws its bar, even with a single tab - so unlike
        // the Media Library tab's live appear/disappear as
        // webClient.isAuthenticated changes, plain Movies-only stays exactly
        // as chrome-free as it was before this ever had a second
        // destination to switch to.
        if webClient.isAuthenticated {
            TabView {
                moviesTab
                    .tabItem {
                        Label("Movies", systemImage: "play.rectangle.on.rectangle")
                    }

                NavigationStack {
                    RemoteLibraryView()
                }
                .tabItem {
                    Label("Media Library", systemImage: "icloud")
                }

                NavigationStack {
                    DeviceStatusView()
                }
                .tabItem {
                    Label("Device", systemImage: "tv")
                }
            }
        } else {
            moviesTab
        }
    }

    private var moviesTab: some View {
        NavigationStack(path: $path) {
            // Just the movie list - no top bar. A floating gear button
            // (see MovieLibraryView) presents Settings as a sheet instead
            // of a dedicated tab; connection status shows inline here too
            // when there's nothing else to display.
            MovieLibraryView(path: $path)
                // .toolbar(.hidden, for: .navigationBar) rather than the
                // older .navigationBarHidden(true): the latter has a known
                // SwiftUI/UIKit quirk of also hiding sibling chrome (e.g. an
                // enclosing TabView's tab bar) since both were once tied to
                // the same UINavigationController chrome-hiding mechanism.
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Movie.self) { movie in
                    MovieDetailView(movie: movie, artwork: artworkStore.artwork(for: movie.title))
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
                        if let status = bleManager.shareImportStatus {
                            ShareImportBanner(status: status, onDismiss: { bleManager.dismissShareImportStatus() })
                        }
                    }
                }
        }
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
        .environmentObject(MagicBoxWebClient())
}
