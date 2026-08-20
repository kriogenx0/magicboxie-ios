import SwiftUI

@main
struct MagicBoxApp: App {
    @StateObject private var bleManager = BLEManager()
    @StateObject private var artworkStore = MovieArtworkStore()
    // Shared so ContentView can show/hide the Media Library tab based on
    // the same login state RemoteLibraryView uses - a second, independent
    // MagicBoxWebClient (as MovieArtworkStore keeps internally) would work
    // too (Keychain keeps their tokens in sync) but would double up on
    // fetchMovies() calls and lag a beat behind on isAuthenticated.
    @StateObject private var webClient = MagicBoxWebClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleManager)
                .environmentObject(artworkStore)
                .environmentObject(webClient)
                .preferredColorScheme(.dark)
                .tint(.appAccent)
                .onOpenURL { url in
                    guard url == SharedUploadStore.importURL else { return }
                    Task {
                        for fileURL in SharedUploadStore.pendingUploadURLs() {
                            await bleManager.uploadMovieIfNeeded(fileURL: fileURL)
                            SharedUploadStore.remove(fileURL)
                        }
                    }
                }
        }
    }
}
