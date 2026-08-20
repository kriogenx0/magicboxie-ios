import Foundation

/// Talks to the MagicBox device's plain HTTP transport (magicbox_device.views.web_service),
/// used by dev mode to exercise the real device (library scan, mpv control) over the
/// phone's WiFi/localhost connection instead of BLE.
struct DeviceMovie: Decodable {
    let id: Int
    let title: String
    let durationSeconds: Int
    let needsTranscoding: Bool

    enum CodingKeys: String, CodingKey {
        case id, title
        case durationSeconds = "duration_seconds"
        case needsTranscoding = "needs_transcoding"
    }
}

struct DeviceStatus: Decodable {
    let status: String
    let movieID: Int?
    let positionSeconds: Int

    enum CodingKeys: String, CodingKey {
        case status
        case movieID = "movie_id"
        case positionSeconds = "position_seconds"
    }
}

enum DeviceOpcode: String {
    case play, pause, stop, seek
    case selectMovie = "select_movie"
}

final class DeviceHTTPClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchMovies() async throws -> [DeviceMovie] {
        let (data, _) = try await session.data(from: baseURL.appendingPathComponent("api/movies"))
        return try JSONDecoder().decode([DeviceMovie].self, from: data)
    }

    func fetchStatus() async throws -> DeviceStatus {
        let (data, _) = try await session.data(from: baseURL.appendingPathComponent("api/status"))
        return try JSONDecoder().decode(DeviceStatus.self, from: data)
    }

    func sendCommand(_ opcode: DeviceOpcode, argument: Int? = nil) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/command"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["opcode": opcode.rawValue]
        if let argument {
            body["argument"] = argument
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await session.data(for: request)
    }

    /// Pushes a phone-fetched "official" poster (from MagicBox-web) back to the
    /// device so it can serve it to other devices that connect later, even
    /// with no internet access of their own.
    func uploadThumbnail(movieID: Int, imageData: Data) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/movies/\(movieID)/thumbnail"))
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData
        _ = try await session.data(for: request)
    }

    /// Uploads a whole video file (e.g. shared in from Photos/Dropbox/Files)
    /// so the device adds it to its library. Streams from disk rather than
    /// loading the file into memory first - these can be multi-gigabyte files.
    func uploadMovie(filename: String, fileURL: URL) async throws -> DeviceMovie {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/movies"))
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(filename, forHTTPHeaderField: "X-Filename")
        let (data, response) = try await session.upload(for: request, fromFile: fileURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(DeviceMovie.self, from: data)
    }
}
