//  MacErrorCenter.swift
//  Astrid for Mac — one place to surface write failures instead of swallowing them (Task 8a5f3066).
//
//  Mac views broadly used `_ = try? await service…`, so a failed task/list/member/comment/chat
//  write vanished silently (and inputs/sheets often cleared regardless). MacActions.perform runs
//  the work and, on failure, reports a transient banner via MacErrorCenter.

#if os(macOS)
import Foundation
import Combine

@MainActor
final class MacErrorCenter: ObservableObject {
    static let shared = MacErrorCenter()

    struct Banner: Identifiable, Equatable { let id = UUID(); let text: String }
    @Published var current: Banner?

    private var dismiss: _Concurrency.Task<Void, Never>?

    /// Show a transient error banner (auto-dismisses).
    func show(_ text: String) {
        current = Banner(text: text)
        dismiss?.cancel()
        dismiss = _Concurrency.Task { [weak self] in
            try? await _Concurrency.Task.sleep(nanoseconds: 5_000_000_000)
            if !_Concurrency.Task.isCancelled { self?.current = nil }
        }
    }

    /// The banner is user-facing, so it must be translated. The 60-odd call-site contexts
    /// ("Save due date", "Delete subtask", …) are developer strings — they stay English and go to
    /// the log, while the banner shows the localized category plus whatever the server said
    /// (task 29b673c0).
    func report(_ context: String, _ error: Error) {
        NSLog("[Astrid] %@ failed: %@", context, error.localizedDescription)
        show("\(MacFailureCopy.message(for: context)): \(error.localizedDescription)")
    }

    func clear() { dismiss?.cancel(); current = nil }
}

/// Which localized "that didn't work" line a call-site context maps to. Grouping by the verb
/// keeps one translated sentence per kind of failure instead of 60 near-identical ones, and the
/// exact operation is still in the log for whoever is debugging.
enum MacFailureCopy {
    static func message(for context: String) -> String {
        let verb = context.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        switch verb {
        case "delete", "remove":
            return NSLocalizedString("mac.failed.delete", comment: "")
        case "complete":
            return NSLocalizedString("mac.failed.complete", comment: "")
        case "add", "create", "register", "invite", "post", "attach", "link", "enable":
            return NSLocalizedString("mac.failed.create", comment: "")
        case "save", "update", "rename", "change", "set", "reorder", "edit", "move", "make", "disable":
            return NSLocalizedString("mac.failed.save", comment: "")
        default:
            return NSLocalizedString("mac.failed.generic", comment: "")
        }
    }
}

/// Run an async write and surface any failure via MacErrorCenter (replaces `try?` swallowing).
@MainActor
enum MacActions {
    static func perform(_ context: String, _ op: @escaping () async throws -> Void) {
        _Concurrency.Task {
            do { try await op() }
            catch { MacErrorCenter.shared.report(context, error) }
        }
    }
}
#endif
