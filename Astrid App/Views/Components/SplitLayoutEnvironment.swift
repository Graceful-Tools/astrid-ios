import SwiftUI
import UIKit

/// Whether this window shows the split (iPad) layout — decided once, in `MainTabView`, by
/// `iPadPaneLayout.usesSplitLayout`, and read by the views below it that used to ask
/// `UIDevice.current.userInterfaceIdiom == .pad` themselves. An unfolded foldable iPhone reports
/// the phone idiom while showing the split layout, so the idiom is the wrong question (AITD-521).
///
/// Defaults to the idiom, for a view presented outside `MainTabView` (a sheet, a preview).
private struct UsesSplitLayoutKey: EnvironmentKey {
    static let defaultValue = UIDevice.current.userInterfaceIdiom == .pad
}

extension EnvironmentValues {
    var usesSplitLayout: Bool {
        get { self[UsesSplitLayoutKey.self] }
        set { self[UsesSplitLayoutKey.self] = newValue }
    }
}
