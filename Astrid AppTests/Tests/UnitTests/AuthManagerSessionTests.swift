//  AuthManagerSessionTests.swift
//  `AuthManager.signOut`, `checkAuthentication` and the background session check, run for real
//  (AITD-535). Until now nothing called `signOut` under test: `UserDataIsolationTests` performed
//  the clearing by hand and then checked it, so a step dropped from the real sign-out never failed.
//
//  Every piece of state the manager touches is a scratch copy — its own keychain service, defaults
//  suite, cookie jar, journal file and in-memory core — so the host app's session is never wiped.

import AstridCore
import XCTest
@testable import Astrid_App

@MainActor
final class AuthManagerSessionTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var keychain: KeychainService!
    private var cookies: HTTPCookieStorage!
    private var journalURL: URL!
    private var core: CoreSession!
    private var connected = true
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        StubURLProtocol.reset()
        suiteName = "AuthManagerSessionTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        keychain = KeychainService(service: "cc.astrid.tests.\(UUID().uuidString)")
        cookies = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: suiteName)
        journalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("auth-outbox-\(UUID().uuidString).json")
        core = try CoreSearchFixture.session(seeding: [])
        connected = true
    }

    override func tearDown() async throws {
        try? keychain.deleteSessionCookie()
        keychain.deleteOAuthClientSecret()
        try? keychain.deleteOAuthAccessToken()
        for cookie in cookies.cookies ?? [] { cookies.deleteCookie(cookie) }
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: journalURL)
        StubURLProtocol.reset()
    }

    private func manager() -> AuthManager {
        AuthManager(apiClient: AstridAPIClient(session: StubURLProtocol.session()), keychainService: keychain,
                    defaults: defaults, cookieStorage: cookies, journalFileURL: journalURL,
                    isConnected: { [unowned self] in self.connected }, core: { [unowned self] in self.core })
    }

    private func cookie(domain: String, name: String) throws -> HTTPCookie {
        try XCTUnwrap(HTTPCookie(properties: [.domain: domain, .path: "/", .name: name, .value: "v"]))
    }

    private func cacheServerUser(_ id: String = "usr_1") {
        defaults.set(id, forKey: Constants.UserDefaults.userId)
        defaults.set("ada@example.com", forKey: Constants.UserDefaults.userEmail)
        defaults.set("Ada", forKey: Constants.UserDefaults.userName)
    }

    nonisolated private static func sessionJSON(id: String = "usr_1", name: String = "Ada Lovelace") -> StubURLProtocol.Answer {
        .json(#"{"user":{"id":"\#(id)","email":"ada@example.com","name":"\#(name)"}}"#)
    }

    private func unsentWrites() async throws -> Int {
        let stats = try await core.run(CoreCommand(kind: "outboxStats"), as: JournalStats.self)
        return stats.pending + stats.running + stats.failed
    }

    // MARK: - signOut

    func testSignOutClearsEveryStoreTheDepartingUserLeft_AITD535() async throws {
        try keychain.saveSessionCookie("__Secure-next-auth.session-token=abc")
        keychain.saveOAuthClientSecret("secret")
        try keychain.saveOAuthAccessToken("token")
        cacheServerUser()
        defaults.set(true, forKey: "reminderPushEnabled")
        defaults.set(["t1": "1"], forKey: "githubTaskLinkCache")
        defaults.set(t0, forKey: "githubLastFullPull:link-1")
        defaults.set("kept", forKey: "unrelatedDeviceSetting")
        cookies.setCookie(try cookie(domain: ".\(Brand.host)", name: "brand"))
        cookies.setCookie(try cookie(domain: "example.com", name: "other"))
        try Data("[]".utf8).write(to: journalURL)
        let queued = OutboxEntry(
            id: "a", kind: "createTask",
            payload: try JSONEncoder().encode(CreateTaskOutboxPayload(title: "Offline", listIds: ["l1"], tempId: "temp_a")),
            clientRequestId: "crid-a", dependsOn: [], status: .pending, attempts: 0,
            nextAttemptAt: t0, lastError: nil, createdAt: t0, updatedAt: t0)
        let scratchJournal = FileManager.default.temporaryDirectory
            .appendingPathComponent("auth-import-\(UUID().uuidString).json")
        try OutboxStore(fileURL: scratchJournal).save([queued])
        _ = CoreUpgrade.importJournal(core, fileURL: scratchJournal)
        let queuedBefore = try await unsentWrites()
        XCTAssertEqual(queuedBefore, 1, "precondition: the departing user has a write in the core's journal")

        let auth = manager()
        auth.isAuthenticated = true
        auth.currentUser = User(id: "usr_1", email: "ada@example.com", name: "Ada", image: nil)
        try await auth.signOut()

        let sent = StubURLProtocol.requests.map { "\($0.method ?? "") \($0.path ?? "")" }
        XCTAssertEqual(sent, ["DELETE /api/v1/auth/signout"])
        XCTAssertThrowsError(try keychain.getSessionCookie(), "the session cookie is gone")
        XCTAssertNil(keychain.getOAuthClientSecret())
        XCTAssertThrowsError(try keychain.getOAuthAccessToken())
        for key in [Constants.UserDefaults.userId, Constants.UserDefaults.userEmail, Constants.UserDefaults.userName,
                    "reminderPushEnabled", "githubTaskLinkCache", "githubLastFullPull:link-1"] {
            XCTAssertNil(defaults.object(forKey: key), "\(key) belongs to the departing user")
        }
        XCTAssertEqual(defaults.string(forKey: "unrelatedDeviceSetting"), "kept", "only per-user keys go")
        XCTAssertEqual(cookies.cookies?.map(\.name), ["other"], "brand cookies go, other sites' stay")
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path), "a leftover outbox.json goes")
        let queuedAfter = try await unsentWrites()
        XCTAssertEqual(queuedAfter, 0, "the core's journal is wiped, so the next session cannot replay it")
        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertNil(auth.currentUser)
        XCTAssertFalse(auth.isLoading)
    }

    func testSignOutStillClearsLocallyWhenTheServerCannotBeReached_AITD535() async throws {
        StubURLProtocol.respond = { _ in .failure(URLError(.notConnectedToInternet)) }
        try keychain.saveSessionCookie("session=abc")
        cacheServerUser()

        let auth = manager()
        auth.isAuthenticated = true
        try await auth.signOut()

        XCTAssertThrowsError(try keychain.getSessionCookie())
        XCTAssertNil(defaults.string(forKey: Constants.UserDefaults.userId))
        XCTAssertFalse(auth.isAuthenticated)
    }

    // MARK: - checkAuthentication

    func testACachedUserWithACookieIsSignedInOfflineWithoutAskingTheServer_AITD535() async throws {
        connected = false
        try keychain.saveSessionCookie("session=abc")
        cacheServerUser()

        let auth = manager()
        await auth.checkAuthentication()

        XCTAssertTrue(auth.isAuthenticated, "offline first: the cached user is signed in at once")
        XCTAssertFalse(auth.isCheckingAuth)
        XCTAssertEqual(auth.currentUser?.id, "usr_1")
        XCTAssertEqual(auth.currentUser?.name, "Ada")
        await auth.validateSessionInBackground()
        XCTAssertTrue(StubURLProtocol.requests.isEmpty, "no network, so no validation is attempted")
        XCTAssertTrue(auth.isAuthenticated, "and no network does not sign anyone out")
    }

    func testACachedUserWhoseCookieIsGoneIsSignedOutAndTheCacheCleared_AITD535() async throws {
        cacheServerUser()

        let auth = manager()
        await auth.checkAuthentication()

        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertNil(auth.currentUser)
        XCTAssertNil(defaults.string(forKey: Constants.UserDefaults.userId), "the stale user is cleared")
        XCTAssertNil(defaults.string(forKey: Constants.UserDefaults.userEmail))
    }

    func testACookieWithNoCachedUserIsValidatedAndTheUserCached_AITD535() async throws {
        StubURLProtocol.respond = { _ in Self.sessionJSON() }
        try keychain.saveSessionCookie("session=abc")

        let auth = manager()
        await auth.checkAuthentication()

        XCTAssertEqual(StubURLProtocol.requests.map(\.path), ["/api/v1/auth/mobile-session"])
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertEqual(auth.currentUser?.id, "usr_1")
        XCTAssertEqual(defaults.string(forKey: Constants.UserDefaults.userId), "usr_1")
        XCTAssertEqual(defaults.string(forKey: Constants.UserDefaults.userName), "Ada Lovelace")
    }

    func testNoCookieAndNoCachedUserIsSignedOutWithoutARequest_AITD535() async throws {
        let auth = manager()
        await auth.checkAuthentication()

        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertFalse(auth.isCheckingAuth)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    // MARK: - Background validation

    func testASessionTheServerRejectsSignsTheUserOut_AITD535() async throws {
        StubURLProtocol.respond = { _ in .json(#"{"error":"Unauthorized"}"#, status: 401) }
        try keychain.saveSessionCookie("session=abc")
        cacheServerUser()
        let auth = manager()
        auth.isAuthenticated = true

        await auth.validateSessionInBackground()

        XCTAssertFalse(auth.isAuthenticated, "a 401 is the server saying the session is over")
        XCTAssertThrowsError(try keychain.getSessionCookie())
        XCTAssertNil(defaults.string(forKey: Constants.UserDefaults.userId))
    }

    func testAServerErrorKeepsTheUserSignedIn_AITD535() async throws {
        StubURLProtocol.respond = { _ in .json(#"{"error":"boom"}"#, status: 500) }
        try keychain.saveSessionCookie("session=abc")
        cacheServerUser()
        let auth = manager()
        auth.isAuthenticated = true

        await auth.validateSessionInBackground()

        XCTAssertTrue(auth.isAuthenticated, "a 500 says nothing about the session")
        XCTAssertNoThrow(try keychain.getSessionCookie())
        XCTAssertEqual(defaults.string(forKey: Constants.UserDefaults.userId), "usr_1")
    }

    func testAValidatedSessionRefreshesTheCachedUser_AITD535() async throws {
        StubURLProtocol.respond = { _ in Self.sessionJSON(name: "Ada Byron") }
        try keychain.saveSessionCookie("session=abc")
        cacheServerUser()
        let auth = manager()
        auth.isAuthenticated = true

        await auth.validateSessionInBackground()

        XCTAssertEqual(auth.currentUser?.name, "Ada Byron")
        XCTAssertEqual(defaults.string(forKey: Constants.UserDefaults.userName), "Ada Byron")
    }
}
