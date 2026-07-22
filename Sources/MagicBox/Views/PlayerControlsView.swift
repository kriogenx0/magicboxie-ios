import SwiftUI

struct PlayerControlsView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @EnvironmentObject private var artworkStore: MovieArtworkStore
    let movie: Movie
    @Binding var path: [Movie]

    private var isLoading: Bool {
        bleManager.pendingMovie?.id == movie.id
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                path.append(movie)
            } label: {
                HStack(spacing: 12) {
                    ThumbnailImage(
                        primaryURL: AppConfig.deviceHTTPBaseURL.appendingPathComponent("movies/\(movie.id)/thumbnail"),
                        fallbackURL: artworkStore.artwork(for: movie.title)?.posterURL
                    )
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text(movie.title)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            if isLoading {
                ProgressView()
            } else {
                Button {
                    if bleManager.playbackState.status == .playing {
                        bleManager.pause()
                    } else {
                        bleManager.play()
                    }
                } label: {
                    Image(systemName: bleManager.playbackState.status == .playing ? "pause.fill" : "play.fill")
                }
            }

            if !bleManager.queue.isEmpty {
                Button {
                    bleManager.skipToNext()
                } label: {
                    Image(systemName: "forward.end.fill")
                }
            }
        }
        .font(.system(size: 22))
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

#Preview {
    PlayerControlsView(movie: Movie(id: 0, title: "Star Wars", durationSeconds: 7620), path: .constant([]))
        .environmentObject(BLEManager())
        .environmentObject(MovieArtworkStore())
}
