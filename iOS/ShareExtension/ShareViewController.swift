import UIKit
import SwiftUI
import UniformTypeIdentifiers
import TidyCore

@MainActor final class ShareViewController: UIViewController {
    private var loadingTask: Task<Void, Never>?
    private var hosted: UIViewController?
    override func viewDidLoad() {
        super.viewDidLoad()
        show(AnyView(VStack(spacing: 20) {
            ProgressView("Opening shared text…")
            Button("Cancel") { [weak self] in self?.finish() }
        }))
        loadingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.loadText()
                try Task.checkCancellation()
                let store = MobileStore()
                self.show(AnyView(EditorView(store: store, text: text, isExtension: true) { [weak self] in self?.finish() }))
            } catch {
                guard !Task.isCancelled else { return }
                self.show(AnyView(VStack(spacing: 20) {
                    Image(systemName: "text.badge.xmark").font(.largeTitle)
                    Text("No text to tidy").font(.title2.bold())
                    Text(error.localizedDescription).multilineTextAlignment(.center)
                    Button("Done") { [weak self] in self?.finish() }
                }.padding(28)))
            }
        }
    }
    private func show(_ root: AnyView) {
        if let hosted { hosted.willMove(toParent: nil); hosted.view.removeFromSuperview(); hosted.removeFromParent() }
        let controller = UIHostingController(rootView: root)
        addChild(controller); view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self); hosted = controller
    }
    private func finish() {
        loadingTask?.cancel()
        extensionContext?.completeRequest(returningItems: nil)
    }
    private func loadText() async throws -> String {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        var pieces: [String] = []
        for item in items {
            var attached = false
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                let value: NSSecureCoding? = try await withCheckedThrowingContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { value, error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: value) }
                    }
                }
                try Task.checkCancellation()
                let text: String?
                if let string = value as? String { text = string }
                else if let attributed = value as? NSAttributedString { text = attributed.string }
                else if let data = value as? Data, data.count <= 80_000 { text = String(data: data, encoding: .utf8) }
                else { text = nil }
                if let text, !text.trimmed.isEmpty { pieces.append(text); attached = true }
                guard pieces.reduce(0, { $0 + $1.count }) <= 20_000 else { throw ClaudeError(message: "Share a shorter selection, up to 20,000 characters.") }
            }
            if !attached, let text = item.attributedContentText?.string, !text.trimmed.isEmpty { pieces.append(text) }
        }
        let text = pieces.joined(separator: "\n\n")
        guard !text.trimmed.isEmpty else { throw ClaudeError(message: "Select and share text from a supporting app. Links, images and files aren’t supported in this prototype.") }
        guard text.count <= 20_000 else { throw ClaudeError(message: "Share a shorter selection, up to 20,000 characters.") }
        return text
    }
    deinit { loadingTask?.cancel() }
}
