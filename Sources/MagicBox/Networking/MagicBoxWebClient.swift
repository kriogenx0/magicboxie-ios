import Foundation

private struct AuthResponse: Decodable {
    let accessToken: String
    enum CodingKeys: String, CodingKey {
        case accessToken = "AccessToken"
    }
}

/// Talks to MagicBox-web (the home media server), speaking its
/// Jellyfin-compatible REST API: login, list movies, and download a movie's
/// bytes to disk so it can be handed off to DeviceHTTPClient.uploadMovie
/// for the push-to-device leg. Distinct from DeviceHTTPClient, which talks
/// to the Raspberry Pi device itself.
@MainActor
final class MagicBoxWebClient: ObservableObject {
    @Published private(set) var isAuthenticated: Bool
    @Published private(set) var movies: [RemoteMovie] = []
    @Published var lastError: String?

    private let baseURL: URL
    private let session: URLSession
    private static let tokenKey = "magicbox_web_token"

    private var token: String? {
        didSet {
            if let token {
                KeychainStore.set(token, forKey: Self.tokenKey)
            } else {
                KeychainStore.remove(Self.tokenKey)
            }
        }
    }

    init(baseURL: URL = AppConfig.magicBoxWebBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        let storedToken = KeychainStore.get(Self.tokenKey)
        self.token = storedToken
        self.isAuthenticated = storedToken != nil
    }

    func login(password: String) async {
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("Users/AuthenticateByName"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "Username": "magicbox-ios",
                "Pw": password,
            ])

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                lastError = "Incorrect password"
                return
            }
            let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
            token = auth.accessToken
            isAuthenticated = true
            lastError = nil
        } catch {
            lastError = "Couldn't reach MagicBox-web at \(baseURL.absoluteString)"
        }
    }

    func logout() {
        token = nil
        isAuthenticated = false
        movies = []
    }

    func fetchMovies() async {
        guard let token else { return }

        var components = URLComponents(url: baseURL.appendingPathComponent("Users/1/Items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "IncludeItemTypes", value: "Movie"),
            URLQueryItem(name: "Recursive", value: "true"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                logout()
                return
            }
            let decoded = try JSONDecoder().decode(RemoteItemsResponse.self, from: data)
            movies = decoded.items
            lastError = nil
        } catch {
            lastError = "Couldn't load movies from MagicBox-web"
        }
    }

    /// Downloads a movie to a local temp file, streaming to disk rather than
    /// buffering in memory -- these can be multi-gigabyte files. The caller
    /// (see RemoteLibraryView) hands the resulting URL to
    /// BLEManager.uploadMovieIfNeeded to push it onward to the device.
    func downloadMovie(_ movie: RemoteMovie) async throws -> URL {
        guard let token else { throw URLError(.userAuthenticationRequired) }

        var components = URLComponents(url: baseURL.appendingPathComponent("Videos/\(movie.id)/stream"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "static", value: "true")]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (tempURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let ext = (movie.originalFilename as NSString).pathExtension
        let filename = movie.name.replacingOccurrences(of: "/", with: "-") + (ext.isEmpty ? ".mp4" : ".\(ext)")
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }
}
