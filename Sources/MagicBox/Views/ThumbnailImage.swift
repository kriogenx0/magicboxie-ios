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
                    defaultArtwork
                @unknown default:
                    defaultArtwork
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
                defaultArtwork
            }
        } else {
            defaultArtwork
        }
    }

    /// Shown while a real thumbnail/poster is loading, and whenever neither
    /// is available at all - a generic clapperboard reads as "a movie" at a
    /// glance, rather than a blank box.
    private var defaultArtwork: some View {
        Color.secondary.opacity(0.2)
            .overlay {
                Image("Clapperboard")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
    }
}
