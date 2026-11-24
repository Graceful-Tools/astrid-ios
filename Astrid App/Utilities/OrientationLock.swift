//  OrientationLock.swift
//  Which way the app may face (ADEV-233). An iPhone stays upright everywhere, as Info.plist says,
//  except while a trade-off grid opened full screen asks for landscape: a wide decision matrix is
//  read sideways, and the app otherwise never turns (Jon, 2026-11-23: "we should enable a rotate
//  it ... through a button"). The iPad turns freely, as before.
//
//  The app delegate answers `supportedInterfaceOrientationsFor` from here, which takes precedence
//  over Info.plist's list, so the plist keeps describing the default.

#if os(iOS)
import UIKit

@MainActor
enum OrientationLock {
    /// A full-screen grid has asked to be read sideways.
    private(set) static var landscapeRequested = false

    static func mask(idiom: UIUserInterfaceIdiom, landscape: Bool) -> UIInterfaceOrientationMask {
        if idiom == .pad { return .all }
        return landscape ? .landscape : [.portrait, .portraitUpsideDown]
    }

    static var current: UIInterfaceOrientationMask {
        mask(idiom: UIDevice.current.userInterfaceIdiom, landscape: landscapeRequested)
    }

    /// Only an iPhone needs the button; an iPad already turns.
    static var canRotateOnRequest: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    /// Turn to landscape, or back upright, and tell UIKit the allowed set has changed.
    static func setLandscape(_ landscape: Bool) {
        guard landscapeRequested != landscape else { return }
        landscapeRequested = landscape
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        var controller = scene.keyWindow?.rootViewController
        while let shown = controller {
            shown.setNeedsUpdateOfSupportedInterfaceOrientations()
            controller = shown.presentedViewController
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: landscape ? .landscapeRight : .portrait)) { error in
            AppLog.debug("⚠️ [OrientationLock] Rotation refused: \(error)")
        }
    }
}

/// Exists only to answer which way the app may face; everything else stays on SwiftUI's side.
final class AstridAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.current
    }
}
#endif
