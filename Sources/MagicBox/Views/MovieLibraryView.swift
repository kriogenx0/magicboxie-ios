import Foundation
import SwiftUI

private struct ListPullOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct MovieLibraryView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @EnvironmentObject private var artworkStore: MovieArtworkStore
    @State private var searchText = ""
    @State private var isSearchRevealed = false
    // The list's first layout/bounce pass can transiently report a large
    // pull offset before it settles, which would otherwise trip the reveal
    // threshold immediately on load with no actual pull from the user.
    // Waiting for an exact resting (~0) reading proved unreliable - it's not
    // guaranteed to land before a spurious large reading does - so instead
    // just ignore all offset readings for a brief window after the view
    // appears, regardless of their value.
    @State private var appearedAt: Date?

    // How far past the top the user has to pull before the search field
    // pops in - roughly matches the feel of a pull-to-refresh threshold.
    private let revealThreshold: CGFloat = 45

    @Binding var path: [Movie]

    private var filteredMovies: [Movie] {
        guard !searchText.isEmpty else { return bleManager.movies }
        return bleManager.movies.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var pullOffsetTracker: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: ListPullOffsetKey.self,
                value: geo.frame(in: .named("movieList")).minY
            )
        }
    }

    var body: some View {
        // Custom search field instead of .searchable(): on iOS 26 that modifier
        // docks to the bottom of the screen by default, landing below the
        // controls - the opposite of "controls always visible at the bottom".
        // Building our own guarantees PlayerControlsView stays the last,
        // fixed element regardless of how the OS likes to place search UI.
        //
        // Hidden by default; revealed by swiping down past the top of the
        // list. Tracks the list's actual overscroll amount (via a
        // GeometryReader + PreferenceKey on its first row) rather than a
        // one-shot programmatic scroll, since the latter proved to land at
        // an imprecise offset when combined with this screen's safe-area
        // banners.
        VStack(spacing: 0) {
            if isSearchRevealed {
                SearchField(text: $searchText)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            List {
                ForEach(Array(MovieCategory.sections(for: filteredMovies).enumerated()), id: \.element.category.rawValue) { index, section in
                    Section {
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
                    } header: {
                        // The pull-offset tracker rides on the very first
                        // section's header (rather than a standalone row)
                        // since an untitled row/section ahead of a titled one
                        // gets List's own phantom-header spacing reserved for
                        // it - which showed up as a large, permanent empty
                        // gap above "Feature Films" regardless of scroll state.
                        Text(section.category.rawValue)
                            .background(index == 0 ? AnyView(pullOffsetTracker) : AnyView(EmptyView()))
                    }
                }
            }
            .listStyle(.plain)
            .coordinateSpace(name: "movieList")
            .onAppear {
                if appearedAt == nil {
                    appearedAt = Date()
                }
            }
            .onPreferenceChange(ListPullOffsetKey.self) { offset in
                guard let appearedAt, Date().timeIntervalSince(appearedAt) > 0.5 else { return }
                guard !isSearchRevealed, offset > revealThreshold else { return }
                withAnimation {
                    isSearchRevealed = true
                }
            }
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
