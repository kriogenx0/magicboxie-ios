import SwiftUI

struct PlayerControlsView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @EnvironmentObject private var artworkStore: MovieArtworkStore
    let movie: Movie
    @State private var showingDetail = false

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
            .font(.system(size: 32))
            .padding(.bottom, 20)
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
