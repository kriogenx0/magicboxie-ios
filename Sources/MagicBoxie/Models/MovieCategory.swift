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
}
