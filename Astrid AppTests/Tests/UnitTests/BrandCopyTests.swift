import XCTest
@testable import Astrid_App

/// Whitelabel (task 97208a72) — the reminder VOICE is configured once, on the server.
///
/// iOS shipped its own copy of Astrid's nags in ReminderConstants, entirely separate from
/// the web's `copy` block. A partner replacing "I die a little every time you ignore me"
/// had to do it twice, in two languages, and nothing kept the two in step.
///
/// The copy is cached locally on fetch rather than read live, because reminders fire
/// OFFLINE — a notification scheduled on a plane must still speak in the brand's voice —
/// and because notification scheduling does not run on the main actor.
final class BrandCopyTests: XCTestCase {

    private var store: BrandCopyStore!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // A dedicated suite so these tests never disturb the app's stored copy.
        defaults = UserDefaults(suiteName: "BrandCopyTests")!
        defaults.removePersistentDomain(forName: "BrandCopyTests")
        store = BrandCopyStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "BrandCopyTests")
        super.tearDown()
    }

    private func decodeCopy(_ json: String) throws -> ServerCapabilities {
        try JSONDecoder().decode(ServerCapabilities.self, from: Data(json.utf8))
    }

    // MARK: - Falling back to the built-in voice

    func testWithNothingStoredTheBuiltInVoiceIsUsed() {
        XCTAssertNil(store.reminders(.general))
        XCTAssertNil(store.reminders(.due))
        XCTAssertNil(store.reminders(.responses))
    }

    /// A deployment that overrides nothing sends no copy block, and the app keeps
    /// Astrid's set. That is the common case and must cost nothing.
    func testAServerWithNoCopyBlockLeavesTheBuiltInVoiceAlone() throws {
        let caps = try decodeCopy(#"{"brand":{"appName":"Astrid"}}"#)
        store.store(caps.copy)

        XCTAssertNil(store.reminders(.general))
        XCTAssertFalse(ReminderConstants.reminders.isEmpty)
        XCTAssertTrue(ReminderConstants.reminders.contains { $0.contains("Have a sec") })
    }

    // MARK: - Adopting a brand voice

    func testStoresAndReturnsABrandVoice() throws {
        let caps = try decodeCopy("""
        {"copy":{"reminders":{"general":["A moment?","Got a sec?"],"due":["It is time."]}}}
        """)
        store.store(caps.copy)

        XCTAssertEqual(store.reminders(.general), ["A moment?", "Got a sec?"])
        XCTAssertEqual(store.reminders(.due), ["It is time."])
        XCTAssertNil(store.reminders(.responses), "an unsupplied set keeps the built-in voice")
    }

    /// The point of persisting: a reminder scheduled offline, days later, still speaks
    /// in the brand's voice. A fresh store over the same defaults must see it.
    func testTheVoiceSurvivesRelaunch() throws {
        let caps = try decodeCopy(#"{"copy":{"reminders":{"general":["A moment?"]}}}"#)
        store.store(caps.copy)

        let afterRelaunch = BrandCopyStore(defaults: defaults)
        XCTAssertEqual(afterRelaunch.reminders(.general), ["A moment?"])
    }

    /// A deployment that drops its override must revert the app to the built-in voice,
    /// not leave the previous brand's nags cached forever.
    func testClearingTheOverrideRevertsToTheBuiltInVoice() throws {
        store.store(try decodeCopy(#"{"copy":{"reminders":{"general":["A moment?"]}}}"#).copy)
        XCTAssertNotNil(store.reminders(.general))

        store.store(try decodeCopy(#"{"brand":{"appName":"Astrid"}}"#).copy)
        XCTAssertNil(store.reminders(.general), "a withdrawn override must not persist")
    }

    // MARK: - Untrusted input

    /// An empty set is "not supplied", matching the web's rule. A brand that wants no
    /// nags should turn reminders off, not ship an empty set that fires a blank
    /// notification.
    func testAnEmptySetIsTreatedAsNotSupplied() throws {
        let caps = try decodeCopy(#"{"copy":{"reminders":{"general":[]}}}"#)
        store.store(caps.copy)

        XCTAssertNil(store.reminders(.general))
    }

    func testBlankAndOverlongStringsAreDropped() throws {
        let huge = String(repeating: "A", count: 1_000)
        let caps = try decodeCopy(#"{"copy":{"reminders":{"general":["  ","Real one","\#(huge)"]}}}"#)
        store.store(caps.copy)

        XCTAssertEqual(store.reminders(.general), ["Real one"])
    }

    /// If sanitizing removes everything, the set is not supplied — better the built-in
    /// voice than a notification body that is empty.
    func testASetThatSanitizesToNothingFallsBack() throws {
        let caps = try decodeCopy(#"{"copy":{"reminders":{"general":["   ",""]}}}"#)
        store.store(caps.copy)

        XCTAssertNil(store.reminders(.general))
    }

    /// Unbounded storage from an unauthenticated endpoint is a denial-of-service, not a
    /// brand voice.
    func testTheNumberOfNagsIsBounded() throws {
        let many = (0..<500).map { "\"nag \($0)\"" }.joined(separator: ",")
        let caps = try decodeCopy("{\"copy\":{\"reminders\":{\"general\":[\(many)]}}}")
        store.store(caps.copy)

        let stored = store.reminders(.general)
        XCTAssertNotNil(stored)
        XCTAssertLessThanOrEqual(stored!.count, BrandCopyStore.maxSetSize)
    }

    // MARK: - Wiring

    /// ReminderConstants is what actually schedules the notification text.
    func testReminderConstantsSpeakInTheStoredVoice() throws {
        let shared = BrandCopyStore.shared
        let saved = shared.reminders(.general)
        defer { shared.replaceForTesting(general: saved) }

        shared.replaceForTesting(general: ["Only nag"])
        XCTAssertEqual(ReminderConstants.reminders, ["Only nag"])
        XCTAssertEqual(ReminderConstants.getRandomReminderString(), "Only nag")

        shared.replaceForTesting(general: nil)
        XCTAssertTrue(ReminderConstants.reminders.count > 1, "reverts to the built-in set")
    }
}
