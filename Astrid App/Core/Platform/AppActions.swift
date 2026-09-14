//  AppActions.swift
//  Astrid — one place to surface write failures instead of swallowing them.
//
//  Originally MacErrorCenter / MacActions / MacFailureCopy, Mac-only and behind
//  `#if os(macOS)` (task 8a5f3066). Mac views broadly used `_ = try? await service…`, so a failed
//  task/list/member/comment/chat write vanished silently while the input or sheet cleared anyway,
//  leaving the user sure it had saved.
//
//  Promoted here (AITD-400) because that guarantee is not a Mac idea. iOS had no global error
//  surface then, so the only way for it to adopt the same rule was to write a second copy of
//  this — which is the drift this file now prevents rather than creates. Nothing about the Mac's
//  behaviour changed in the move: same banner, same auto-dismiss, same verb-to-copy mapping.
//
//  iOS is wired to the banner as of AITD-406, but to FAR fewer call sites than the Mac, and the
//  asymmetry is deliberate. Most iOS writes go through the Outbox: they write optimistically,
//  enqueue, and drain on reconnect, so a network failure is a queued row rather than an error.
//  Reporting those would tell someone editing offline that their edit was lost when it was not.
//  Only the writes with no Outbox behind them — list and member writes, which hit the API
//  directly — reach this banner on iOS. `IOSSilentWriteGuardTests` pins both halves of that.

import Foundation
import Combine

@MainActor
final class AppErrorCenter: ObservableObject {
    static let shared = AppErrorCenter()

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

    /// The banner is user-facing, so it must be translated. The 100-odd call-site contexts
    /// ("Save due date", "Delete subtask", …) are developer strings — they stay English and go to
    /// the log, while the banner shows the localized category plus whatever the server said
    /// (task 29b673c0).
    func report(_ context: String, _ error: Error) {
        NSLog("[Astrid] %@ failed: %@", context, error.localizedDescription)
        show("\(FailureCopy.message(for: context)): \(error.localizedDescription)")
    }

    func clear() { dismiss?.cancel(); current = nil }
}

/// Which localized "that didn't work" line a call-site context maps to. Grouping by the verb
/// keeps one translated sentence per kind of failure instead of a hundred near-identical ones,
/// and the exact operation is still in the log for whoever is debugging.
///
/// The keys are still spelled `mac.failed.*`: the COPY is platform-neutral ("Couldn't save your
/// changes"), so renaming them would churn twelve translation files to say the same thing.
enum FailureCopy {
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

/// Run an async write and surface any failure via `AppErrorCenter` (replaces `try?` swallowing).
@MainActor
enum AppActions {
    static func perform(_ context: String, _ op: @escaping () async throws -> Void) {
        _Concurrency.Task {
            do { try await op() }
            catch { AppErrorCenter.shared.report(context, error) }
        }
    }
}
