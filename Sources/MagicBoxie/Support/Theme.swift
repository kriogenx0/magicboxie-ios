import SwiftUI

/// Shared colors for the streaming-service-style browse UI (dark, near-black
/// surfaces with a bold accent) - centralized so every screen agrees on the
/// same palette rather than each reaching for ad hoc grays.
extension Color {
    /// True near-black rather than iOS's default elevated dark-gray system
    /// background, closer to what makes Netflix/Apple TV-style browse UIs
    /// feel like a dedicated theater rather than a system list.
    static let appBackground = Color(red: 0.06, green: 0.06, blue: 0.07)
    static let appElevatedSurface = Color(red: 0.12, green: 0.12, blue: 0.13)
    static let appAccent = Color(red: 0.90, green: 0.16, blue: 0.16)
}
