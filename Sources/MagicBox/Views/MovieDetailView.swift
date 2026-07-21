import SwiftUI

struct MovieDetailView: View {
    let movie: Movie
    let artwork: TMDBMovie?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ThumbnailImage(
                    primaryURL: AppConfig.deviceHTTPBaseURL.appendingPathComponent("movies/\(movie.id)/thumbnail"),
                    fallbackURL: artwork?.posterURL
                )
                .aspectRatio(2 / 3, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))

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
}
