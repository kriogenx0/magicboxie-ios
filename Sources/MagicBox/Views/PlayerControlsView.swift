import SwiftUI

struct PlayerControlsView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @EnvironmentObject private var artworkStore: MovieArtworkStore
    let movie: Movie
    @State private var isQueueExpanded = false

    private var isLoading: Bool {
        bleManager.pendingMovie?.id == movie.id
    }

    private let queueRowHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    guard !bleManager.queue.isEmpty else { return }
                    withAnimation {
                        isQueueExpanded.toggle()
                    }
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

            // Tapping the now-playing row above toggles this open so the
            // queue can be reviewed and trimmed without leaving the library
            // screen. A List (rather than a custom stack) is what gets
            // swipe-to-remove for free via .swipeActions.
            if isQueueExpanded, !bleManager.queue.isEmpty {
                List {
                    ForEach(bleManager.queue) { queuedMovie in
                        Text(queuedMovie.title)
                            .font(.subheadline)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    bleManager.removeFromQueue(queuedMovie)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .frame(height: queueRowHeight * CGFloat(min(bleManager.queue.count, 4)))
            }
        }
    }
}

#Preview {
    PlayerControlsView(movie: Movie(id: 0, title: "Star Wars", durationSeconds: 7620))
        .environmentObject(BLEManager())
        .environmentObject(MovieArtworkStore())
}
