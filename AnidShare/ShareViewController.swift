import UIKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Entry point for sharing a video into Anid from elsewhere (Photos' own
/// share sheet, chiefly). Pulls the shared video out of the extension
/// context, copies it into the shared App Group storage, then presents a
/// tiny SwiftUI compose screen to add an optional note before saving a new
/// Idea straight into the same SwiftData store the main app reads.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        loadSharedVideo()
    }

    private func loadSharedVideo() {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let provider = item.attachments?.first(where: {
                $0.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
            })
        else {
            finish(withError: true)
            return
        }

        provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
            guard let self else { return }
            guard let url, error == nil else {
                DispatchQueue.main.async { self.finish(withError: true) }
                return
            }
            // The URL handed to this callback is only valid for its duration,
            // so it has to be copied into permanent storage right here.
            do {
                let filename = try VideoStorage.store(from: url)
                DispatchQueue.main.async { self.presentCompose(filename: filename) }
            } catch {
                DispatchQueue.main.async { self.finish(withError: true) }
            }
        }
    }

    private func presentCompose(filename: String) {
        let compose = ShareComposeView(
            onSave: { [weak self] note in
                self?.save(note: note, filename: filename)
            },
            onCancel: { [weak self] in
                VideoStorage.delete(filename: filename)
                self?.finish(withError: true)
            }
        )
        let hosting = UIHostingController(rootView: compose)
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }

    private func save(note: String, filename: String) {
        let context = ModelContext(SharedModelContainer.make())
        let idea = Idea(rawText: note, localVideoFilename: filename)
        context.insert(idea)
        do {
            try context.save()
            finish(withError: false)
        } catch {
            VideoStorage.delete(filename: filename)
            finish(withError: true)
        }
    }

    private func finish(withError: Bool) {
        if withError {
            extensionContext?.cancelRequest(withError: NSError(domain: "com.hasini.anid.share", code: 1))
        } else {
            extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
