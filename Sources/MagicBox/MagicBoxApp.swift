import SwiftUI

@main
struct MagicBoxApp: App {
    @StateObject private var bleManager = BLEManager()
    @StateObject private var artworkStore = MovieArtworkStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleManager)
                .environmentObject(artworkStore)
                .preferredColorScheme(.dark)
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
