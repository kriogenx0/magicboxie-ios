import SwiftUI

struct MovieLibraryView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @EnvironmentObject private var artworkStore: MovieArtworkStore

    @Binding var path: [Movie]
    @State private var refreshSpin = 0.0
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(MovieCategory.sections(for: bleManager.movies), id: \.category.rawValue) { section in
                        MovieShelf(
                            title: section.category.rawValue,
                            movies: section.movies,
                            onSelect: { path.append($0) }
                        )
                    }
                }
                .padding(.vertical, 16)
            }
            .refreshable {
                await refresh()
            }
            .overlay {
                // Not connected: explain why and offer a way to connect,
                // rather than just an empty screen. Connected but genuinely
                // empty: a plain, simpler message - there's no connection
                // problem to explain or retry there.
                if bleManager.connectionState != .connected {
                    ConnectionStatusView()
                } else if bleManager.movies.isEmpty {
                    Text("No movies found on the device")
                        .foregroundStyle(.secondary)
                }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 10) {
                    refreshButton
                    settingsButton
                }
                .padding(.top, 8)
                .padding(.trailing, 16)
            }

            // Keep playback controls available without adding navigation or
            // promotional chrome to the movie list itself.
            if let displayedMovie = bleManager.currentMovie {
                PlayerControlsView(movie: displayedMovie)
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showingSettings = false }
                        }
                    }
            }
        }
    }

    /// bleManager.refreshLibrary() isn't itself awaitable - the BLE read
    /// result arrives later via a delegate callback that updates
    /// bleManager.movies asynchronously, not as a direct response .refreshable
    /// can await. A short fixed delay just keeps the pull-to-refresh spinner
    /// on screen long enough for that to land in the common case (local BLE
    /// reads are near-instant) without adding continuation-based plumbing
    /// for what's a cosmetic concern, not a functional one - the list
    /// updates reactively off bleManager.movies regardless of when the
    /// spinner itself dismisses.
    private func refresh() async {
        bleManager.refreshLibrary()
        try? await Task.sleep(nanoseconds: 800_000_000)
    }

    private var refreshButton: some View {
        Button {
            bleManager.refreshLibrary()
            withAnimation(.easeInOut(duration: 0.5)) { refreshSpin += 360 }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
                .rotationEffect(.degrees(refreshSpin))
        }
    }

    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(alignment: .topTrailing) {
                    // Lightweight hint that Settings has something worth
                    // seeing (an API version mismatch) - the actual message
                    // lives in DeviceConnectionView, not here, to keep this
                    // screen free of banners.
                    if bleManager.apiCompatibility != .compatible {
                        Circle()
                            .fill(.yellow)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.appBackground, lineWidth: 1.5))
                    }
                }
        }
    }
}

private struct MovieShelf: View {
    @EnvironmentObject private var bleManager: BLEManager
    @EnvironmentObject private var artworkStore: MovieArtworkStore

    let title: String
    let movies: [Movie]
    let onSelect: (Movie) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(movies) { movie in
                        Button {
                            onSelect(movie)
                        } label: {
                            PosterCard(
                                title: movie.title,
                                primaryURL: thumbnailURL(for: movie),
                                fallbackURL: artworkStore.artwork(for: movie.title)?.posterURL,
                                isTranscoding: bleManager.transcodingMovieID == movie.id
                            )
                        }
                        .buttonStyle(.plain)
                        .task {
                            guard let artwork = await artworkStore.fetchIfNeeded(for: movie.title) else { return }
                            await bleManager.pushThumbnailToDeviceIfNeeded(movie: movie, artwork: artwork)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func thumbnailURL(for movie: Movie) -> URL? {
        let baseURL = bleManager.wifiBaseURL
            ?? (AppConfig.mode == .directAPI ? AppConfig.deviceHTTPBaseURL : nil)
        return baseURL?.appendingPathComponent("api/movies/\(movie.id)/thumbnail")
    }
}

#Preview {
    MovieLibraryView(path: .constant([]))
        .environmentObject(BLEManager())
        .environmentObject(MovieArtworkStore())
}
