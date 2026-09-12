//  AppUpdateServiceTests.swift
//  Tests for AITD-383 — the service half of the "Update" CTA.
//
//  AppVersionCheckTests covers the arithmetic; these cover the behaviour around it: what the app
//  does when the endpoint is not there, what it does with a URL it was handed over the network,
//  and what "not now" actually remembers.

import XCTest
@testable import Astrid_App

@MainActor
final class AppUpdateServiceTests: XCTestCase {

    /// A UserDefaults nobody else is using, so a dismissal in one test cannot silence another.
    private func scratchDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "AppUpdateServiceTests.\(name)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    private func response(_ latest: String?, url: String? = "https://apps.apple.com/app/id123",
                          notes: String? = nil) -> AppVersionResponse {
        AppVersionResponse(latestVersion: latest, minimumVersion: nil,
                           updateUrl: url, releaseNotes: notes)
    }

    private func service(current: String, defaults: UserDefaults,
                         fetch: @escaping (String) async throws -> AppVersionResponse) -> AppUpdateService {
        let service = AppUpdateService(userDefaults: defaults, fetch: fetch)
        service.currentVersionOverride = current
        return service
    }

    // MARK: - The state this will actually ship into

    /// astrid-web deploys by hand, so `/api/v1/app-version` will 404 for a while after this lands.
    /// That must be indistinguishable from "you are up to date": no card, no error, nothing.
    func testAMissingEndpointSaysNothing() async {
        struct NotFound: Error {}
        let service = service(current: "1.9.1", defaults: scratchDefaults()) { _ in throw NotFound() }
        await service.checkForUpdate()
        XCTAssertNil(service.availableUpdate,
                     "AITD-383: a failed check means silence, not a banner")
    }

    /// A body that decodes but says nothing useful is the same kind of nothing.
    func testAnEmptyAnswerSaysNothing() async {
        let service = service(current: "1.9.1", defaults: scratchDefaults()) { _ in self.response(nil) }
        await service.checkForUpdate()
        XCTAssertNil(service.availableUpdate)
    }

    // MARK: - The happy path

    func testANewerVersionProducesTheCard() async {
        let service = service(current: "1.9.1", defaults: scratchDefaults()) { _ in
            self.response("1.9.2", notes: "Fixes")
        }
        await service.checkForUpdate()
        XCTAssertEqual(service.availableUpdate?.version, "1.9.2")
        XCTAssertEqual(service.availableUpdate?.releaseNotes, "Fixes")
    }

    /// The report's own trap: internal builds run ahead of the store.
    func testABuildAheadOfTheStoreProducesNoCard() async {
        let service = service(current: "1.9.5", defaults: scratchDefaults()) { _ in self.response("1.9.2") }
        await service.checkForUpdate()
        XCTAssertNil(service.availableUpdate)
    }

    // MARK: - No destination, no card

    /// There is no App Store id in this repository, so the app cannot invent where to send people.
    /// An update nobody can act on is not worth interrupting for.
    func testAnUpdateWithNoDestinationIsNotOffered() async {
        let service = service(current: "1.9.1", defaults: scratchDefaults()) { _ in
            self.response("1.9.2", url: nil)
        }
        await service.checkForUpdate()
        XCTAssertNil(service.availableUpdate,
                     "AITD-383: without a URL from the server there is nowhere to send anyone")
    }

    /// This string arrives over the network and ends up in `openURL`. "Open whatever the server
    /// said" is not something to hand a client.
    func testOnlyRealStoreAndWebSchemesAreAccepted() {
        XCTAssertNotNil(AppUpdateService.updateURL(from: "https://apps.apple.com/app/id123"))
        XCTAssertNotNil(AppUpdateService.updateURL(from: "macappstore://apps.apple.com/app/id123"))
        XCTAssertNil(AppUpdateService.updateURL(from: "javascript:alert(1)"))
        XCTAssertNil(AppUpdateService.updateURL(from: "file:///etc/passwd"))
        XCTAssertNil(AppUpdateService.updateURL(from: nil))
    }

    // MARK: - "Not now"

    func testDismissingClearsTheCardAndIsRemembered() async {
        let defaults = scratchDefaults()
        let first = service(current: "1.9.1", defaults: defaults) { _ in self.response("1.9.2") }
        await first.checkForUpdate()
        XCTAssertNotNil(first.availableUpdate)
        first.dismiss()
        XCTAssertNil(first.availableUpdate)

        // A fresh launch, same answer from the server: stays quiet.
        let second = service(current: "1.9.1", defaults: defaults) { _ in self.response("1.9.2") }
        await second.checkForUpdate()
        XCTAssertNil(second.availableUpdate, "AITD-383: 'not now' has to survive a relaunch")
    }

    /// One dismissal must not turn the feature off for good.
    func testDismissingOneVersionDoesNotSilenceTheNext() async {
        let defaults = scratchDefaults()
        let first = service(current: "1.9.1", defaults: defaults) { _ in self.response("1.9.2") }
        await first.checkForUpdate()
        first.dismiss()

        let second = service(current: "1.9.1", defaults: defaults) { _ in self.response("1.9.3") }
        await second.checkForUpdate()
        XCTAssertEqual(second.availableUpdate?.version, "1.9.3",
                       "AITD-383: dismissing 1.9.2 was an answer about 1.9.2")
    }

    // MARK: - It only asks once

    func testItChecksOncePerLaunch() async {
        var calls = 0
        let service = service(current: "1.9.1", defaults: scratchDefaults()) { _ in
            calls += 1
            return self.response("1.9.2")
        }
        await service.checkForUpdate()
        await service.checkForUpdate()
        await service.checkForUpdate()
        XCTAssertEqual(calls, 1, "the modifier calls this on every appearance; it must not poll")
    }
}
