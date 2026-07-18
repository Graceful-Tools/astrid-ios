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

    func report(_ context: String, _ error: Error) {
        show("\(context): \(error.localizedDescription)")
    }

    func clear() { dismiss?.cancel(); current = nil }
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
