import Foundation
import SwiftUI

struct MovieLibraryView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @EnvironmentObject private var artworkStore: MovieArtworkStore
    @State private var searchText = ""
    @Binding var path: [Movie]

    private var filteredMovies: [Movie] {
        guard !searchText.isEmpty else { return bleManager.movies }
        return bleManager.movies.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        // Custom search field instead of .searchable(): on iOS 26 that modifier
        // docks to the bottom of the screen by default, landing below the
        // controls - the opposite of "controls always visible at the bottom".
        // Building our own guarantees PlayerControlsView stays the last,
        // fixed element regardless of how the OS likes to place search UI.
        VStack(spacing: 0) {
            SearchField(text: $searchText)
                .padding(.horizontal)
                .padding(.vertical, 8)

            List {
                ForEach(MovieCategory.sections(for: filteredMovies), id: \.category.rawValue) { section in
                    Section(section.category.rawValue) {
                        ForEach(section.movies) { movie in
                            Button {
                                path.append(movie)
                            } label: {
                                MovieRow(movie: movie, artwork: artworkStore.artwork(for: movie.title))
                                    .task {
                                        guard let artwork = await artworkStore.fetchIfNeeded(for: movie.title) else { return }
                                        await bleManager.pushThumbnailToDeviceIfNeeded(movie: movie, artwork: artwork)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if filteredMovies.isEmpty {
                    Text(bleManager.movies.isEmpty ? "No movies found on the device" : "No movies match \u{201C}\(searchText)\u{201D}")
                        .foregroundStyle(.secondary)
                }
            }

            // Prefer the just-tapped movie (shown immediately, with a loading
            // state) over the last device-confirmed one, until the device
            // confirms it - see BLEManager.pendingMovie.
            if let displayedMovie = bleManager.pendingMovie
                ?? bleManager.movies.first(where: { $0.id == bleManager.playbackState.movieID }) {
                Divider()
                PlayerControlsView(movie: displayedMovie, path: $path)
            }
        }
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search movies", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct MovieRow: View {
    let movie: Movie
    let artwork: TMDBMovie?

    var body: some View {
        HStack {
            ThumbnailImage(
                primaryURL: AppConfig.deviceHTTPBaseURL.appendingPathComponent("movies/\(movie.id)/thumbnail"),
                fallbackURL: artwork?.posterURL
            )
            .frame(width: 40, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading) {
                Text(movie.title)
                if let overview = artwork?.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if movie.durationSeconds > 0 {
                Text(formattedDuration(movie.durationSeconds))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        "\(seconds / 60) min"
    }
}

#Preview {
    MovieLibraryView(path: .constant([]))
        .environmentObject(BLEManager())
        .environmentObject(MovieArtworkStore())
}
