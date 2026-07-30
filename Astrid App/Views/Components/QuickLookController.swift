import SwiftUI
import QuickLook
import QuickLookThumbnailing

// MARK: - QuickLook Presenter (UIKit-based)

/// Helper to present QLPreviewController using UIKit's native presentation
@MainActor
class QuickLookPresenter: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate, UIAdaptivePresentationControllerDelegate {
    static let shared = QuickLookPresenter()

    private var previewItems: [AstridPreviewItem] = []
    private var initialIndex: Int = 0
    private var onDismiss: (() -> Void)?
    private weak var currentNavController: UINavigationController?

    @objc private func dismissQuickLook() {
        currentNavController?.dismiss(animated: true) { [weak self] in
            self?.onDismiss?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.previewItems = []
            }
        }
    }

    /// Present QuickLook from the current view controller
    func present(items: [(fileId: String, url: URL)], initialIndex: Int = 0, onDismiss: @escaping () -> Void) {
        self.previewItems = items.map { AstridPreviewItem(fileId: $0.fileId, url: $0.url) }
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss

        let controller = QLPreviewController()
        controller.dataSource = self
        controller.delegate = self
        controller.currentPreviewItemIndex = initialIndex

        // Wrap in navigation controller for consistent white background
        let navController = UINavigationController(rootViewController: controller)
        navController.modalPresentationStyle = .fullScreen
        // Prevent iPad from adapting to popover/formSheet presentation
        navController.modalTransitionStyle = .coverVertical
        navController.overrideUserInterfaceStyle = .light
        navController.view.backgroundColor = .white

        // Add Done button since nav controller hides QuickLook's native one
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissQuickLook)
        )
        self.currentNavController = navController

        // Prevent iPad from adapting to popover - must be set before presenting
        navController.presentationController?.delegate = self

        // Find the top view controller to present from
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            print("❌ [QuickLook] Could not find root view controller")
            return
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        topVC.present(navController, animated: true)
    }

    // MARK: - QLPreviewControllerDataSource

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return previewItems.count
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        // Guard against index out of range during dismiss
        guard index >= 0 && index < previewItems.count else {
            return AstridPreviewItem(fileId: "placeholder", url: URL(fileURLWithPath: "/tmp/placeholder"))
        }
        return previewItems[index]
    }

    // MARK: - QLPreviewControllerDelegate

    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        onDismiss?()
        // Delay clearing to prevent index out of range during animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.previewItems = []
        }
    }

    // MARK: - UIAdaptivePresentationControllerDelegate

    /// Prevent iPad from adapting full-screen presentation to popover/formSheet
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return .none  // Always use the requested presentation style (fullScreen)
    }

    func previewController(_ controller: QLPreviewController, editingModeFor previewItem: QLPreviewItem) -> QLPreviewItemEditingMode {
        guard let astridItem = previewItem as? AstridPreviewItem else {
            return .disabled
        }

        // Only allow editing for real files (not unknown/temp)
        if astridItem.fileId.starts(with: "unknown-") || astridItem.fileId.starts(with: "temp_") {
            return .disabled
        }

        // Check if it's an editable file type (images and PDFs)
        let ext = astridItem.fileURL.pathExtension.lowercased()
        let editableExtensions = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp", "pdf"]

        return editableExtensions.contains(ext) ? .createCopy : .disabled
    }

    func previewController(_ controller: QLPreviewController, didSaveEditedCopyOf previewItem: QLPreviewItem, at modifiedContentsURL: URL) {
        guard let astridItem = previewItem as? AstridPreviewItem else { return }

        let fileId = astridItem.fileId
        guard !fileId.starts(with: "unknown-") && !fileId.starts(with: "temp_") else { return }

        guard let editedData = try? Data(contentsOf: modifiedContentsURL) else {
            print("❌ [QuickLook] Failed to read edited file")
            return
        }

        let mimeType = mimeTypeForURL(modifiedContentsURL)

        _Concurrency.Task {
            // Update thumbnail cache and notify immediately for instant UI update
            var thumbnailImage: UIImage?

            if let image = UIImage(data: editedData) {
                thumbnailImage = image
            } else {
                // For PDFs and other files, generate thumbnail using QuickLook
                thumbnailImage = await generateThumbnail(from: modifiedContentsURL)
            }

            if let thumbnail = thumbnailImage {
                await MainActor.run {
                    ThumbnailCache.shared.set(thumbnail, for: fileId)
                    // Post notification immediately so thumbnails refresh before upload completes
                    NotificationCenter.default.post(
                        name: .attachmentUpdated,
                        object: nil,
                        userInfo: ["fileId": fileId]
                    )
                }
            }

            do {
                let _ = try await AttachmentService.shared.updateAttachment(
                    fileId: fileId,
                    newFileData: editedData,
                    mimeType: mimeType
                )
                await MainActor.run {
                    showSaveSuccessToast()
                }
            } catch {
                print("❌ [QuickLook] Failed to save: \(error)")
            }
        }
    }

    private func mimeTypeForURL(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "heic", "heif": return "image/heic"
        case "webp": return "image/webp"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }

    /// Generate a thumbnail from a file URL (for PDFs and other non-image files)
    private func generateThumbnail(from url: URL) async -> UIImage? {
        let size = CGSize(width: 256, height: 256)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: UIScreen.main.scale,
            representationTypes: .all
        )

        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.uiImage)
            }
        }
    }

    private func showSaveSuccessToast() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return
        }

        let toast = UILabel()
        toast.text = "✅ Saved to \(Brand.appName)"
        toast.textColor = .white
        toast.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.9)
        toast.textAlignment = .center
        toast.font = .systemFont(ofSize: 16, weight: .semibold)
        toast.layer.cornerRadius = 20
        toast.clipsToBounds = true
        toast.alpha = 0

        let padding: CGFloat = 16
        toast.frame = CGRect(x: padding, y: window.safeAreaInsets.top + 60, width: window.bounds.width - (padding * 2), height: 44)

        window.addSubview(toast)

        UIView.animate(withDuration: 0.3, animations: {
            toast.alpha = 1
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 2.0, options: [], animations: {
                toast.alpha = 0
            }) { _ in
                toast.removeFromSuperview()
            }
        }
    }
}

// MARK: - Preview Item

/// A preview item that tracks both the URL and the original file ID
class AstridPreviewItem: NSObject, QLPreviewItem {
    let fileId: String
    let fileURL: URL

    var previewItemURL: URL? { fileURL }
    var previewItemTitle: String? { fileURL.lastPathComponent }

    init(fileId: String, url: URL) {
        self.fileId = fileId
        self.fileURL = url
        super.init()
    }
}

// MARK: - SwiftUI View Modifier

/// View modifier to present QuickLook using UIKit
struct QuickLookModifier: ViewModifier {
    let items: [(fileId: String, url: URL)]
    let initialIndex: Int
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, newValue in
                if newValue && !items.isEmpty {
                    QuickLookPresenter.shared.present(items: items, initialIndex: initialIndex) {
                        isPresented = false
                    }
                }
            }
    }
}

extension View {
    func quickLookPresenter(items: [(fileId: String, url: URL)], initialIndex: Int, isPresented: Binding<Bool>) -> some View {
        self.modifier(QuickLookModifier(items: items, initialIndex: initialIndex, isPresented: isPresented))
    }
}
