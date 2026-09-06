import SwiftUI
import PhotosUI

// MARK: - UIImage Orientation Fix

extension UIImage {
    /// Returns a new image with normalized orientation (always .up)
    /// This fixes rotation issues when loading images from the photo library
    /// NOTE: This must be called on the main thread as UIGraphics APIs require it
    @MainActor
    func normalizedOrientation() -> UIImage {
        if imageOrientation == .up {
            return self
        }

        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return normalizedImage ?? self
    }
}

// MARK: - PHPicker Wrapper (avoids SwiftUI sheet dismiss issues)

struct PHPickerViewControllerWrapper: UIViewControllerRepresentable {
    let onImageSelected: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageSelected: onImageSelected, onCancel: onCancel)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImageSelected: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImageSelected: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImageSelected = onImageSelected
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                onCancel()
                return
            }

            // Capture callbacks before async context to satisfy Swift 6 concurrency
            // This avoids capturing `self` in a @MainActor Task (concurrent code)
            let imageSelectedCallback = onImageSelected
            let cancelCallback = onCancel

            result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                // Use Task with MainActor to ensure UIGraphics APIs are called on main thread
                _Concurrency.Task { @MainActor in
                    if let image = object as? UIImage {
                        // Normalize orientatio-n to fix rotation issues from photo library
                        // normalizedOrientation() requires MainActor for UIGraphics calls
                        let normalizedImage = image.normalizedOrientation()
                        imageSelectedCallback(normalizedImage)
                    } else {
                        cancelCallback()
                    }
                }
            }
        }
    }
}

/// Image picker modal for selecting list images
/// Supports: Color placeholders, Default icons, Photo library upload
struct ImagePickerView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    let list: TaskList
    let onSelectImage: (String) -> Void

    @State private var selectedTab = 0
    @State private var selectedPlaceholder: String?
    @State private var selectedDefaultIcon: String?
    @State private var showingPhotoPicker = false

    // Crop view state
    @State private var selectedImage: UIImage?
    @State private var showingCropView = false
    @State private var isUploading = false
    @State private var uploadError: String?

    // The shared palette (task 9a9d24bd) — Mac reads the same one, so the two platforms
    // cannot drift into offering different pictures.
    private var pastelColors: [ListImagePlaceholders.Placeholder] { ListImagePlaceholders.all }

    var body: some View {
        NavigationStack {
            Group {
                if showingCropView, let image = selectedImage {
                    // Show crop view when image is selected
                    ImageCropView(
                        image: image,
                        isUploading: isUploading,
                        uploadError: uploadError,
                        onCancel: {
                            selectedImage = nil
                            showingCropView = false
                            uploadError = nil
                        },
                        onConfirm: { croppedImage in
                            uploadCroppedImage(croppedImage)
                        }
                    )
                } else {
                    // Show tab picker
                    VStack(spacing: 0) {
                        // Tab Picker
                        Picker("", selection: $selectedTab) {
                            Label("Colors", systemImage: "paintpalette")
                                .tag(0)
                            Label("Defaults", systemImage: "photo")
                                .tag(1)
                            Label("Upload", systemImage: "photo.on.rectangle.angled")
                                .tag(2)
                        }
                        .pickerStyle(.segmented)
                        .padding(Theme.spacing16)

                        Divider()

                        // Tab Content
                        TabView(selection: $selectedTab) {
                            // Colors Tab - Pastel placeholders
                            colorsTab
                                .tag(0)

                            // Defaults Tab - 4 default icons
                            defaultsTab
                                .tag(1)

                            // Upload Tab - Photo library
                            uploadTab
                                .tag(2)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    }
                }
            }
            .background(colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
            .navigationTitle(showingCropView ? "Adjust Image" : "Choose Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if showingCropView {
                            selectedImage = nil
                            showingCropView = false
                            uploadError = nil
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            // Prevent sheet from being dismissed during photo selection or crop
            .interactiveDismissDisabled(showingCropView || showingPhotoPicker)
        }
    }

    // MARK: - Colors Tab

    private var colorsTab: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 80), spacing: Theme.spacing12)
            ], spacing: Theme.spacing12) {
                ForEach(pastelColors, id: \.name) { color in
                    Button {
                        selectedPlaceholder = color.path
                        selectedDefaultIcon = nil
                        onSelectImage(color.path)
                        dismiss()
                    } label: {
                        VStack(spacing: Theme.spacing8) {
                            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                                .fill(Color(hex: color.colorHex) ?? Color.gray)
                                .frame(height: 80)
                                .overlay {
                                    if selectedPlaceholder == color.path {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title)
                                            .foregroundColor(.white)
                                            .shadow(radius: 2)
                                    }
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                                        .stroke(
                                            selectedPlaceholder == color.path ? Theme.accent : Color.clear,
                                            lineWidth: 3
                                        )
                                }

                            Text(color.name)
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.spacing16)
        }
    }

    // MARK: - Defaults Tab

    private var defaultsTab: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 100), spacing: Theme.spacing16)
            ], spacing: Theme.spacing16) {
                ForEach(ListImageHelper.defaultImages, id: \.name) { icon in
                    Button {
                        selectedDefaultIcon = icon.filename
                        selectedPlaceholder = nil
                        onSelectImage(icon.filename)
                        dismiss()
                    } label: {
                        VStack(spacing: Theme.spacing8) {
                            // Load default icon from web
                            AsyncImage(url: URL(string: "\(Brand.productionBaseURL)\(icon.filename)")) { phase in
                                switch phase {
                                case .empty:
                                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 100, height: 100)
                                        .overlay {
                                            ProgressView()
                                        }
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                                        .overlay {
                                            if selectedDefaultIcon == icon.filename {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.title)
                                                    .foregroundColor(.white)
                                                    .shadow(radius: 2)
                                            }
                                        }
                                        .overlay {
                                            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                                                .stroke(
                                                    selectedDefaultIcon == icon.filename ? Theme.accent : Color.clear,
                                                    lineWidth: 3
                                                )
                                        }
                                case .failure(_):
                                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                                        .fill(Color(hex: icon.color) ?? Color.gray)
                                        .frame(width: 100, height: 100)
                                @unknown default:
                                    EmptyView()
                                }
                            }

                            Text(labelForDefaultIcon(icon.name))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.spacing16)
        }
    }

    // MARK: - Upload Tab

    private var uploadTab: some View {
        VStack(spacing: Theme.spacing24) {
            Spacer()

            // Icon
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundColor(Theme.accent)

            // Instructions
            VStack(spacing: Theme.spacing8) {
                Text(NSLocalizedString("image_picker.upload_library", comment: "Upload from Photo Library"))
                    .font(Theme.Typography.headline())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                Text(NSLocalizedString("image_picker.choose_description", comment: "Choose an image from your photo library"))
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Upload Button - present PHPicker via sheet
            Button {
                showingPhotoPicker = true
            } label: {
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text(NSLocalizedString("attachments.choose_photo", comment: "Choose Photo"))
                }
                .font(Theme.Typography.body())
                .foregroundColor(.white)
                .padding(.horizontal, Theme.spacing24)
                .padding(.vertical, Theme.spacing12)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
            .sheet(isPresented: $showingPhotoPicker) {
                PHPickerViewControllerWrapper(
                    onImageSelected: { image in
                        showingPhotoPicker = false
                        selectedImage = image
                        showingCropView = true
                    },
                    onCancel: {
                        showingPhotoPicker = false
                    }
                )
                .ignoresSafeArea()
            }

            Spacer()
        }
        .padding(Theme.spacing16)
    }

    // MARK: - Helper Methods

    private func labelForDefaultIcon(_ name: String) -> String {
        switch name {
        case "Default List 0": return "Blue"
        case "Default List 1": return "Green"
        case "Default List 2": return "Orange"
        case "Default List 3": return "Purple"
        default: return name
        }
    }

    private func uploadCroppedImage(_ image: UIImage) {
        isUploading = true
        uploadError = nil

        _Concurrency.Task {
            do {
                // Convert to JPEG data
                guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                    throw URLError(.cannotDecodeContentData)
                }

                // Upload to secure file storage
                let imageUrl = try await uploadImage(data: imageData)

                await MainActor.run {
                    isUploading = false
                    onSelectImage(imageUrl)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    uploadError = "Failed to upload. Please try again."
                }
            }
        }
    }

    private func uploadImage(data: Data) async throws -> String {
        // Create multipart form data
        let boundary = UUID().uuidString
        var body = Data()

        // Add file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"list-image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)

        // Add context
        let contextJSON = "{\"listId\":\"\(list.id)\"}"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"context\"\r\n\r\n".data(using: .utf8)!)
        body.append(contextJSON.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        // Make request
        guard let url = URL(string: "\(Constants.API.baseURL)/api/v1/secure-upload/request-upload") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        AnalyticsPlatformHeader.apply(to: &request)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        // Add session cookie for authentication
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        // Parse response
        let json = try JSONDecoder().decode(SecureFileUploadResponse.self, from: responseData)
        return "/api/v1/secure-files/\(json.fileId)"
    }
}

// MARK: - Upload Response Model

private struct SecureFileUploadResponse: Codable {
    let fileId: String
    let success: Bool
    // Optional fields from server response
    let fileName: String?
    let fileSize: Int?
    let mimeType: String?
}

// MARK: - Image Crop View

/// View for adjusting and cropping an image to a square before upload
struct ImageCropView: View {
    @Environment(\.colorScheme) var colorScheme

    let image: UIImage
    let isUploading: Bool
    let uploadError: String?
    let onCancel: () -> Void
    let onConfirm: (UIImage) -> Void

    // Gesture state for pan and zoom
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    // Crop area size (square)
    private let cropSize: CGFloat = 280

    var body: some View {
        VStack(spacing: 0) {
            // Instructions
            Text(NSLocalizedString("image_picker.pinch_zoom", comment: "Pinch to zoom, drag to position"))
                .font(Theme.Typography.caption1())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                .padding(.top, Theme.spacing16)

            Spacer()

            // Crop area
            ZStack {
                // Dark overlay
                Color.black.opacity(0.6)

                // Image with gestures
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(scale)
                    .offset(offset)
                    .frame(width: cropSize, height: cropSize)
                    .clipped()
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale = min(max(scale * delta, 1.0), 5.0)
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                },
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                    )

                // Crop frame overlay
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: cropSize, height: cropSize)
            }
            .frame(width: cropSize + 40, height: cropSize + 40)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))

            Spacer()

            // Error message
            if let error = uploadError {
                Text(error)
                    .font(Theme.Typography.caption1())
                    .foregroundColor(Theme.error)
                    .padding(.horizontal, Theme.spacing16)
                    .padding(.bottom, Theme.spacing8)
            }

            // Action buttons
            VStack(spacing: Theme.spacing12) {
                // Confirm button
                Button {
                    let cropped = cropImage()
                    onConfirm(cropped)
                } label: {
                    HStack {
                        if isUploading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                            Text(NSLocalizedString("image_picker.uploading", comment: "Uploading..."))
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                            Text(NSLocalizedString("image_picker.use_this_image", comment: "Use This Image"))
                        }
                    }
                    .font(Theme.Typography.body())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.spacing12)
                    .background(isUploading ? Theme.accent.opacity(0.6) : Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                }
                .disabled(isUploading)

                // Choose different photo
                Button {
                    onCancel()
                } label: {
                    Text(NSLocalizedString("image_picker.choose_different_photo", comment: "Choose Different Photo"))
                        .font(Theme.Typography.body())
                        .foregroundColor(Theme.accent)
                }
                .disabled(isUploading)
            }
            .padding(Theme.spacing16)
        }
        .background(colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
    }

    /// Crop the image to the visible area
    /// NOTE: This function uses UIGraphics and is called from the main thread via SwiftUI Button action
    @MainActor
    private func cropImage() -> UIImage {
        let imageSize = image.size
        let viewSize = CGSize(width: cropSize, height: cropSize)

        // Calculate the visible rect in image coordinates
        let scaledImageSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        // Determine the aspect-fill scale
        let aspectFillScale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)

        // Calculate center offset
        let centerX = (scaledImageSize.width * aspectFillScale - viewSize.width) / 2
        let centerY = (scaledImageSize.height * aspectFillScale - viewSize.height) / 2

        // Apply user offset (inverted because we're moving the image, not the viewport)
        let cropX = centerX - offset.width
        let cropY = centerY - offset.height

        // Convert to image coordinates
        let imageScale = 1 / (scale * aspectFillScale)
        let cropRect = CGRect(
            x: max(0, cropX * imageScale),
            y: max(0, cropY * imageScale),
            width: viewSize.width * imageScale,
            height: viewSize.height * imageScale
        )

        // Perform the crop
        guard let cgImage = image.cgImage?.cropping(to: cropRect) else {
            return image
        }

        // Resize to a reasonable output size (512x512 for list images)
        // UIGraphicsBeginImageContextWithOptions must be called on main thread
        let outputSize = CGSize(width: 512, height: 512)
        UIGraphicsBeginImageContextWithOptions(outputSize, false, 1.0)
        UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: outputSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resizedImage ?? UIImage(cgImage: cgImage)
    }
}

#Preview {
    ImagePickerView(
        list: TaskList(
            id: "test-123",
            name: "Test List",
            color: "#3b82f6"
        ),
        onSelectImage: { imageUrl in
            print("Selected image: \(imageUrl)")
        }
    )
}
