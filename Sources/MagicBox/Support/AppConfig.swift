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
        #if DEBUG
        ProcessInfo.processInfo.environment["MAGICBOX_DIRECT_API"] == "1" ? .directAPI : .bluetooth
        #else
        // Direct API exists only for simulator/development workflows. A
        // distributed application must always discover and control the real
        // MagicBox rather than attempting to contact a developer's server.
        .bluetooth
        #endif
    }

    /// Base URL for the device's HTTP transport in direct-API mode.
    ///
    /// Order of resolution:
    /// 1. `MAGICBOX_DEVICE_URL`
    /// 2. network-hosted development server at `magicboxie-device.local:8000`
    /// 3. fallback to `localhost:8000` for simulator-local server testing.
    static var deviceHTTPBaseURL: URL {
        if let raw = ProcessInfo.processInfo.environment["MAGICBOX_DEVICE_URL"],
           let url = URL(string: raw) {
            return url
        }

        let defaultURLs = [
            "http://magicboxie-device.local:8000",
            "http://magicboxie-device:8000",
            "http://localhost:8000",
        ]

        for candidate in defaultURLs {
            if let url = URL(string: candidate) {
                return url
            }
        }

        return URL(string: "http://localhost:8000")!
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
