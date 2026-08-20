import Foundation

/// A magicboxie-device Pi as MagicBox-web's GET /api/devices reports it -
/// see items_controller.go's ListDevices. Purely for visibility (confirming
/// a device really is checking in), not access control - see models.Device's
/// own doc comment on the server.
struct RemoteDevice: Decodable, Identifiable, Hashable {
    let id: Int
    let deviceID: String
    /// Kept as the raw wire string rather than decoded straight to Date:
    /// Go's encoding/json emits RFC3339 with fractional seconds, which
    /// Foundation's built-in .iso8601 JSONDecoder strategy doesn't parse -
    /// lastSeenAt below tries fractional seconds first, then falls back.
    private let lastSeenAtRaw: String

    enum CodingKeys: String, CodingKey {
        case id
        case deviceID = "device_id"
        case lastSeenAtRaw = "last_seen_at"
    }

    var lastSeenAt: Date? {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractionalSeconds.date(from: lastSeenAtRaw) {
            return date
        }
        return ISO8601DateFormatter().date(from: lastSeenAtRaw)
    }
}

struct RemoteDevicesResponse: Decodable {
    let devices: [RemoteDevice]
}
