import SwiftUI
import PencilKit
import Combine

/// A view for editing image attachments with markup capabilities
/// Uses PencilKit for drawing annotations on images
struct AttachmentEditorView: View {
    let file: SecureFile
    let originalImage: UIImage
    let onSave: (Data) -> Void
    let onCancel: () -> Void

    @StateObject private var editorState = MarkupEditorState()
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                GeometryReader { geometry in
                    if geometry.size.width > 0 && geometry.size.height > 0 {
                        let imageSize = calculateImageSize(for: originalImage, in: geometry.size)

                        ZStack {
                            // Background image
                            Image(uiImage: originalImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: imageSize.width, height: imageSize.height)

                            // Drawing canvas overlay
                            MarkupCanvasView(editorState: editorState)
                                .frame(width: imageSize.width, height: imageSize.height)
                        }
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                }
            }
            .onAppear {
                AppLog.debug("🎨 [AttachmentEditor] View appeared for file: \(file.id)")
                AppLog.debug("🎨 [AttachmentEditor] Image size: \(originalImage.size)")
            }
            .navigationTitle("Markup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        AppLog.debug("🎨 [AttachmentEditor] Cancel tapped")
                        onCancel()
                    }
                    .foregroundColor(.white)
                }

                ToolbarItem(placement: .primaryAction) {
                    if isSaving {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text(NSLocalizedString("attachments.saving", comment: "Saving..."))
                                .foregroundColor(.white)
                        }
                    } else {
                        Button {
                            saveEditedImage()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.down")
                                Text(NSLocalizedString("attachments.save_to_task", comment: "Save to Task"))
                            }
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        }
                    }
                }

                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button {
                            editorState.undo()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .disabled(!editorState.canUndo)

                        Spacer()

                        Button {
                            editorState.redo()
                        } label: {
                            Image(systemName: "arrow.uturn.forward")
                        }
                        .disabled(!editorState.canRedo)

                        Spacer()

                        Button {
                            editorState.clearDrawing()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(!editorState.hasDrawing)
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
        }
    }

    private func calculateImageSize(for image: UIImage, in containerSize: CGSize) -> CGSize {
        guard image.size.width > 0, image.size.height > 0 else {
            return CGSize(width: 100, height: 100)
        }

        let imageAspectRatio = image.size.width / image.size.height
        let containerAspectRatio = containerSize.width / containerSize.height

        if imageAspectRatio > containerAspectRatio {
            // Image is wider than container
            let width = containerSize.width
            let height = width / imageAspectRatio
            return CGSize(width: width, height: height)
        } else {
            // Image is taller than container
            let height = containerSize.height
            let width = height * imageAspectRatio
            return CGSize(width: width, height: height)
        }
    }

    private func saveEditedImage() {
        isSaving = true
        AppLog.debug("📤 [AttachmentEditor] Starting save for file: \(file.id)")
        AppLog.debug("📤 [AttachmentEditor] Original image size: \(originalImage.size)")

        // Get the canvas bounds from the editor state
        let canvasBounds = editorState.canvasBounds
        AppLog.debug("📤 [AttachmentEditor] Canvas bounds: \(canvasBounds)")

        // Safety check for canvas bounds
        guard canvasBounds.width > 0, canvasBounds.height > 0 else {
            AppLog.debug("⚠️ [AttachmentEditor] Canvas bounds are zero, using original image")
            // Just save the original image if canvas isn't ready
            guard let imageData = originalImage.jpegData(compressionQuality: 0.9) else {
                isSaving = false
                errorMessage = "Failed to encode image"
                showingError = true
                return
            }
            onSave(imageData)
            return
        }

        // Render the image with annotations
        let renderer = UIGraphicsImageRenderer(size: originalImage.size)
        let editedImage = renderer.image { context in
            // Draw original image
            originalImage.draw(at: .zero)

            // Scale and draw the canvas drawing
            let scale = originalImage.size.width / canvasBounds.width
            AppLog.debug("📤 [AttachmentEditor] Scale factor: \(scale)")
            context.cgContext.scaleBy(x: scale, y: scale)

            // Convert PKDrawing to image and draw it
            let drawingImage = editorState.getDrawingImage(bounds: canvasBounds)
            drawingImage.draw(at: .zero)
        }

        // Convert to JPEG data
        guard let imageData = editedImage.jpegData(compressionQuality: 0.9) else {
            isSaving = false
            errorMessage = "Failed to encode edited image"
            showingError = true
            AppLog.debug("❌ [AttachmentEditor] Failed to encode image")
            return
        }

        AppLog.debug("📤 [AttachmentEditor] Encoded image: \(imageData.count) bytes, calling onSave...")
        onSave(imageData)
    }
}

// MARK: - Editor State

/// Observable state for the markup editor
@MainActor
class MarkupEditorState: ObservableObject {
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var hasDrawing = false

    var canvasBounds: CGRect = .zero
    private var drawing = PKDrawing()
    private weak var canvasView: PKCanvasView?

    func setCanvasView(_ canvas: PKCanvasView) {
        self.canvasView = canvas
        updateState()
    }

    func updateState() {
        canUndo = canvasView?.undoManager?.canUndo ?? false
        canRedo = canvasView?.undoManager?.canRedo ?? false
        hasDrawing = !(canvasView?.drawing.strokes.isEmpty ?? true)
        canvasBounds = canvasView?.bounds ?? .zero
        drawing = canvasView?.drawing ?? PKDrawing()
    }

    func undo() {
        canvasView?.undoManager?.undo()
        updateState()
    }

    func redo() {
        canvasView?.undoManager?.redo()
        updateState()
    }

    func clearDrawing() {
        canvasView?.drawing = PKDrawing()
        updateState()
    }

    func getDrawingImage(bounds: CGRect) -> UIImage {
        return drawing.image(from: bounds, scale: 1.0)
    }
}

// MARK: - Canvas View

/// UIViewRepresentable wrapper for PKCanvasView
struct MarkupCanvasView: UIViewRepresentable {
    @ObservedObject var editorState: MarkupEditorState

    func makeCoordinator() -> Coordinator {
        Coordinator(editorState: editorState)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        AppLog.debug("🎨 [MarkupCanvasView] makeUIView called")

        let canvasView = PKCanvasView()
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.tool = PKInkingTool(.pen, color: .red, width: 5)
        canvasView.delegate = context.coordinator

        // Store reference in coordinator
        context.coordinator.canvasView = canvasView

        // Update editor state with canvas reference
        DispatchQueue.main.async {
            self.editorState.setCanvasView(canvasView)
        }

        // Setup tool picker after a delay to ensure window is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.setupToolPicker(for: canvasView, coordinator: context.coordinator)
        }

        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Update state when view updates
        DispatchQueue.main.async {
            self.editorState.updateState()
        }
    }

    private func setupToolPicker(for canvasView: PKCanvasView, coordinator: Coordinator) {
        AppLog.debug("🎨 [MarkupCanvasView] Setting up tool picker...")

        // Find the window scene
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let _ = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first else {
            AppLog.debug("⚠️ [MarkupCanvasView] Could not get window for tool picker")
            // Try again after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.setupToolPicker(for: canvasView, coordinator: coordinator)
            }
            return
        }

        // Create and configure tool picker
        let toolPicker = PKToolPicker()
        coordinator.toolPicker = toolPicker

        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)

        // Make canvas first responder to show tool picker
        canvasView.becomeFirstResponder()

        AppLog.debug("🎨 [MarkupCanvasView] Tool picker configured, canvas is first responder: \(canvasView.isFirstResponder)")
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var toolPicker: PKToolPicker?
        weak var canvasView: PKCanvasView?
        let editorState: MarkupEditorState

        init(editorState: MarkupEditorState) {
            self.editorState = editorState
            super.init()
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            _Concurrency.Task { @MainActor in
                editorState.updateState()
            }
        }
    }
}

#Preview {
    AttachmentEditorView(
        file: SecureFile(id: "test", name: "test.jpg", size: 1000, mimeType: "image/jpeg"),
        originalImage: UIImage(systemName: "photo")!,
        onSave: { _ in },
        onCancel: { }
    )
}
