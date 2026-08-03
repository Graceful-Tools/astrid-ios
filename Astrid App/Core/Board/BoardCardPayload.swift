import Foundation
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    /// The board's own drag type. Exported in Info.plist (`UTExportedTypeDeclarations`)
    /// so the system registers it; `BoardCardPayloadTests` pins the two together, because
    /// a drift between them breaks drag-and-drop with no compiler error.
    ///
    /// A frozen wire identifier, in the same family as `cc.astrid.app.sync` — not
    /// user-visible text, so it is not brand-dependent.
    static let astridBoardCard = UTType(exportedAs: "cc.astrid.board-card", conformingTo: .data)
}

/// Typed drag-drop payload for board task cards.
///
/// Using a custom Transferable instead of bare `String` ensures only
/// board-internal drops are accepted — drops from text fields, share
/// sheets, or universal clipboard sources won't trigger a board move.
/// Earlier the column dropDestination accepted any `plainText` payload,
/// which made drops feel "flaky" because system gestures occasionally
/// intercepted the drop.
///
/// The type has to be the app's OWN, though. This was declared `contentType: .data` —
/// that is `public.data`, the root of every binary type in the system, so a dragged card
/// had no identity to match on: the drop destination was offered any data blob and asked
/// to decode it as a board card. Anything that wasn't one failed to decode and the drop
/// was refused, which from the outside looks exactly like "dragging between columns isn't
/// working". (Task 3ed65a40)
struct BoardCardPayload: Codable, Transferable, Equatable {
    let taskId: String

    /// Spelled once, so the test can compare it against what Info.plist exports.
    static var contentType: UTType { .astridBoardCard }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: contentType)
    }
}
