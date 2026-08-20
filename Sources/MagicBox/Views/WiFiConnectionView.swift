import SwiftUI

/// Standalone WiFi connectivity check, reached from Settings. Lets you
/// confirm the device's WiFi/HTTP transport - used only for movie/thumbnail
/// uploads (see BLEManager.uploadMovieIfNeeded/pushThumbnailToDeviceIfNeeded),
/// never for control - is actually reachable, independent of BLE. Read-only:
/// deliberately doesn't add a WiFi control path, since BLE always carries
/// commands regardless of what this shows.
struct WiFiConnectionView: View {
    @EnvironmentObject private var bleManager: BLEManager

    private enum TestState {
        case idle
        case testing
        case success(movieCount: Int)
        case failure(String)
    }

    @State private var testState: TestState = .idle

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi")
                .font(.system(size: 48))
                .foregroundStyle(Color.appAccent)

            if let url = bleManager.wifiBaseURL {
                Text(url.absoluteString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Device not yet discovered on WiFi")
                    .foregroundStyle(.secondary)
            }

            resultView

            Button("Test Connection") {
                Task { await testConnection() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.appAccent)
            .disabled(bleManager.wifiBaseURL == nil || isTesting)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Device WiFi")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var resultView: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView()
        case .success(let count):
            Label("Connected — \(count) movie(s) found", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Text(message)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    private var isTesting: Bool {
        if case .testing = testState { return true }
        return false
    }

    private func testConnection() async {
        guard let url = bleManager.wifiBaseURL else { return }
        testState = .testing
        do {
            let movies = try await DeviceHTTPClient(baseURL: url).fetchMovies()
            testState = .success(movieCount: movies.count)
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }
}

#Preview {
    NavigationStack {
        WiFiConnectionView()
    }
    .environmentObject(BLEManager())
}
