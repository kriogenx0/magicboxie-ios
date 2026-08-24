import ImageIO
import SwiftUI
import UIKit

/// Prefers the device's own thumbnail (generated from the movie file itself);
/// falls back to a MagicBoxie-web poster if the device doesn't have one or
/// isn't reachable over HTTP (e.g. plain BLE-only mode with no HTTP
/// transport up).
struct ThumbnailImage: View {
    let primaryURL: URL?
    let fallbackURL: URL?
    /// Longest edge to decode to, in pixels - callers displaying this larger
    /// (e.g. full-width detail headers) pass a bigger value. Deliberately
    /// downsampled via ImageIO rather than left to AsyncImage's default
    /// full-resolution decode: magicboxie-web serves posters straight from
    /// disk with no server-side resizing (often TMDB-original quality,
    /// several megapixels each), and decoding many of those at once just to
    /// render a handful of list-row-sized thumbnails was observed to make
    /// the whole phone sluggish, not just this screen.
    var maxPixelSize: CGFloat = 600

    @State private var image: UIImage?
    @State private var primaryFailed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else if primaryURL == nil || primaryFailed {
                fallbackView
            } else {
                DefaultArtwork()
            }
        }
        .task(id: primaryURL) {
            image = nil
            primaryFailed = false
            guard let primaryURL else { return }
            if let loaded = await ImageDownsampler.shared.image(for: primaryURL, maxPixelSize: maxPixelSize) {
                image = loaded
            } else {
                primaryFailed = true
            }
        }
    }

    @ViewBuilder
    private var fallbackView: some View {
        if let fallbackURL {
            DownsampledFallbackImage(url: fallbackURL, maxPixelSize: maxPixelSize)
        } else {
            DefaultArtwork()
        }
    }
}

/// The fallbackURL half of ThumbnailImage, split out into its own view so
/// its @State (a second, independent load) only exists when there's
/// actually a fallback to load.
private struct DownsampledFallbackImage: View {
    let url: URL
    let maxPixelSize: CGFloat

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                DefaultArtwork()
            }
        }
        .task(id: url) {
            image = await ImageDownsampler.shared.image(for: url, maxPixelSize: maxPixelSize)
        }
    }
}

/// Shown while a real thumbnail/poster is loading, and whenever neither is
/// available at all - a generic clapperboard reads as "a movie" at a
/// glance, rather than a blank box.
private struct DefaultArtwork: View {
    var body: some View {
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

/// Fetches image data over the network and decodes it downsampled to at
/// most `maxPixelSize` on its longest edge via ImageIO, instead of the full
/// original resolution - see ThumbnailImage's own doc comment for why that
/// matters here. Cached in memory by URL+size, since SwiftUI recreates List
/// rows as they scroll on/off screen and would otherwise redo the same
/// decode repeatedly during a single scroll session.
final class ImageDownsampler {
    static let shared = ImageDownsampler()

    private let cache = NSCache<NSString, UIImage>()

    func image(for url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        let key = "\(url.absoluteString)@\(Int(maxPixelSize))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let downsampled = Self.downsample(data: data, maxPixelSize: maxPixelSize) else {
            return nil
        }
        cache.setObject(downsampled, forKey: key)
        return downsampled
    }

    private static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
