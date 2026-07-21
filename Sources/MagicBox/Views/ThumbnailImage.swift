import SwiftUI

/// Prefers the device's own thumbnail (generated from the movie file itself);
/// falls back to a TMDB poster if the device doesn't have one or isn't
/// reachable over HTTP (e.g. plain BLE-only mode with no HTTP transport up).
struct ThumbnailImage: View {
    let primaryURL: URL?
    let fallbackURL: URL?

    var body: some View {
        if let primaryURL {
            AsyncImage(url: primaryURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    fallbackView
                case .empty:
                    Color.secondary.opacity(0.2)
                @unknown default:
                    Color.secondary.opacity(0.2)
                }
            }
        } else {
            fallbackView
        }
    }

    @ViewBuilder
    private var fallbackView: some View {
        if let fallbackURL {
            AsyncImage(url: fallbackURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.secondary.opacity(0.2)
            }
        } else {
            Color.secondary.opacity(0.2)
        }
    }
}
