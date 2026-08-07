import Foundation

enum AppMode {
    /// Normal operation: discover and control the real MagicBox device over BLE.
    case bluetooth
    /// Dev/testing only: skip Bluetooth entirely and talk to the device's plain
    /// HTTP transport (magicbox_device.views.web_service) directly over WiFi/
    /// localhost, so the UI can be built/tested without BLE hardware or a Pi.
    case directAPI
}

enum AppConfig {
    static var mode: AppMode {
        ProcessInfo.processInfo.environment["MAGICBOX_DIRECT_API"] == "1" ? .directAPI : .bluetooth
    }

    /// Base URL for the device's HTTP transport in direct-API mode. Defaults to
    /// localhost, which works from the iOS Simulator against the Docker
    /// container on the same Mac; point at a real device's LAN IP otherwise.
    static var deviceHTTPBaseURL: URL {
        let raw = ProcessInfo.processInfo.environment["MAGICBOX_DEVICE_URL"] ?? "http://localhost:8000"
        return URL(string: raw) ?? URL(string: "http://localhost:8000")!
    }

    static var tmdbAPIKey: String {
        Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String ?? ""
    }

    /// Base URL for MagicBox-web, the home media server movies are
    /// downloaded from before being pushed onward to the device. Distinct
    /// from `deviceHTTPBaseURL`, which is the Raspberry Pi device itself.
    static var magicBoxWebBaseURL: URL {
        let raw = ProcessInfo.processInfo.environment["MAGICBOX_WEB_URL"] ?? "http://localhost:8080"
        return URL(string: raw) ?? URL(string: "http://localhost:8080")!
    }
}
