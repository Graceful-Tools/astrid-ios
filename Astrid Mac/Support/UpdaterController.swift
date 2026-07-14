//  UpdaterController.swift
//  Astrid for Mac — Sparkle auto-update wrapper for the Direct (non-App-Store) build (M3).
//
//  Gated on `canImport(Sparkle)` so the app compiles and ships TODAY without the Sparkle
//  package. When the Direct build adds the Sparkle SPM dependency and the Info.plist keys
//  (SUFeedURL + SUPublicEDKey), this lights up automatically. The App Store build uses the
//  store's own update mechanism and never calls this.

#if os(macOS)
import Foundation
import Combine

#if canImport(Sparkle)
import Sparkle

final class UpdaterController: ObservableObject {
    static let shared = UpdaterController()
    private let controller = SPUStandardUpdaterController(startingUpdater: true,
                                                          updaterDelegate: nil,
                                                          userDriverDelegate: nil)
    var isAvailable: Bool { true }
    func checkForUpdates() { controller.updater.checkForUpdates() }
}
#else

/// No-op until the Sparkle package is added to the Direct build (see docs/MAC_DISTRIBUTION.md).
final class UpdaterController: ObservableObject {
    static let shared = UpdaterController()
    var isAvailable: Bool { false }
    func checkForUpdates() {}
}
#endif
#endif
