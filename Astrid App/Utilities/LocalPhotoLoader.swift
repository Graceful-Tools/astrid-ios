import Foundation
import SwiftUI
import Photos
import PhotosUI

/// Loads a picked photo's bytes, preferring an **on-disk (no-network) read** so:
///  - a locally-available photo attaches instantly even offline (and the
///    existing `AttachmentService` queues its upload), and
///  - a cloud-only ("Optimize iPhone Storage") photo offline fails *fast* with a
///    clear message instead of hanging on a doomed iCloud download.
///
/// Implements part B of the "real offline photo support" task using PhotoKit
/// (`PHImageManager` + `isNetworkAccessAllowed = false`). Falls back to the
/// opaque `loadTransferable` path when PhotoKit isn't usable (no asset
/// identifier, or the user declined Photos access), so behavior never regresses
/// below today's.
enum LocalPhotoLoader {

    enum PhotoLoadOutcome: Equatable {
        case data(Data)
        /// Cloud-only and offline — the bytes simply aren't reachable.
        case notLocallyAvailable
        case failed
    }

    /// Pure decision: turn a no-network read result into an outcome.
    /// - Parameters:
    ///   - imageData: bytes returned by a no-network request (nil/empty if not on disk).
    ///   - isInCloud: PhotoKit's `PHImageResultIsInCloudKey` (true ⇒ needs network).
    ///   - isConnected: current network state.
    static func outcome(imageData: Data?, isInCloud: Bool, isConnected: Bool) -> PhotoLoadOutcome {
        if let data = imageData, !data.isEmpty { return .data(data) }
        if isInCloud && !isConnected { return .notLocallyAvailable }
        return .failed
    }

    /// Loads image data for a picked item. Tries an on-disk read first; if online
    /// and not on disk, allows a network fetch; otherwise falls back to
    /// `loadTransferable`.
    static func loadImageData(for item: PhotosPickerItem, isConnected: Bool) async -> PhotoLoadOutcome {
        if let assetId = item.itemIdentifier, let asset = await fetchAsset(localId: assetId) {
            // 1) Fast on-disk read (no network).
            let local = await requestData(asset: asset, allowNetwork: false)
            let decided = outcome(imageData: local.data, isInCloud: local.isInCloud, isConnected: isConnected)
            if case .data = decided { return decided }
            if decided == .notLocallyAvailable { return decided }

            // 2) Online and not on disk → allow the iCloud download.
            if isConnected {
                let net = await requestData(asset: asset, allowNetwork: true)
                if let data = net.data, !data.isEmpty { return .data(data) }
            }
        }

        // 3) Fallback: opaque transferable load (today's behavior).
        if let loaded = try? await item.loadTransferable(type: Data.self), !loaded.isEmpty {
            return .data(loaded)
        }
        return isConnected ? .failed : .notLocallyAvailable
    }

    // MARK: - PhotoKit plumbing

    /// Resolves a `PHAsset` from a picker item's local identifier, requesting
    /// Photos authorization if needed. Returns nil (→ caller falls back) when
    /// access isn't granted.
    private static func fetchAsset(localId: String) async -> PHAsset? {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let granted: Bool
        switch status {
        case .authorized, .limited:
            granted = true
        case .notDetermined:
            granted = await withCheckedContinuation { cont in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                    cont.resume(returning: newStatus == .authorized || newStatus == .limited)
                }
            }
        default:
            granted = false
        }
        guard granted else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil).firstObject
    }

    private static func requestData(asset: PHAsset, allowNetwork: Bool) async -> (data: Data?, isInCloud: Bool) {
        await withCheckedContinuation { cont in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = allowNetwork
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                let inCloud = (info?[PHImageResultIsInCloudKey] as? Bool) == true
                cont.resume(returning: (data, inCloud))
            }
        }
    }
}
