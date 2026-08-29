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

        print("📤 [ShareExtension] Share Extension loaded")

        // Extract shared content
        extractSharedContent { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let fileData):
                self.sharedFileData = fileData
                self.setupUI(with: fileData)
            case .failure(let error):
                print("❌ [ShareExtension] Failed to extract content: \(error)")
                self.showError(error)
            }
        }
    }

    // MARK: - UI Setup

    private func setupUI(with fileData: SharedFileData?) {
        print("🎨 [ShareExtension] Setting up UI")

        let quickCreateView = TaskQuickCreateView(
            fileData: fileData,
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

    private func extractSharedContent(completion: @escaping (Result<SharedFileData?, Error>) -> Void) {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = extensionItem.attachments?.first else {
            print("⚠️ [ShareExtension] No attachments found")
            completion(.success(nil))
            return
        }

        print("📎 [ShareExtension] Found attachment")

        // Try to load as image first
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            loadImage(from: itemProvider, completion: completion)
        }
        // Then try other file types
        else if itemProvider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            loadFile(from: itemProvider, completion: completion)
        }
        // Try URL (for files from Files app)
        else if itemProvider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            loadFileURL(from: itemProvider, completion: completion)
        }
        else {
            print("⚠️ [ShareExtension] Unsupported content type")
            completion(.success(nil))
        }
    }

    private func loadImage(from itemProvider: NSItemProvider, completion: @escaping (Result<SharedFileData?, Error>) -> Void) {
        itemProvider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] (item, error) in
            if let error = error {
                print("❌ [ShareExtension] Error loading image: \(error)")
                completion(.failure(error))
                return
            }

            guard let self = self else { return }

            // Handle image data
            if let url = item as? URL {
                self.processFileURL(url, completion: completion)
            } else if let data = item as? Data {
                self.processImageData(data, completion: completion)
            } else if let image = item as? UIImage {
                self.processUIImage(image, completion: completion)
            } else {
                print("⚠️ [ShareExtension] Unknown image format")
                completion(.success(nil))
            }
        }
    }

    private func loadFile(from itemProvider: NSItemProvider, completion: @escaping (Result<SharedFileData?, Error>) -> Void) {
        itemProvider.loadItem(forTypeIdentifier: UTType.data.identifier, options: nil) { [weak self] (item, error) in
            if let error = error {
                print("❌ [ShareExtension] Error loading file: \(error)")
                completion(.failure(error))
                return
            }

            guard let self = self else { return }

            if let url = item as? URL {
                self.processFileURL(url, completion: completion)
            } else if let data = item as? Data {
                self.processFileData(data, suggestedName: "file", completion: completion)
            } else {
                print("⚠️ [ShareExtension] Unknown file format")
                completion(.success(nil))
            }
        }
    }

    private func loadFileURL(from itemProvider: NSItemProvider, completion: @escaping (Result<SharedFileData?, Error>) -> Void) {
        itemProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] (item, error) in
            if let error = error {
                print("❌ [ShareExtension] Error loading file URL: \(error)")
                completion(.failure(error))
                return
            }

            guard let self = self, let url = item as? URL else {
                completion(.success(nil))
                return
            }

            self.processFileURL(url, completion: completion)
        }
    }

    // MARK: - Process Content

    private func processFileURL(_ url: URL, completion: @escaping (Result<SharedFileData?, Error>) -> Void) {
        print("📁 [ShareExtension] Processing file URL: \(url.lastPathComponent)")

        do {
            // Copy file to shared container
            let sharedURL = try ShareDataManager.shared.copyFileToSharedContainer(from: url)

            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0

            let mimeType = getMimeType(for: url.pathExtension)

            let fileData = SharedFileData(
                fileURL: sharedURL,
                fileName: url.lastPathComponent,
                mimeType: mimeType,
                fileSize: fileSize
            )

            print("✅ [ShareExtension] File processed: \(url.lastPathComponent) (\(fileSize) bytes)")
            completion(.success(fileData))
        } catch {
            print("❌ [ShareExtension] Failed to process file: \(error)")
            completion(.failure(error))
        }
    }

    private func processImageData(_ data: Data, completion: @escaping (Result<SharedFileData?, Error>) -> Void) {
        print("🖼️ [ShareExtension] Processing image data (\(data.count) bytes)")

        let fileName = "image_\(Int(Date().timeIntervalSince1970)).jpg"
        processFileData(data, suggestedName: fileName, completion: completion)
    }

    private func processUIImage(_ image: UIImage, completion: @escaping (Result<SharedFileData?, Error>) -> Void) {
        print("🖼️ [ShareExtension] Processing UIImage")

        guard let data = image.jpegData(compressionQuality: 0.8) else {
            print("❌ [ShareExtension] Failed to convert image to JPEG")
            completion(.success(nil))
            return
        }

        let fileName = "image_\(Int(Date().timeIntervalSince1970)).jpg"
        processFileData(data, suggestedName: fileName, completion: completion)
    }

    private func processFileData(_ data: Data, suggestedName: String, completion: @escaping (Result<SharedFileData?, Error>) -> Void) {
        do {
            // Write to temporary file first
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedName)
            try data.write(to: tempURL)

            // Copy to shared container
            let sharedURL = try ShareDataManager.shared.copyFileToSharedContainer(from: tempURL)

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)

            let mimeType = getMimeType(for: (suggestedName as NSString).pathExtension)

            let fileData = SharedFileData(
                fileURL: sharedURL,
                fileName: suggestedName,
                mimeType: mimeType,
                fileSize: Int64(data.count)
            )

            print("✅ [ShareExtension] File data processed: \(suggestedName) (\(data.count) bytes)")
            completion(.success(fileData))
        } catch {
            print("❌ [ShareExtension] Failed to process file data: \(error)")
            completion(.failure(error))
        }
    }

    // MARK: - Save and Close

    private func saveAndClose(taskData: SharedTaskData) {
        print("💾 [ShareExtension] Saving shared task: \(taskData.title)")

        do {
            try ShareDataManager.shared.saveSharedTask(taskData)
            print("✅ [ShareExtension] Task saved successfully")

            // Close extension with success
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        } catch {
            print("❌ [ShareExtension] Failed to save task: \(error)")
            showError(error)
        }
    }

    private func cancel() {
        print("❌ [ShareExtension] User cancelled")

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

    // MARK: - Helpers

    private func getMimeType(for fileExtension: String) -> String {
        if let type = UTType(filenameExtension: fileExtension) {
            return type.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }
}

// MARK: - Shared File Data

struct SharedFileData {
    let fileURL: URL
    let fileName: String
    let mimeType: String
    let fileSize: Int64
}
