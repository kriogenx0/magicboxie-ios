import Foundation

/// Best-effort poster/overview lookup by title, shared by both bluetooth and
/// direct-API modes. Silently no-ops on missing key or failed match - callers
/// fall back to the plain title-only row they already render.
@MainActor
final class MovieArtworkStore: ObservableObject {
    @Published private(set) var artworkByTitle: [String: TMDBMovie] = [:]

    private var inFlightTitles: Set<String> = []
    private let client: TMDBClient

    init(client: TMDBClient = .shared) {
        self.client = client
    }

    func artwork(for title: String) -> TMDBMovie? {
        artworkByTitle[title]
    }

    /// Returns the cached/fetched match, or nil if there's no key, no match,
    /// or a fetch for this title is already in flight. Callers that need to
    /// know when a *new* match was found (e.g. to push it on to the device)
    /// should use this return value rather than polling `artwork(for:)`.
    @discardableResult
    func fetchIfNeeded(for title: String) async -> TMDBMovie? {
        if let cached = artworkByTitle[title] {
            return cached
        }
        guard !inFlightTitles.contains(title), !AppConfig.tmdbAPIKey.isEmpty else {
            return nil
        }
        inFlightTitles.insert(title)
        defer { inFlightTitles.remove(title) }

        guard let match = try? await client.searchMovie(title: title) else { return nil }
        artworkByTitle[title] = match
        return match
    }
}
