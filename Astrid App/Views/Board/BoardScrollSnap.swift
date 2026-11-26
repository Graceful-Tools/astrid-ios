import SwiftUI

/// How a board's sideways scroll settles, on iPad and on the Mac (ADEV-315).
///
/// `.byColumn` is `.viewAligned(limitBehavior: .alwaysByOne)`: ONE swipe moves ONE column and the
/// board settles on that column's leading edge. Plain `.viewAligned` snaps to whichever column
/// edge the fling happens to land nearest, so on a multi-column board a normal-length swipe often
/// does not travel far enough to reach the next edge and springs back to where it started — which
/// reads as the board ignoring you until you swipe several times.
///
/// `.page`: a single column fills the container, so a page and a column are the same distance and
/// paging already moves exactly one.
nonisolated enum BoardScrollSnap: Equatable, Sendable {
    case byColumn
    case page

    init(multiColumn: Bool) {
        self = multiColumn ? .byColumn : .page
    }
}

/// SwiftUI's `.paging` and `.viewAligned` scroll-target behaviors are different opaque types, so
/// they can't be switched with a ternary. Apply to the horizontal `ScrollView` whose content
/// carries `.scrollTargetLayout()`.
struct BoardScrollSnapModifier: ViewModifier {
    let snap: BoardScrollSnap

    init(_ snap: BoardScrollSnap) { self.snap = snap }
    init(multiColumn: Bool) { self.snap = BoardScrollSnap(multiColumn: multiColumn) }

    func body(content: Content) -> some View {
        switch snap {
        case .byColumn:
            if #available(iOS 18.0, macOS 15.0, *) {
                content.scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            } else {
                // macOS 14 (the Mac's floor) has no `.alwaysByOne`: snap to the nearest column edge.
                content.scrollTargetBehavior(.viewAligned)
            }
        case .page: content.scrollTargetBehavior(.paging)
        }
    }
}
