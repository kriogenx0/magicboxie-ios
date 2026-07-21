import SwiftUI

struct PlayerControlsView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @EnvironmentObject private var artworkStore: MovieArtworkStore
    let movie: Movie
    @State private var showingDetail = false

    private var isLoading: Bool {
        bleManager.pendingMovie?.id == movie.id
    }

    var body: some View {
        VStack(spacing: 12) {
            Button {
                showingDetail = true
            } label: {
                Text(movie.title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            HStack(spacing: 40) {
                Button {
                    bleManager.stop()
                } label: {
                    Image(systemName: "stop.fill")
                }

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
            }
            .font(.system(size: 32))

            if !bleManager.queue.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Up Next")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(bleManager.queue) { queuedMovie in
                        Text(queuedMovie.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }

            Spacer(minLength: 0).frame(height: 20)
        }
        .padding(.top, 12)
        .sheet(isPresented: $showingDetail) {
            MovieDetailView(movie: movie, artwork: artworkStore.artwork(for: movie.title))
        }
    }
}

#Preview {
    PlayerControlsView(movie: Movie(id: 0, title: "Star Wars", durationSeconds: 7620))
        .environmentObject(BLEManager())
        .environmentObject(MovieArtworkStore())
}
