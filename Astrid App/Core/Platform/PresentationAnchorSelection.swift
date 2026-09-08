//  PresentationAnchorSelection.swift
//  Which window a sign-in sheet should hang off, on iOS (task AITD-347).
//
//  The old rule was `connectedScenes.first as? UIWindowScene` and then `scene.windows.first`,
//  with a `fatalError` when either failed. `Info.plist` sets `UIApplicationSupportsMultipleScenes`,
//  so on iPad `connectedScenes` is a SET: "first" is whichever the enumeration happens to yield,
//  which may be a backgrounded scene with no windows, or not a `UIWindowScene` at all. A sign-in
//  started from the second window could therefore terminate the app.
//
//  Two changes. The choice now prefers the scene the user is actually looking at, and a miss is
//  no longer fatal — the macOS branch has always fallen back rather than trapping, and showing a
//  sheet on the wrong window is recoverable where killing the app is not.
//
//  Pure and generic over the window type so the ordering can be tested without conjuring real
//  `UIScene`s, which is the reason this is not written inline in `Platform.swift`.
#if canImport(UIKit)
import UIKit

enum PresentationAnchorSelection {

    /// One scene, reduced to what the choice actually depends on.
    struct SceneCandidate<Window> {
        let activationState: UIScene.ActivationState
        /// In the order the scene reports them.
        let windows: [Window]
        /// The scene's key window, when it has one.
        let keyWindow: Window?

        init(activationState: UIScene.ActivationState, windows: [Window], keyWindow: Window? = nil) {
            self.activationState = activationState
            self.windows = windows
            self.keyWindow = keyWindow
        }
    }

    /// The best window to anchor to, or nil when there is genuinely none.
    ///
    /// Preference order, most specific first — the point is that a foreground scene always beats
    /// a background one, however the set happens to enumerate:
    ///   1. the key window of a foreground-active scene (what the user is looking at)
    ///   2. any window of a foreground-active scene
    ///   3. the same two, for a foreground-INACTIVE scene (mid-transition, still on screen)
    ///   4. any key window at all
    ///   5. any window at all
    static func choose<Window>(from scenes: [SceneCandidate<Window>]) -> Window? {
        for state in [UIScene.ActivationState.foregroundActive, .foregroundInactive] {
            let matching = scenes.filter { $0.activationState == state }
            if let key = matching.compactMap({ $0.keyWindow }).first { return key }
            if let any = matching.compactMap({ $0.windows.first }).first { return any }
        }
        if let key = scenes.compactMap({ $0.keyWindow }).first { return key }
        return scenes.compactMap({ $0.windows.first }).first
    }
}
#endif
