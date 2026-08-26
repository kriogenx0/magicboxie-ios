import Foundation

/// Groups the flat device library into Apple TV-style sections. Classified by
/// duration rather than MagicBoxie-web's genre data on purpose: duration comes
/// straight from the device's own ffprobe scan and works with zero internet
/// access, which matters a lot for a car deployment that may never have
/// connectivity to the home server.
enum MovieCategory: String, CaseIterable {
    case featureFilms = "Feature Films"
    case tvShows = "TV Shows"
    case clips = "Clips & Other"

    static func categorize(_ movie: Movie) -> MovieCategory {
        switch movie.durationSeconds {
        case 3600...: return .featureFilms
        case 900..<3600: return .tvShows
        default: return .clips
        }
    }

    /// Groups and orders movies into non-empty sections, Feature Films first,
    /// Clips & Other last - each section alphabetical by title
    /// (localizedStandardCompare: the same "ignore case, treat digit runs
    /// numerically" ordering Finder uses, so "2001" sorts before "20,000
    /// Leagues" the way a person would expect rather than by raw character
    /// code). The device sends movies in whatever order its own directory
    /// scan produced, which isn't guaranteed to match this.
    static func sections(for movies: [Movie]) -> [(category: MovieCategory, movies: [Movie])] {
        allCases.compactMap { category in
            let matches = movies
                .filter { categorize($0) == category }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return matches.isEmpty ? nil : (category, matches)
        }
    }

    /// Genre-based rows, additive to (not replacing) the duration-based
    /// sections above - unlike those, a movie can land in more than one
    /// row here (a kids' comedy shows up under both "Kids" and "Comedy"),
    /// the same way Netflix's own genre rows overlap. Sourced from
    /// MagicBoxie-web's TMDB-matched data (see RemoteMovie.genreNames),
    /// cached in memory for the session (see MovieArtworkStore) rather
    /// than looked up fresh - so this only ever reflects whatever's
    /// already been fetched. A movie with no cached genre (offline, or
    /// MagicBoxie-web was never reached this session) simply doesn't
    /// appear in any genre row - it's still findable in the duration-based
    /// ones above, which work with zero internet access by design.
    static func genreSections(for movies: [Movie], genres: (Movie) -> [String]) -> [(genre: String, movies: [Movie])] {
        var moviesByGenre: [String: [Movie]] = [:]
        for movie in movies {
            for genre in genres(movie) {
                moviesByGenre[genre, default: []].append(movie)
            }
        }
        return moviesByGenre.keys.sorted().map { genre in
            let sorted = moviesByGenre[genre]!.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return (genre, sorted)
        }
    }
}
