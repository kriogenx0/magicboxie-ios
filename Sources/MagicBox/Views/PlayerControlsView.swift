import SwiftUI

struct PlayerControlsView: View {
    @EnvironmentObject private var bleManager: BLEManager
    let movie: Movie
    @Binding var path: [Movie]

    private var isLoading: Bool {
        bleManager.pendingMovie?.id == movie.id
    }

    var body: some View {
        VStack(spacing: 12) {
            Button {
                path.append(movie)
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
    }
}

#Preview {
    PlayerControlsView(movie: Movie(id: 0, title: "Star Wars", durationSeconds: 7620), path: .constant([]))
        .environmentObject(BLEManager())
        .environmentObject(MovieArtworkStore())
}
