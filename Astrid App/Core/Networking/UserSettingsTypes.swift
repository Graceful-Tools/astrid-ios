//  UserSettingsTypes.swift
//  The wire shapes of `/api/v1/users/me/settings`: reminder settings, and the language the server
//  writes pushes and emails in (AITD-663).
//
//  Out of AstridAPIClient.swift because that file is under the source-size ratchet (AITD-346), and
//  these shapes are what a settings screen and `ServerLocaleSync` read, not part of the client.

import Foundation

struct UserSettingsResponse: Codable {
    let settings: UserSettingsData
    let meta: MetaInfo
}

struct UserSettingsData: Codable {
    /// One of the app's twelve locales as the server spells them (`zh-TW`, not `zh-Hant`), or nil
    /// when unknown — and nil from a server that predates the field (AITD-663).
    let locale: String?
    let reminderSettings: ReminderSettingsData
}

/// The body of `PUT /api/v1/users/me/settings` when only the language changes (AITD-663).
struct UpdateUserLocaleRequest: Encodable {
    let locale: String
}

struct ReminderSettingsData: Codable {
    let enablePushReminders: Bool
    let enableEmailReminders: Bool
    let defaultReminderTime: Int
    let enableDailyDigest: Bool
    let dailyDigestTime: String
    let dailyDigestTimezone: String
    let quietHoursStart: String?
    let quietHoursEnd: String?
}
