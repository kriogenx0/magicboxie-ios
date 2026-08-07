import SwiftUI

/// A single poster in a Netflix-style horizontal shelf: artwork first, with
/// the title kept small underneath rather than overlaid - the library this
/// browses can be entirely offline (BLE-only, zero TMDB key), where artwork
/// is often just the generic clapperboard, so the title can't live only as
/// text baked into a promotional image the way real Netflix rows get away with.
struct PosterCard: View {
    let title: String
    let primaryURL: URL?
    let fallbackURL: URL?

    static let width: CGFloat = 126

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailImage(primaryURL: primaryURL, fallbackURL: fallbackURL)
                .frame(width: Self.width, height: Self.width * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.5), radius: 5, y: 3)

            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .frame(width: Self.width, alignment: .leading)
        }
    }
}
