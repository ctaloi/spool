import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Entry point for the Spool Share Extension. The system instantiates
/// this controller when the user picks "Spool" from the share sheet
/// of any app (Safari, Mail, Messages, etc.). We extract the shared
/// URL from the extension's input items and hand it to a SwiftUI host
/// that runs the on-device summarizer against it.
class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        Task { @MainActor in
            let url = await extractURL()
            embed(url: url)
        }
    }

    private func extractURL() async -> URL? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return nil }
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let urlObj = try? await provider.loadItem(
                        forTypeIdentifier: UTType.url.identifier
                    ) as? URL {
                        return urlObj
                    }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try? await provider.loadItem(
                        forTypeIdentifier: UTType.plainText.identifier
                    ) as? String,
                       let url = URL(string: text) {
                        return url
                    }
                }
            }
        }
        return nil
    }

    private func embed(url: URL?) {
        let host = UIHostingController(
            rootView: ShareSummaryView(
                url: url,
                onDismiss: { [weak self] in
                    self?.extensionContext?.completeRequest(
                        returningItems: nil,
                        completionHandler: nil
                    )
                }
            )
        )
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }
}
