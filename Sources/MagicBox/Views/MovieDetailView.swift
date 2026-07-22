import SwiftUI

struct MovieDetailView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @Environment(\.dismiss) private var dismiss
    let movie: Movie
    let artwork: TMDBMovie?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // A fixed height (rather than .aspectRatio + .frame(maxWidth:))
                // is what actually bounds this inside a ScrollView: with
                // height otherwise unconstrained, ThumbnailImage's internal
                // .fill aspect ratio has nothing to fit within and blows up
                // to an enormous cropped size instead of a sensible poster.
                // The GeometryReader (rather than .frame(maxWidth: .infinity)
                // directly on the image) is what makes the width behave -
                // reading the container's actual resolved width and applying
                // it explicitly sidesteps AsyncImage's own internal sizing
                // preferences, which otherwise bled past the screen edges.
                GeometryReader { geo in
                    ThumbnailImage(
                        primaryURL: AppConfig.deviceHTTPBaseURL.appendingPathComponent("movies/\(movie.id)/thumbnail"),
                        fallbackURL: artwork?.posterURL
                    )
                    .frame(width: geo.size.width, height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .frame(height: 320)

                Text(movie.title)
                    .font(.title2.bold())

                if movie.durationSeconds > 0 {
                    Text("\(movie.durationSeconds / 60) min")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let overview = artwork?.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.body)
                }

                HStack(spacing: 12) {
                    Button {
                        bleManager.playNow(movie)
                        dismiss()
                    } label: {
                        Label("Play Now", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        bleManager.enqueue(movie)
                        dismiss()
                    } label: {
                        Label("Add to Queue", systemImage: "text.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 8)
            }
            .padding()
        }
    }
}

#Preview {
    MovieDetailView(
        movie: Movie(id: 0, title: "Star Wars", durationSeconds: 7620),
        artwork: nil
    )
    .environmentObject(BLEManager())
}
