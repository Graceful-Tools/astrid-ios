import Foundation

/// Single source of truth for handling a picked photo that can't be loaded.
///
/// With "Optimize iPhone Storage", full-resolution photos live in iCloud only.
/// SwiftUI's PhotosPicker downloads the bytes on demand via `loadTransferable`,
/// which returns nil / throws when the device is offline and the asset hasn't
/// been downloaded. Both the comment composer and the task-detail composer hit
/// this case; centralizing the copy here keeps their behavior identical.
enum OfflinePhotoPolicy {

    /// User-facing message for a failed photo load. When offline we explain the
    /// likely cause (cloud-only asset) and the two ways out; when online it's a
    /// generic retry.
    static func unavailableMessage(isConnected: Bool) -> String {
        isConnected
            ? "Failed to load photo. Please try again."
            : "This photo isn't downloaded to your device. Connect to the internet, or pick a recently-taken photo (those are stored locally)."
    }
}
