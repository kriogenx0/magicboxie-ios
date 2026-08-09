import SwiftUI

struct PlayerControlsView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @EnvironmentObject private var artworkStore: MovieArtworkStore
    let movie: Movie
    @State private var showingNowPlaying = false

    private var isLoading: Bool {
        bleManager.pendingMovie?.id == movie.id
    }

    var body: some View {
        HStack(spacing: 12) {
            // Opens the full player (progress bar/scrub, ±15s, previous,
            // and the queue) - there's no room for any of that in this
            // compact bar.
            Button {
                showingNowPlaying = true
            } label: {
                HStack(spacing: 12) {
                    ThumbnailImage(
                        primaryURL: AppConfig.deviceHTTPBaseURL.appendingPathComponent("api/movies/\(movie.id)/thumbnail"),
                        fallbackURL: artworkStore.artwork(for: movie.title)?.posterURL
                    )
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("NOW PLAYING")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(Color.appAccent)
                        Text(movie.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            if isLoading {
                ProgressView()
            } else {
                Button {
                    switch bleManager.playbackState.status {
                    case .playing:
                        bleManager.pause()
                    case .paused:
                        bleManager.play()
                    case .stopped:
                        // Nothing's loaded on the device once truly
                        // stopped (e.g. this movie reached its natural
                        // end) - a bare play() would be a no-op, so
                        // re-select and start it again from scratch.
                        bleManager.playNow(movie)
                    }
                } label: {
                    Image(systemName: bleManager.playbackState.status == .playing ? "pause.fill" : "play.fill")
                }
                .tint(.appAccent)
            }

            if !bleManager.queue.isEmpty {
                Button {
                    bleManager.skipToNext()
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .tint(.primary)
            }
        }
        .font(.system(size: 22))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .background(Color.appElevatedSurface.opacity(0.92))
        .fullScreenCover(isPresented: $showingNowPlaying) {
            NowPlayingView(movie: movie)
                .environmentObject(bleManager)
                .environmentObject(artworkStore)
        }
    }
}

#Preview {
    PlayerControlsView(movie: Movie(id: 0, title: "Star Wars", durationSeconds: 7620))
        .environmentObject(BLEManager())
        .environmentObject(MovieArtworkStore())
}
