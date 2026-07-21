import UIKit
import UniformTypeIdentifiers

/// Receives a shared video (from Photos/Dropbox/Files/etc.), copies it into
/// the App Group container, and hands off to the main app to actually upload
/// it - extensions have tight memory/time limits, which a multi-gigabyte
/// video upload would blow through; the main app doesn't have that problem.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = "Adding to MagicBox…"
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        Task { await handleSharedItem() }
    }

    private func handleSharedItem() async {
        guard
            let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
            let attachment = extensionItem.attachments?.first
        else {
            complete()
            return
        }

        let movieType = UTType.movie.identifier
        guard attachment.hasItemConformingToTypeIdentifier(movieType) else {
            complete()
            return
        }

        do {
            let loaded = try await attachment.loadItem(forTypeIdentifier: movieType)
            guard let sourceURL = loaded as? URL else {
                complete()
                return
            }
            try SharedUploadStore.copyIntoPendingUploads(from: sourceURL)
            openHostApp()
        } catch {
            complete()
        }
    }

    private func openHostApp() {
        extensionContext?.open(SharedUploadStore.importURL) { [weak self] _ in
            self?.complete()
        }
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
