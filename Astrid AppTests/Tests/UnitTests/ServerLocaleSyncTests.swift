//  ServerLocaleSyncTests.swift
//  AITD-663 — "[ios] Send the device language to the server, so pushes and reminder emails arrive
//  in it" (astrid-web AWTD-1592). The server now writes pushes and reminder/digest emails in
//  `User.locale`, which only web filled; an iOS- or Mac-only user stayed English. These pin when
//  the app sends its language and what it records once it has.

import XCTest
@testable import Astrid_App

final class ServerLocaleSyncTests: XCTestCase {

    // MARK: - When to send

    func testANeverSentLanguageIsSent_AITD663() {
        XCTAssertTrue(ServerLocaleSync.needsSending(language: "de", recorded: nil))
    }

    func testTheLanguageAlreadySentIsNotSentAgain_AITD663() {
        XCTAssertFalse(ServerLocaleSync.needsSending(language: "de", recorded: "de"),
                       "a request per launch for an answer the server already has")
    }

    func testAChangedLanguageIsSent_AITD663() {
        XCTAssertTrue(ServerLocaleSync.needsSending(language: "fr", recorded: "de"))
    }

    /// Recorded per account: signing in as someone else on the same device has to tell the server
    /// about THEM, whose `User.locale` is still unknown.
    func testWhatWasSentIsRecordedPerAccount_AITD663() {
        XCTAssertNotEqual(ServerLocaleSync.recordKey(userId: "a"), ServerLocaleSync.recordKey(userId: "b"))
    }

    // MARK: - What a reply teaches

    func testAServerThatAnswersWithTheLanguageStoredIt_AITD663() {
        XCTAssertEqual(ServerLocaleSync.outcome(serverLocale: "zh-TW"), .stored)
        XCTAssertTrue(ServerLocaleSync.Outcome.stored.records)
    }

    /// A server from before AWTD-1592 ignores `locale` and answers 200 without it. Recording that
    /// would stop the app from ever sending again, including after the deploy that adds the column.
    func testAServerThatDoesNotEchoTheLanguageHasNotStoredIt_AITD663() {
        XCTAssertEqual(ServerLocaleSync.outcome(serverLocale: nil), .notUnderstood)
        XCTAssertFalse(ServerLocaleSync.Outcome.notUnderstood.records)
    }

    /// A 400 is "not a language the app ships". The contract says do not retry, so it is recorded
    /// like a success: the same language is not offered again.
    func testAnUnsupportedLanguageIsNotRetried_AITD663() {
        let outcome = ServerLocaleSync.outcome(error: AstridAPIError.httpError(statusCode: 400, message: "Unsupported locale"))
        XCTAssertEqual(outcome, .unsupported)
        XCTAssertTrue(outcome.records)
    }

    func testAFailedRequestIsTriedAgainNextTime_AITD663() {
        for status in [401, 500, 503] {
            let outcome = ServerLocaleSync.outcome(error: AstridAPIError.httpError(statusCode: status, message: ""))
            XCTAssertEqual(outcome, .failed, "status \(status)")
            XCTAssertFalse(outcome.records)
        }
        XCTAssertFalse(ServerLocaleSync.outcome(error: URLError(.notConnectedToInternet)).records)
    }

    // MARK: - The wire

    func testTheRequestCarriesOnlyTheLocale_AITD663() throws {
        let data = try JSONEncoder().encode(UpdateUserLocaleRequest(locale: "de"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object as? [String: String], ["locale": "de"],
                       "a top-level `locale` beside, not inside, reminderSettings")
    }

    func testSettingsDecodeTheServersLocale_AITD663() throws {
        let response = try JSONDecoder().decode(UserSettingsResponse.self, from: Data(settingsJSON(locale: "\"zh-TW\"").utf8))
        XCTAssertEqual(response.settings.locale, "zh-TW")
    }

    /// An older server sends no `locale` at all, and the settings screen still has to decode.
    func testSettingsFromAnOlderServerStillDecode_AITD663() throws {
        let response = try JSONDecoder().decode(UserSettingsResponse.self, from: Data(settingsJSON(locale: nil).utf8))
        XCTAssertNil(response.settings.locale)
        XCTAssertTrue(response.settings.reminderSettings.enableEmailReminders)
    }

    private func settingsJSON(locale: String?) -> String {
        let localeField = locale.map { "\"locale\": \($0)," } ?? ""
        return """
        {"settings": {\(localeField) "reminderSettings": {"enablePushReminders": false,
          "enableEmailReminders": true, "defaultReminderTime": 15, "enableDailyDigest": false,
          "dailyDigestTime": "09:00", "dailyDigestTimezone": "UTC", "quietHoursStart": null,
          "quietHoursEnd": null}}, "meta": {"apiVersion": "v1", "authSource": "session"}}
        """
    }
}
