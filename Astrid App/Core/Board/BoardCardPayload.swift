import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Typed drag-drop payload for board task cards.
///
/// Using a custom Transferable instead of bare `String` ensures only
/// board-internal drops are accepted — drops from text fields, share
/// sheets, or universal clipboard sources won't trigger a board move.
/// Earlier the column dropDestination accepted any `plainText` payload,
/// which made drops feel "flaky" because system gestures occasionally
/// intercepted the drop.
struct BoardCardPayload: Codable, Transferable, Equatable {
    let taskId: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}
