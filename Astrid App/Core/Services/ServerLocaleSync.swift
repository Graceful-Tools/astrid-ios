//  ServerLocaleSync.swift
//  Tells the server which language the user reads (AITD-663, astrid-web AWTD-1592).
//
//  The server writes push notifications and reminder / daily / weekly emails in `User.locale`, and
//  falls back to English while it is unknown. Web fills it from the signed-in page; nothing filled
//  it for someone who only uses the iOS or Mac app, so their emails stayed English. This sends the
//  app's language — the user's own choice in Settings, else the device's — after sign-in, on
//  launch, and when the language changes.
//
//  One request per change, not per launch: what was sent is recorded per account, and only a
//  reply that shows the server KEPT it is recorded. A server from before AWTD-1592 answers 200 and
//  ignores the field, and recording that would mean never sending again, even after the deploy
//  that adds the column.

import Foundation

@MainActor
final class ServerLocaleSync {
    static let shared = ServerLocaleSync()

    private let defaults: UserDefaults
    /// Launch reaches this twice: the auth check flipping `isAuthenticated`, and the launch task
    /// after it. One request is enough.
    private var isSending = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - The rules

    /// What one PUT taught the app.
    enum Outcome: Equatable {
        /// The server answered with a locale: it has the language.
        case stored
        /// 400: not a language the app ships. The contract says do not retry.
        case unsupported
        /// 200 with no `settings.locale`: a server that does not know the field yet.
        case notUnderstood
        /// Offline, signed out, a server error. Try again next launch.
        case failed

        /// Whether to remember this language as sent, so it is not offered again.
        var records: Bool { self == .stored || self == .unsupported }
    }

    nonisolated static func needsSending(language: String, recorded: String?) -> Bool {
        language != recorded
    }

    nonisolated static func recordKey(userId: String) -> String {
        "serverLocale.sent.\(userId)"
    }

    nonisolated static func outcome(serverLocale: String?) -> Outcome {
        serverLocale == nil ? .notUnderstood : .stored
    }

    nonisolated static func outcome(error: Error) -> Outcome {
        if case AstridAPIError.httpError(statusCode: 400, _) = error { return .unsupported }
        return .failed
    }

    // MARK: - Sending

    /// Fire and forget, for the places that do not wait: the language settings and sign-in.
    func languageChanged() {
        _Concurrency.Task { await syncIfNeeded() }
    }

    /// Sends the app's language when this account's server has not been told it yet.
    func syncIfNeeded() async {
        guard !isSending,
              ConnectionModeManager.shared.currentMode != .offlineOnly,
              AuthManager.shared.isAuthenticated,
              let userId = AuthManager.shared.currentUser?.id else { return }

        let language = LocalizationManager.shared.getCurrentLanguage()
        let key = Self.recordKey(userId: userId)
        guard Self.needsSending(language: language, recorded: defaults.string(forKey: key)) else { return }

        isSending = true
        defer { isSending = false }
        let outcome: Outcome
        do {
            let response = try await RemoteResourceService.shared.updateUserLocale(language)
            outcome = Self.outcome(serverLocale: response.settings.locale)
        } catch {
            outcome = Self.outcome(error: error)
        }
        AppLog.debug("🌍 [ServerLocaleSync] \(language): \(outcome)")
        if outcome.records {
            defaults.set(language, forKey: key)
        }
    }
}
