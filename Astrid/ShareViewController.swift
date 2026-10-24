import UIKit
import Social
import SwiftUI
import UniformTypeIdentifiers
import MobileCoreServices

/// Main entry point for Share Extension
/// Handles receiving shared content from system share sheet
class ShareViewController: UIViewController {

    private var hostingController: UIHostingController<TaskQuickCreateView>?
    private var sharedFileData: SharedFileData?

    override func viewDidLoad() {
        super.viewDidLoad()

        AppLog.debug("📤 [ShareExtension] Share Extension loaded")

        // Extract shared content
        extractSharedContent { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let draft):
                self.sharedFileData = draft?.file
                self.setupUI(with: draft)
            case .failure(let error):
                AppLog.debug("❌ [ShareExtension] Failed to extract content: \(error)")
                self.showError(error)
            }
        }
    }

    // MARK: - UI Setup

    private func setupUI(with draft: SharedTaskDraft?) {
        AppLog.debug("🎨 [ShareExtension] Setting up UI")

        let quickCreateView = TaskQuickCreateView(
            draft: draft,
            onSave: { [weak self] taskData in
                self?.saveAndClose(taskData: taskData)
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )

        let hostingController = UIHostingController(rootView: quickCreateView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        hostingController.didMove(toParent: self)
        self.hostingController = hostingController
    }

    // MARK: - Extract Shared Content

    /// The mapping lives in `Shared/SharedContentLoader.swift`, where the unit tests reach it.
    private func extractSharedContent(completion: @escaping (Result<SharedTaskDraft?, Error>) -> Void) {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        _Concurrency.Task { @MainActor in
            do {
                completion(.success(try await SharedContentLoader(manager: .shared).draft(from: items)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Save and Close

    private func saveAndClose(taskData: SharedTaskData) {
        AppLog.debug("💾 [ShareExtension] Saving shared task: \(taskData.title)")

        do {
            try ShareDataManager.shared.saveSharedTask(taskData)
            AppLog.debug("✅ [ShareExtension] Task saved successfully")

            // Close extension with success
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        } catch {
            AppLog.debug("❌ [ShareExtension] Failed to save task: \(error)")
            showError(error)
        }
    }

    private func cancel() {
        AppLog.debug("❌ [ShareExtension] User cancelled")

        // Clean up any shared file
        if let fileURL = sharedFileData?.fileURL {
            try? ShareDataManager.shared.deleteSharedFile(at: fileURL)
        }

        // Close extension
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    // MARK: - Error Handling

    private func showError(_ error: Error) {
        let alert = UIAlertController(
            title: "Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.cancel()
        })
        present(alert, animated: true)
    }
}
