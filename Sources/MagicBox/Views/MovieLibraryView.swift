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
    // The scroll view's first layout/bounce pass can transiently report a
    // large pull offset before it settles, which would otherwise trip the
    // reveal threshold immediately on load with no actual pull from the
    // user. Waiting for an exact resting (~0) reading proved unreliable -
    // it's not guaranteed to land before a spurious large reading does - so
    // instead just ignore all offset readings for a brief window after the
    // view appears, regardless of their value.
    @State private var appearedAt: Date?

    // How far past the top the user has to pull before the search field
    // pops in - roughly matches the feel of a pull-to-refresh threshold.
    private let revealThreshold: CGFloat = 45

    @Binding var path: [Movie]

    private var filteredMovies: [Movie] {
        guard !searchText.isEmpty else { return bleManager.movies }
        return bleManager.movies.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    /// The first movie in the first non-empty category (Feature Films when
    /// there is one) - a simple, offline-friendly stand-in for "editorially
    /// featured" since there's no watch-history or trending signal to rank by.
    private var heroMovie: Movie? {
        MovieCategory.sections(for: bleManager.movies).first?.movies.first
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
        // content (tracked via a GeometryReader + PreferenceKey on a marker
        // at the very top of the scroll view) rather than a one-shot
        // programmatic scroll, since the latter proved to land at an
        // imprecise offset when combined with this screen's safe-area banners.
        VStack(spacing: 0) {
            BrowseHeader(
                isSearching: isSearchRevealed,
                onSearch: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSearchRevealed.toggle()
                        if !isSearchRevealed { searchText = "" }
                    }
                }
            )

            if isSearchRevealed {
                SearchField(text: $searchText)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView {
                Color.clear.frame(height: 0).background(pullOffsetTracker)

                LazyVStack(alignment: .leading, spacing: 30) {
                    if searchText.isEmpty, let heroMovie {
                        HeroBanner(
                            movie: heroMovie,
                            artwork: artworkStore.artwork(for: heroMovie.title),
                            onPlay: { bleManager.playNow(heroMovie) },
                            onAddToQueue: { bleManager.enqueue(heroMovie) },
                            onMoreInfo: { path.append(heroMovie) }
                        )
                        .task {
                            guard let artwork = await artworkStore.fetchIfNeeded(for: heroMovie.title) else { return }
                            await bleManager.pushThumbnailToDeviceIfNeeded(movie: heroMovie, artwork: artwork)
                        }
                    }

                    ForEach(MovieCategory.sections(for: filteredMovies), id: \.category.rawValue) { section in
                        MovieShelf(
                            title: section.category.rawValue,
                            movies: section.movies,
                            onSelect: { path.append($0) }
                        )
                    }
                }
                .padding(.bottom, 12)
            }
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
            // currentMovie covers both the just-tapped movie (shown
            // immediately, with a loading state, before the device confirms
            // it - see BLEManager.pendingMovie) and stays put once a movie
            // reaches its natural end, rather than disappearing just because
            // the device now reports "stopped".
            if let displayedMovie = bleManager.currentMovie {
                PlayerControlsView(movie: displayedMovie)
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
    }
}

private struct BrowseHeader: View {
    let isSearching: Bool
    let onSearch: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Image("MBMark")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityLabel("MagicBox")

            Spacer()

            Text("Home")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Text("Movies")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))

            Button(action: onSearch) {
                Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
        .padding(.leading, 16)
        // Leave room for ContentView's cloud-library action.
        .padding(.trailing, 58)
        .padding(.vertical, 10)
        .background(Color.appBackground.opacity(0.96))
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
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// One horizontal, poster-first row of movies under a bold section title -
/// the Netflix/Apple TV "shelf" that replaces the old flat, plain-text List.
private struct MovieShelf: View {
    @EnvironmentObject private var bleManager: BLEManager
    @EnvironmentObject private var artworkStore: MovieArtworkStore

    let title: String
    let movies: [Movie]
    let onSelect: (Movie) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.65))
            }
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 9) {
                    ForEach(movies) { movie in
                        Button {
                            onSelect(movie)
                        } label: {
                            PosterCard(
                                title: movie.title,
                                primaryURL: AppConfig.deviceHTTPBaseURL.appendingPathComponent("api/movies/\(movie.id)/thumbnail"),
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
                .padding(.horizontal)
            }
        }
    }
}

/// Full-bleed backdrop for the featured movie, with a bottom gradient the
/// title/buttons sit on and that fades the image into the shelves below -
/// the same visual language Netflix/Apple TV use to open a browse screen.
private struct HeroBanner: View {
    let movie: Movie
    let artwork: TMDBMovie?
    let onPlay: () -> Void
    let onAddToQueue: () -> Void
    let onMoreInfo: () -> Void

    private let height: CGFloat = 500

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                ThumbnailImage(
                    primaryURL: artwork?.backdropURL
                        ?? AppConfig.deviceHTTPBaseURL.appendingPathComponent("api/movies/\(movie.id)/thumbnail"),
                    fallbackURL: artwork?.posterURL
                )
                .frame(width: geo.size.width, height: height)
                .clipped()

                LinearGradient(
                    colors: [.black.opacity(0.12), .clear, Color.appBackground.opacity(0.55), Color.appBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: geo.size.width, height: height)

                VStack(spacing: 13) {
                    Text("FEATURED")
                        .font(.caption2.weight(.heavy))
                        .tracking(2.4)
                        .foregroundStyle(.white.opacity(0.82))

                    Text(movie.title)
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .shadow(radius: 6)

                    if let overview = artwork?.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }

                    HStack(alignment: .center, spacing: 28) {
                        HeroAction(title: "My List", systemImage: "plus", action: onAddToQueue)

                        Button(action: onPlay) {
                            Label("Play", systemImage: "play.fill")
                                .font(.headline.weight(.bold))
                                .padding(.horizontal, 22)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(.black)

                        HeroAction(title: "Info", systemImage: "info.circle", action: onMoreInfo)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            }
            .frame(width: geo.size.width, height: height)
        }
        .frame(height: height)
    }
}

private struct HeroAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 21, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .frame(minWidth: 48)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}

#Preview {
    MovieLibraryView(path: .constant([]))
        .environmentObject(BLEManager())
        .environmentObject(MovieArtworkStore())
}
