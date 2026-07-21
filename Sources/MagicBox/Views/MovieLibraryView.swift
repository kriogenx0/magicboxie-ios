import Foundation
import SwiftUI

struct MovieLibraryView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @EnvironmentObject private var artworkStore: MovieArtworkStore
    @State private var searchText = ""

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
                                bleManager.selectMovie(movie)
                                bleManager.play()
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

            if let currentMovie = bleManager.movies.first(where: { $0.id == bleManager.playbackState.movieID }) {
                Divider()
                PlayerControlsView(movie: currentMovie)
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
    MovieLibraryView()
        .environmentObject(BLEManager())
        .environmentObject(MovieArtworkStore())
}
