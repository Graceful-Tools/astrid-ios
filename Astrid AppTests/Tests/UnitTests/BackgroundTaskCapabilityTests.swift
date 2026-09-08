import XCTest
@testable import Astrid_App

/// Regression for Astrid task fda7a84a-4542-46ab-b77a-3fc56fad3c93.
///
/// `BGTaskScheduler.submit` throws `.unavailable` unless the app declares the
/// background mode the request type needs — `processing` for a
/// `BGProcessingTaskRequest`. The app listed its identifier under
/// `BGTaskSchedulerPermittedIdentifiers` and submitted the request, but declared
/// no `UIBackgroundModes` at all, so every submit threw, the throw was only
/// logged, and no backgrounded sync had ever run: pending Outbox work waited for
/// the next foreground.
///
/// The pairing is what the test pins. Either half alone is silently useless, and
/// the half that was missing is the one nothing else in the build would complain
/// about.
final class BackgroundTaskCapabilityTests: XCTestCase {
    private static let infoPlists = ["Info.plist", "Info-Debug.plist"]

    /// Every `BGProcessingTaskRequest` identifier the app is permitted to submit
    /// needs `processing` in `UIBackgroundModes`, in Debug and Release alike.
    func testPermittedBackgroundTaskIdentifiersAreBackedByTheProcessingMode() throws {
        for name in Self.infoPlists {
            let plist = try plist(named: name)
            let identifiers = plist["BGTaskSchedulerPermittedIdentifiers"] as? [String] ?? []
            guard !identifiers.isEmpty else { continue }

            let modes = plist["UIBackgroundModes"] as? [String] ?? []
            XCTAssertTrue(
                modes.contains("processing"),
                """
                \(name) permits background task identifier(s) \(identifiers) but does not \
                declare "processing" in UIBackgroundModes, so BGTaskScheduler.submit \
                throws .unavailable and the task never runs. UIBackgroundModes is \
                currently \(modes.isEmpty ? "absent" : String(describing: modes)).
                """
            )
        }
    }

    /// The scheduler only ever hands back an identifier the app registered, so a
    /// mode declared without a matching identifier is dead weight in App Store
    /// review — and a sign someone removed the wrong half.
    func testProcessingModeIsNotDeclaredWithoutATaskToRun() throws {
        for name in Self.infoPlists {
            let plist = try plist(named: name)
            let modes = plist["UIBackgroundModes"] as? [String] ?? []
            guard modes.contains("processing") else { continue }

            let identifiers = plist["BGTaskSchedulerPermittedIdentifiers"] as? [String] ?? []
            XCTAssertFalse(
                identifiers.isEmpty,
                "\(name) declares the processing background mode but permits no task identifiers"
            )
        }
    }

    /// The identifier the handler registers and submits has to be one the system
    /// permits, or `register` traps at launch.
    func testTheSyncIdentifierIsPermitted() throws {
        for name in Self.infoPlists {
            let identifiers = try plist(named: name)["BGTaskSchedulerPermittedIdentifiers"] as? [String] ?? []
            XCTAssertTrue(
                identifiers.contains(BackgroundSyncHandler.syncTaskIdentifier),
                "\(name) does not permit \(BackgroundSyncHandler.syncTaskIdentifier)"
            )
        }
    }

    private func plist(named name: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UnitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Astrid AppTests
            .deletingLastPathComponent()   // repository root
        let data = try Data(contentsOf: root.appendingPathComponent(name))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}
