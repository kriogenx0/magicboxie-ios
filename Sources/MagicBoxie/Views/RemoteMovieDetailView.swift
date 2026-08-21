import SwiftUI

/// Detail screen for a MagicBoxie-web movie, reached by tapping a row in
/// RemoteLibraryView. Mirrors MovieDetailView's full-bleed backdrop/title
/// treatment, but the action here is downloading to the device rather than
/// playing - these movies don't live on the device (and can't be commanded
/// to play) until that happens.
struct RemoteMovieDetailView: View {
    let movie: RemoteMovie
    let status: RemoteLibraryView.RowStatus?
    let alreadyOnDevice: Bool
    let onDownload: () -> Void

    private let headerHeight: CGFloat = 380

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                    .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 4) {
                        if let year = movie.productionYear {
                            Text(String(year))
                        }
                        if movie.durationMinutes > 0 {
                            Text("\u{00B7} \(movie.durationMinutes) min")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if let overview = movie.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.body)
                    }

                    actionRow
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.appBackground.ignoresSafeArea())
    }

    @ViewBuilder
    private var actionRow: some View {
        switch status {
        case .downloading:
            statusLabel("Downloading\u{2026}", systemImage: "icloud.and.arrow.down")
        case .sending:
            statusLabel("Sending to device\u{2026}", systemImage: "antenna.radiowaves.left.and.right")
        case .done:
            statusLabel("On device", systemImage: "checkmark.circle.fill", color: .green)
        case .queued:
            // Re-checked live rather than trusting the stale .queued status
            // forever - see RemoteLibraryView.MovieRow's identical check.
            if alreadyOnDevice {
                statusLabel("On device", systemImage: "checkmark.circle.fill", color: .green)
            } else {
                statusLabel("Saved on phone \u{2014} will send once the device is reachable", systemImage: "clock.badge.checkmark")
            }
        case .failed:
            Button(action: onDownload) {
                Label("Download failed \u{2014} Retry", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        case nil:
            if alreadyOnDevice {
                statusLabel("Already on device", systemImage: "checkmark.circle")
            } else if movie.isReady {
                Button(action: onDownload) {
                    Label("Download to Device", systemImage: "icloud.and.arrow.down")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.appAccent)
            } else {
                statusLabel(movie.status.replacingOccurrences(of: "_", with: " ").capitalized, systemImage: "clock")
            }
        }
    }

    private func statusLabel(_ text: String, systemImage: String, color: Color = .secondary) -> some View {
        Label(text, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(color)
    }

    /// Full-bleed backdrop (falling back to the poster) with the title
    /// sitting on a bottom gradient - see MovieDetailView.header, which
    /// this mirrors exactly for the local-device equivalent screen.
    private var header: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                ThumbnailImage(primaryURL: movie.backdropURL, fallbackURL: movie.posterURL)
                    .frame(width: geo.size.width, height: headerHeight)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .clear, Color.appBackground.opacity(0.9), Color.appBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: geo.size.width, height: headerHeight)

                Text(movie.name)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .shadow(radius: 6)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }
            .frame(width: geo.size.width, height: headerHeight)
        }
        .frame(height: headerHeight)
    }
}

#Preview {
    let json = """
    {"Id":"movie-1","Name":"Star Wars","Overview":"A long time ago...",
     "ProductionYear":1977,"RunTimeTicks":76200000000,
     "MagicBoxieStatus":"ready","MagicBoxieOriginalFilename":"starwars.mp4",
     "MagicBoxieSyncEnabled":true}
    """.data(using: .utf8)!
    let movie = try! JSONDecoder().decode(RemoteMovie.self, from: json)

    return NavigationStack {
        RemoteMovieDetailView(movie: movie, status: nil, alreadyOnDevice: false, onDownload: {})
    }
}
