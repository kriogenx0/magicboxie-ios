import Foundation

/// A movie as MagicBox-web (the home server) reports it -- decoded straight
/// from its Jellyfin-compatible /Users/{id}/Items response. Field names
/// match the wire format (see magicbox-web's items_controller.go); the
/// MagicBox*-prefixed fields are that server's own additive extensions
/// (status/progress/original filename) real Jellyfin has no concept of.
struct RemoteMovie: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let overview: String?
    let productionYear: Int?
    let runTimeTicks: Int64?
    let status: String
    let originalFilename: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case overview = "Overview"
        case productionYear = "ProductionYear"
        case runTimeTicks = "RunTimeTicks"
        case status = "MagicBoxStatus"
        case originalFilename = "MagicBoxOriginalFilename"
    }

    var isReady: Bool { status == "ready" }

    var durationMinutes: Int {
        guard let ticks = runTimeTicks else { return 0 }
        return Int(ticks / 10_000_000 / 60)
    }
}

struct RemoteItemsResponse: Decodable {
    let items: [RemoteMovie]
    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }
}
