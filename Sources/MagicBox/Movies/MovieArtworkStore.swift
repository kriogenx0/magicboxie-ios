import Foundation

/// Best-effort poster/overview lookup by title, shared by both bluetooth and
/// direct-API modes. Sourced from MagicBox-web (the home server) rather than
/// TMDB directly - magicbox-web already does its own TMDB matching/caching
/// server-side (see its internal/services/tmdb), so this is just reading
/// that already-enriched data over the LAN. Silently no-ops when not logged
/// in to MagicBox-web or on a failed/empty fetch - callers fall back to the
/// plain title-only row they already render.
@MainActor
final class MovieArtworkStore: ObservableObject {
    @Published private(set) var artworkByTitle: [String: RemoteMovie] = [:]

    private var isFetchingLibrary = false
    private let client: MagicBoxWebClient

    init(client: MagicBoxWebClient? = nil) {
        self.client = client ?? MagicBoxWebClient()
    }

    func artwork(for title: String) -> RemoteMovie? {
        artworkByTitle[title]
    }

    /// Returns the cached/fetched match, or nil if there's no logged-in
    /// MagicBox-web session, no match, or the library fetch is already in
    /// flight. Callers that need to know when a *new* match was found (e.g.
    /// to push it on to the device) should use this return value rather
    /// than polling `artwork(for:)`.
    @discardableResult
    func fetchIfNeeded(for title: String) async -> RemoteMovie? {
        if let cached = artworkByTitle[title] {
            return cached
        }
        guard client.isAuthenticated else { return nil }

        // One bulk fetch serves every title, rather than a per-title
        // request the way TMDB's search endpoint needed - so this just
        // ensures the whole library's been pulled at least once (retrying
        // on a later call if it came back empty, e.g. from a transient
        // network failure) instead of tracking per-title in-flight state.
        if client.movies.isEmpty, !isFetchingLibrary {
            isFetchingLibrary = true
            await client.fetchMovies()
            isFetchingLibrary = false
        }

        guard let match = client.movies.first(where: { $0.name == title }) else { return nil }
        artworkByTitle[title] = match
        return match
    }
}
