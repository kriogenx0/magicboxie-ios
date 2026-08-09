import Foundation

struct Movie: Identifiable, Hashable {
    let id: Int
    let title: String
    let durationSeconds: Int
    /// Whether the device still needs to (re-)encode this movie into a
    /// profile this hardware can decode smoothly - only known when the
    /// library came from the device's HTTP API (see DeviceMovie); BLE's
    /// tight per-characteristic byte budget doesn't carry this, so it
    /// defaults to false there rather than showing a badge with no signal
    /// behind it.
    let needsTranscoding: Bool

    init(id: Int, title: String, durationSeconds: Int, needsTranscoding: Bool = false) {
        self.id = id
        self.title = title
        self.durationSeconds = durationSeconds
        self.needsTranscoding = needsTranscoding
    }
}
