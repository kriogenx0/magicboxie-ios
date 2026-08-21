import UIKit
import UniformTypeIdentifiers

/// Receives a shared video (from Photos/Dropbox/Files/etc.), copies it into
/// the App Group container, and hands off to the main app to actually upload
/// it - extensions have tight memory/time limits, which a multi-gigabyte
/// video upload would blow through; the main app doesn't have that problem.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)

        let mark = UIImageView(image: UIImage(named: "MBMark"))
        mark.contentMode = .scaleAspectFit
        mark.layer.cornerRadius = 18
        mark.clipsToBounds = true
        mark.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mark)

        let label = UILabel()
        label.text = "Adding to MagicBoxie…"
        label.textAlignment = .center
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 80),
            mark.heightAnchor.constraint(equalToConstant: 80),
            mark.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mark.bottomAnchor.constraint(equalTo: label.topAnchor, constant: -20),
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
