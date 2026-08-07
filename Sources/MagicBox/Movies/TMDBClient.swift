import Foundation

struct TMDBMovie: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let overview: String
    let posterPath: String?
    let backdropPath: String?

    enum CodingKeys: String, CodingKey {
        case id, title, overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
    }

    var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\(posterPath)")
    }

    /// Wide promotional art used for the hero banner and detail-view header;
    /// falls back to nil (rather than the poster) so callers can decide
    /// their own fallback treatment for the different aspect ratio.
    var backdropURL: URL? {
        guard let backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w780\(backdropPath)")
    }
}

enum TMDBError: Error {
    case missingAPIKey
    case invalidResponse
}

private struct TMDBPage<Result: Decodable>: Decodable {
    let results: [Result]
}

final class TMDBClient {
    static let shared = TMDBClient()

    private let baseURL = URL(string: "https://api.themoviedb.org/3")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Used by dev mode to populate the library without a real device.
    func popularMovies(page: Int = 1) async throws -> [TMDBMovie] {
        let response: TMDBPage<TMDBMovie> = try await get(
            "/movie/popular",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
        return response.results
    }

    /// Used to enrich a BLE-supplied (or dev-mode) title with poster/overview.
    func searchMovie(title: String) async throws -> TMDBMovie? {
        let response: TMDBPage<TMDBMovie> = try await get(
            "/search/movie",
            query: [URLQueryItem(name: "query", value: title)]
        )
        return response.results.first
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        guard !AppConfig.tmdbAPIKey.isEmpty else { throw TMDBError.missingAPIKey }

        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw TMDBError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "api_key", value: AppConfig.tmdbAPIKey)] + query
        guard let url = components.url else { throw TMDBError.invalidResponse }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TMDBError.invalidResponse
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
