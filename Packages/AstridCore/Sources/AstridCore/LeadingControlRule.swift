import Foundation

/// What a task's leading control shows and what tapping it does — astrid-core's row projection
/// (`rows::LeadingControl::for_task` and `::action`, asked through the `rows` rule with one task;
/// AITD-622 / AITD-656 / AITD-672).
///
/// The two rules follow iOS exactly since core `e0d8ce7` (AWTD2-214, CONTRACTS D62/D63): someone
/// else's task opens the picker on every surface (AITD-375), a list row or the detail completes
/// only when the control IS a checkbox (AITD-382), and a board card always opens the picker.
public struct LeadingControlAnswer: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case checkbox
        case avatar(String)
        case unassigned
        /// A public-list task the reader can only copy. Never answered here: no lists cross, so
        /// the core has no public list to see. Kept so a newer core cannot fail the decode.
        case copy
    }

    public enum Action: String, Decodable, Equatable, Sendable {
        case complete, openPicker, copy
    }

    public let kind: Kind
    public let action: Action

    public init(kind: Kind, action: Action) {
        self.kind = kind
        self.action = action
    }
}

extension CoreRules {
    /// The leading control for a task assigned to `assigneeId` (nil or empty: nobody), drawn for
    /// `currentUserId` on `surface` (`listRow` /
    /// `boardCard` / `detail`). Nil only when the core could not answer; the caller picks the
    /// safe fallback.
    public static func leadingControl(assigneeId: String?, currentUserId: String?,
                                      surface: String) -> LeadingControlAnswer? {
        let request = LeadingRowsRequest(
            tasks: [.init(assigneeId: assigneeId?.isEmpty == false ? assigneeId : nil)],
            currentUserId: currentUserId, surface: surface, now: Date())
        guard let row = (try? ask(request, as: LeadingRowsAnswer.self))?.rows.first else { return nil }
        return LeadingControlAnswer(kind: row.leading.kind, action: row.action)
    }
}

private struct LeadingRowsRequest: Encodable {
    struct OneTask: Encodable {
        // The id and title are placeholders: only the assignee decides the control. Never
        // completed, so the default completion filter cannot drop the one row asked about.
        let id = "leading-control"
        let title = ""
        let completed = false
        let assigneeId: String?
    }

    let kind = "rows"
    let tasks: [OneTask]
    let currentUserId: String?
    let surface: String
    let now: Date
}

private struct LeadingRowsAnswer: Decodable {
    struct Row: Decodable {
        struct Leading: Decodable {
            let kind: LeadingControlAnswer.Kind

            private enum Key: String, CodingKey { case kind, userId }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: Key.self)
                switch try container.decode(String.self, forKey: .kind) {
                case "checkbox": kind = .checkbox
                case "avatar": kind = .avatar(try container.decode(String.self, forKey: .userId))
                case "copy": kind = .copy
                default: kind = .unassigned
                }
            }
        }

        let leading: Leading
        let action: LeadingControlAnswer.Action
    }

    let rows: [Row]
}
