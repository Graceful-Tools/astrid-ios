//  RowZoomTransition.swift
//  Full-screen task details zoom out of the tapped row (AITD-609, register DS7). The rule for when
//  lives in `DetailPanelChrome.zoomsFromRow`; this only applies it, so a push with no row to grow
//  out of (quick add, deep links) keeps the ordinary slide. Since AITD-664 the rule says no zoom at
//  all: a row pushes with the slide a board card uses.

import SwiftUI

#if os(iOS)  // The "Astrid App" folder also builds into the Mac, which has no navigation zoom.
extension View {
    /// The pushed details' side: zoom out of the row registered under `sourceId`, when there is one.
    @ViewBuilder
    func zoomsOutOfRow(_ sourceId: String?, in namespace: Namespace.ID) -> some View {
        if let sourceId {
            navigationTransition(.zoom(sourceID: sourceId, in: namespace))
        } else {
            self
        }
    }
}
#endif
