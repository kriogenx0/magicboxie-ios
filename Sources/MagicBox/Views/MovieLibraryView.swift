import SwiftUI

struct MovieLibraryView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @EnvironmentObject private var artworkStore: MovieArtworkStore

    @Binding var path: [Movie]

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
            .overlay {
                if bleManager.movies.isEmpty {
                    Text(emptyMessage)
                        .foregroundStyle(.secondary)
                }
            }

            // Keep playback controls available without adding navigation or
            // promotional chrome to the movie list itself.
            if let displayedMovie = bleManager.currentMovie {
                PlayerControlsView(movie: displayedMovie)
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    private var emptyMessage: String {
        bleManager.connectionState == .connected
            ? "No movies found on the device"
            : "Connect to MagicBox to load movies"
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
                                fallbackURL: artworkStore.artwork(for: movie.title)?.posterURL
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
