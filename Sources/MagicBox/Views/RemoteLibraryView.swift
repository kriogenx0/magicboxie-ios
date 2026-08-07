import SwiftUI

/// Browse movies on MagicBox-web (the home server) and download them
/// straight to the device: a two-hop flow (server -> phone -> device) that
/// reuses BLEManager.uploadMovieIfNeeded for the second hop, the same path
/// the Share Extension already uses.
struct RemoteLibraryView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @StateObject private var webClient = MagicBoxWebClient()

    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var isRefreshing = false
    @State private var rowStatus: [String: RowStatus] = [:]

    private enum RowStatus: Equatable {
        case downloading
        case sending
        case done
        case failed
    }

    var body: some View {
        Group {
            if webClient.isAuthenticated {
                libraryList
            } else {
                loginForm
            }
        }
        .navigationTitle("Cloud Library")
        .task {
            if webClient.isAuthenticated {
                await refresh()
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    private var loginForm: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    Image("MBMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityLabel("MagicBox")
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section {
                SecureField("MagicBox-web password", text: $password)
                    .textContentType(.password)
                Button {
                    Task {
                        isLoggingIn = true
                        await webClient.login(password: password)
                        isLoggingIn = false
                        if webClient.isAuthenticated {
                            password = ""
                            await refresh()
                        }
                    }
                } label: {
                    if isLoggingIn {
                        ProgressView()
                    } else {
                        Text("Connect")
                    }
                }
                .tint(.appAccent)
                .disabled(password.isEmpty || isLoggingIn)
            } footer: {
                if let error = webClient.lastError {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground.ignoresSafeArea())
    }

    private var libraryList: some View {
        List {
            ForEach(webClient.movies) { movie in
                MovieRow(
                    movie: movie,
                    status: rowStatus[movie.id],
                    alreadyOnDevice: bleManager.movies.contains { $0.title == movie.name },
                    onDownload: { Task { await downloadAndSend(movie) } }
                )
                .listRowBackground(Color.appElevatedSurface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if webClient.movies.isEmpty && !isRefreshing {
                Text("No movies on MagicBox-web yet")
                    .foregroundStyle(.secondary)
            }
        }
        .refreshable { await refresh() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Sign Out") { webClient.logout() }
                    .tint(.appAccent)
            }
        }
    }

    private func refresh() async {
        isRefreshing = true
        await webClient.fetchMovies()
        isRefreshing = false
    }

    private func downloadAndSend(_ movie: RemoteMovie) async {
        rowStatus[movie.id] = .downloading
        do {
            let fileURL = try await webClient.downloadMovie(movie)
            rowStatus[movie.id] = .sending
            await bleManager.uploadMovieIfNeeded(fileURL: fileURL)
            rowStatus[movie.id] = .done
            try? FileManager.default.removeItem(at: fileURL)
        } catch {
            rowStatus[movie.id] = .failed
        }
    }

    private struct MovieRow: View {
        let movie: RemoteMovie
        let status: RowStatus?
        let alreadyOnDevice: Bool
        let onDownload: () -> Void

        var body: some View {
            HStack {
                VStack(alignment: .leading) {
                    Text(movie.name)
                    HStack(spacing: 4) {
                        if let year = movie.productionYear {
                            Text(String(year))
                        }
                        if movie.durationMinutes > 0 {
                            Text("\u{00B7} \(movie.durationMinutes) min")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                trailingControl
            }
        }

        @ViewBuilder
        private var trailingControl: some View {
            switch status {
            case .downloading:
                ProgressView()
            case .sending:
                Label("Sending to device", systemImage: "antenna.radiowaves.left.and.right")
                    .labelStyle(.iconOnly)
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            case nil:
                if alreadyOnDevice {
                    Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                } else if movie.isReady {
                    Button(action: onDownload) {
                        Image(systemName: "icloud.and.arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .tint(.appAccent)
                } else {
                    Text(movie.status.replacingOccurrences(of: "_", with: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        RemoteLibraryView()
            .environmentObject(BLEManager())
    }
}
