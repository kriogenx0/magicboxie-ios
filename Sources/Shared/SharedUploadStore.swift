import Foundation

/// Hand-off point between the Share Extension and the main app: the
/// extension copies a shared video file in here (via the App Group container,
/// since the extension and the app are separate processes/sandboxes), then
/// asks the system to open the main app, which picks the file up from here
/// and uploads it to the device.
enum SharedUploadStore {
    static let appGroupID = "group.com.magicboxie.app"
    static let importURL = URL(string: "magicboxie://import-shared")!

    static var pendingUploadsDirectory: URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        let directory = container.appendingPathComponent("PendingUploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Copies a shared file into the pending-uploads directory, preserving
    /// its filename (it becomes the movie's title on the device once
    /// uploaded). A same-named file already waiting is replaced - shares are
    /// picked up almost immediately, so this directory is never meant to
    /// hold more than a few files at a time.
    @discardableResult
    static func copyIntoPendingUploads(from sourceURL: URL) throws -> URL {
        guard let directory = pendingUploadsDirectory else {
            throw CocoaError(.fileWriteUnknown)
        }
        let destination = directory.appendingPathComponent(sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    static func pendingUploadURLs() -> [URL] {
        guard let directory = pendingUploadsDirectory else { return [] }
        return (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
