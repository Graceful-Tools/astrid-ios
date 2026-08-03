//  CameraCapturePicker.swift
//  Take a photo and hand it back. (Task a72e09ca — "From Camera")
//
//  SwiftUI has no native camera capture view, so this wraps UIImagePickerController.
//  Requires NSCameraUsageDescription in Info.plist — without it the app is terminated on
//  first camera access rather than shown a permission prompt.

import SwiftUI
import UIKit

struct CameraCapturePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    /// Called with the captured photo. Not called if the user cancels.
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        // Guard the source type: setting .camera where none exists raises at runtime.
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: { dismiss() })
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let dismiss: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, dismiss: @escaping () -> Void) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // .editedImage only exists when allowsEditing is on; fall back to the original.
            if let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage) {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
