import Foundation

struct Movie: Identifiable, Hashable {
    let id: Int
    let title: String
    let durationSeconds: Int
}
