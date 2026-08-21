import Foundation

enum PlaybackStatus: UInt8 {
    case stopped = 0x00
    case playing = 0x01
    case paused = 0x02

    /// Maps the device's HTTP status strings ("stopped"/"playing"/"paused").
    init(deviceString: String) {
        switch deviceString {
        case "playing": self = .playing
        case "paused": self = .paused
        default: self = .stopped
        }
    }
}

struct PlaybackState {
    var status: PlaybackStatus
    var movieID: Int?
    var positionSeconds: Int

    static let idle = PlaybackState(status: .stopped, movieID: nil, positionSeconds: 0)
}
