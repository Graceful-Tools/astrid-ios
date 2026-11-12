import AstridCore
import Foundation

/// The astrid-core command behind `ServerCapabilityService` (task 97208a72, moved in AITD-620).
///
/// Online-only: what a deployment offers is its build-time configuration. The core fetches
/// `GET /api/v1/capabilities`, keeps the answer in its cache (its `FeedbackListId` reads it), and
/// answers the route's `capabilities` object unwrapped — the shape `ServerCapabilities` decodes.
enum ServerCapabilityCommands {
    static func refresh() -> CoreCommand {
        CoreCommand(kind: "refreshCapabilities")
    }
}
