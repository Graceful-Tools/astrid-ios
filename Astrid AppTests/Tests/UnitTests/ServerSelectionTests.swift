import XCTest
@testable import Astrid_App

/// ADEV-118: one app, pointed at a partner's own server, chosen at sign-in.
final class ServerSelectionTests: XCTestCase {
    private let brand = "https://astrid.cc"

    // MARK: - What a person types

    func testABareHostBecomesAnHTTPSOrigin_ADEV118() {
        XCTAssertEqual(ServerSelection.origin(from: "tasks.example.com"), .success("https://tasks.example.com"))
    }

    func testPathQueryFragmentAndTrailingSlashAreDropped_ADEV118() {
        XCTAssertEqual(ServerSelection.origin(from: "https://tasks.example.com/"), .success("https://tasks.example.com"))
        XCTAssertEqual(ServerSelection.origin(from: "https://tasks.example.com/auth/signin?x=1#top"),
                       .success("https://tasks.example.com"))
    }

    func testHostIsLowercasedAndPortKept_ADEV118() {
        XCTAssertEqual(ServerSelection.origin(from: "  HTTPS://Tasks.Example.COM:8443/app \n"),
                       .success("https://tasks.example.com:8443"))
    }

    func testOnlyHTTPSIsAccepted_ADEV118() {
        XCTAssertEqual(ServerSelection.origin(from: "http://tasks.example.com"), .failure(.notHTTPS))
        XCTAssertEqual(ServerSelection.origin(from: "ftp://tasks.example.com"), .failure(.notHTTPS))
    }

    func testEmptyAndNonsenseAreRefused_ADEV118() {
        XCTAssertEqual(ServerSelection.origin(from: "   "), .failure(.empty))
        XCTAssertEqual(ServerSelection.origin(from: "not a server"), .failure(.invalid))
        XCTAssertEqual(ServerSelection.origin(from: "localhost"), .failure(.invalid))
        XCTAssertEqual(ServerSelection.origin(from: "https://"), .failure(.invalid))
    }

    func testCredentialsInTheAddressAreRefused_ADEV118() {
        XCTAssertEqual(ServerSelection.origin(from: "https://me:secret@tasks.example.com"), .failure(.invalid))
    }

    // MARK: - Which server is used

    func testNoChoiceMeansTheBuildsOwnServer_ADEV118() {
        XCTAssertEqual(ServerSelection.resolve(custom: nil, brandDefault: brand), brand)
        XCTAssertEqual(ServerSelection.resolve(custom: "https://tasks.example.com", brandDefault: brand),
                       "https://tasks.example.com")
    }

    func testIsCustomComparesOrigins_ADEV118() {
        XCTAssertFalse(ServerSelection.isCustom("https://astrid.cc/", brandDefault: brand))
        XCTAssertTrue(ServerSelection.isCustom("https://tasks.example.com", brandDefault: brand))
    }

    // MARK: - Kept between launches

    func testTheChoiceIsSavedAndReadBack_ADEV118() {
        let store = makeStore()
        XCTAssertNil(store.custom)
        store.save("https://tasks.example.com", brandDefault: brand)
        XCTAssertEqual(store.custom, "https://tasks.example.com")
    }

    func testChoosingTheBuildsOwnServerForgetsTheChoice_ADEV118() {
        let store = makeStore()
        store.save("https://tasks.example.com", brandDefault: brand)
        store.save(brand, brandDefault: brand)
        XCTAssertNil(store.defaults.string(forKey: ServerSelectionStore.key))
        store.save("https://tasks.example.com", brandDefault: brand)
        store.save(nil, brandDefault: brand)
        XCTAssertNil(store.custom)
    }

    func testAStoredValueThatNoLongerParsesReadsAsNoChoice_ADEV118() {
        let store = makeStore()
        store.defaults.set("http://insecure.example.com", forKey: ServerSelectionStore.key)
        XCTAssertNil(store.custom)
    }

    private func makeStore() -> ServerSelectionStore {
        let name = "ServerSelectionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return ServerSelectionStore(defaults: defaults)
    }
}

/// ADEV-118: a server is checked before the app is pointed at it.
final class ServerProbeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    func testAnAstridServerAnswersWithItsCapabilities_ADEV118() async throws {
        StubURLProtocol.respond = { _ in
            .json(#"{"auth":{"google":false,"passkey":true},"brand":{"appName":"Acme Tasks"},"meta":{"apiVersion":"v1"}}"#)
        }
        let capabilities = try await ServerProbe(session: StubURLProtocol.session()).check("https://tasks.example.com")
        XCTAssertEqual(StubURLProtocol.requests.first?.request.url?.absoluteString,
                       "https://tasks.example.com/api/v1/capabilities")
        XCTAssertEqual(capabilities.brand.appName, "Acme Tasks")
    }

    func testAnyOtherJSONIsNotAnAstridServer_ADEV118() async {
        StubURLProtocol.respond = { _ in .json(#"{"hello":"world"}"#) }
        await assertProbe(fails: .notAstrid)
    }

    func testANon200IsNotAnAstridServer_ADEV118() async {
        StubURLProtocol.respond = { _ in .json(#"{"auth":{},"meta":{"apiVersion":"v1"}}"#, status: 404) }
        await assertProbe(fails: .notAstrid)
    }

    func testNoAnswerIsUnreachable_ADEV118() async {
        StubURLProtocol.respond = { _ in .failure(URLError(.cannotFindHost)) }
        await assertProbe(fails: .unreachable)
    }

    private func assertProbe(fails expected: ServerProbe.Failure, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await ServerProbe(session: StubURLProtocol.session()).check("https://tasks.example.com")
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ServerProbe.Failure, expected, file: file, line: line)
        }
    }
}

/// ADEV-118: switching servers is a clean break.
@MainActor
final class ServerSwitcherTests: XCTestCase {
    private let brand = "https://astrid.cc"
    private var events: [String] = []
    private var current = "https://astrid.cc"
    private var signedIn = false
    private var store: ServerSelectionStore!

    override func setUp() {
        super.setUp()
        let name = "ServerSwitcherTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        store = ServerSelectionStore(defaults: defaults)
        events = []
        current = brand
        signedIn = false
    }

    private func makeSwitcher() -> ServerSwitcher {
        ServerSwitcher(.init(
            store: store,
            brandDefault: brand,
            currentServer: { [unowned self] in current },
            reloadServer: { [unowned self] in current = ServerSelection.resolve(custom: store.custom, brandDefault: brand) },
            isSignedIn: { [unowned self] in signedIn },
            signOut: { [unowned self] in events.append("signOut"); signedIn = false },
            clearCookies: { [unowned self] host in events.append("cookies:\(host)") },
            restartCore: { [unowned self] in events.append("restartCore:\(current)") },
            resetCapabilities: { [unowned self] in events.append("resetCapabilities") },
            refreshCapabilities: { [unowned self] in events.append("refreshCapabilities") }))
    }

    func testSwitchingRestartsTheCoreOnTheNewServerAndAsksItWhoItIs_ADEV118() async {
        let changed = await makeSwitcher().use("https://tasks.example.com")
        XCTAssertTrue(changed)
        XCTAssertEqual(store.custom, "https://tasks.example.com")
        XCTAssertEqual(events, ["cookies:astrid.cc", "restartCore:https://tasks.example.com",
                                "resetCapabilities", "refreshCapabilities"])
    }

    func testASignedInSwitchSignsOutFirst_ADEV118() async {
        signedIn = true
        await makeSwitcher().use("https://tasks.example.com")
        XCTAssertEqual(events.first, "signOut")
        XCTAssertFalse(signedIn)
    }

    func testChoosingTheServerAlreadyInUseChangesNothing_ADEV118() async {
        signedIn = true
        let changed = await makeSwitcher().use(brand)
        XCTAssertFalse(changed)
        XCTAssertEqual(events, [])
        XCTAssertTrue(signedIn)
    }

    func testGoingBackForgetsTheChoiceAndClearsThePartnersCookies_ADEV118() async {
        let switcher = makeSwitcher()
        await switcher.use("https://tasks.example.com")
        XCTAssertTrue(switcher.isCustom)
        XCTAssertEqual(switcher.currentHost, "tasks.example.com")
        events = []
        await switcher.use(nil)
        XCTAssertNil(store.custom)
        XCTAssertFalse(switcher.isCustom)
        XCTAssertEqual(events.first, "cookies:tasks.example.com")
        XCTAssertTrue(events.contains("restartCore:https://astrid.cc"))
    }
}

/// ADEV-118: the sign-in sheet checks, then switches, and says why when it can't.
@MainActor
final class ServerPickerModelTests: XCTestCase {
    func testAGoodServerIsCheckedThenUsed_ADEV118() async {
        var probed: [String] = []
        var switched: [String?] = []
        var current = ServerCapabilities()
        current.meta.apiLevel = ServerCompatibility.requiredLevel
        let model = ServerPickerModel(probe: { probed.append($0); return current },
                                      switchTo: { switched.append($0) })
        model.address = "Tasks.Example.com/signin"
        let connected = await model.connect()
        XCTAssertTrue(connected)
        XCTAssertEqual(probed, ["https://tasks.example.com"])
        XCTAssertEqual(switched, ["https://tasks.example.com"])
        XCTAssertNil(model.errorMessage)
    }

    func testAnHTTPAddressIsRefusedBeforeAnythingIsAsked_ADEV118() async {
        var probed = false
        let model = ServerPickerModel(probe: { _ in probed = true; return .permissive }, switchTo: { _ in })
        model.address = "http://tasks.example.com"
        let connected = await model.connect()
        XCTAssertFalse(connected)
        XCTAssertFalse(probed)
        XCTAssertEqual(model.errorMessage, NSLocalizedString("server.error_not_https", comment: ""))
    }

    func testAServerThatIsNotAstridIsNotUsedAndIsNamed_ADEV118() async {
        var switched = false
        let model = ServerPickerModel(probe: { _ in throw ServerProbe.Failure.notAstrid },
                                      switchTo: { _ in switched = true })
        model.address = "example.com"
        let connected = await model.connect()
        XCTAssertFalse(connected)
        XCTAssertFalse(switched)
        XCTAssertEqual(model.errorMessage,
                       String(format: NSLocalizedString("server.error_not_astrid", comment: ""), "example.com"))
    }
}

/// ADEV-120: links and link handling follow the server the person chose.
final class ActiveServerTests: XCTestCase {
    private let partner = "https://tasks.example.com"

    func testOnlyAChosenServerThatIsInUseCountsAsChosen_ADEV120() {
        XCTAssertTrue(ActiveServer.isChosen(origin: partner, chosen: partner))
        XCTAssertFalse(ActiveServer.isChosen(origin: "http://localhost:3000", chosen: nil),
                       "a developer's localhost is not a choice")
        XCTAssertFalse(ActiveServer.isChosen(origin: "https://www.astrid.cc", chosen: partner),
                       "a UI-test run's override is not the person's choice")
    }

    func testLinksPointAtTheChosenServer_ADEV120() {
        XCTAssertEqual(ActiveServer.linkOrigin(origin: partner, chosen: true, brandOrigin: "https://astrid.cc"), partner)
        XCTAssertEqual(ActiveServer.linkOrigin(origin: "http://localhost:3000", chosen: false, brandOrigin: "https://astrid.cc"),
                       "https://astrid.cc")
    }

    func testOnlyTheChosenServersLinksOpenInPlace_ADEV120() {
        let brandHosts: Set<String> = ["astrid.cc", "www.astrid.cc"]
        XCTAssertEqual(ActiveServer.webHosts(origin: partner, chosen: true, brandHosts: brandHosts),
                       ["tasks.example.com"])
        XCTAssertEqual(ActiveServer.webHosts(origin: "https://www.astrid.cc", chosen: false, brandHosts: brandHosts),
                       brandHosts)
    }
}

/// ADEV-121: a chosen server too old for this app is refused by name.
@MainActor
final class ServerCompatibilityTests: XCTestCase {
    private func capabilities(_ json: String) throws -> ServerCapabilities {
        try JSONDecoder().decode(ServerCapabilities.self, from: Data(json.utf8))
    }

    func testAServerWithNoLevelIsTheOldest_ADEV121() throws {
        let old = try capabilities(#"{"auth":{},"meta":{"apiVersion":"v1"}}"#)
        XCTAssertEqual(old.meta.level, 0)
        XCTAssertTrue(ServerCompatibility.isTooOld(old, required: 1))
    }

    func testOlderAndCurrentLevels_ADEV121() throws {
        let current = try capabilities(#"{"meta":{"apiVersion":"v1","apiLevel":1}}"#)
        let newer = try capabilities(#"{"meta":{"apiVersion":"v1","apiLevel":7}}"#)
        XCTAssertFalse(ServerCompatibility.isTooOld(current, required: 1))
        XCTAssertFalse(ServerCompatibility.isTooOld(newer, required: 1))
        XCTAssertTrue(ServerCompatibility.isTooOld(current, required: 2))
    }

    func testAMalformedMetaReadsAsTheOldestRatherThanFailingTheWholeDocument_ADEV121() throws {
        let odd = try capabilities(#"{"brand":{"appName":"Acme"},"meta":{"apiLevel":"high"}}"#)
        XCTAssertEqual(odd.meta.level, 0)
        XCTAssertEqual(odd.brand.appName, "Acme")
    }

    func testTheMessageNamesTheServer_ADEV121() {
        XCTAssertTrue(ServerCompatibility.message(host: "tasks.example.com").contains("tasks.example.com"))
    }

    func testThePickerRefusesATooOldServerAndDoesNotSwitch_ADEV121() async {
        var switched = false
        let model = ServerPickerModel(probe: { _ in try JSONDecoder().decode(
            ServerCapabilities.self, from: Data(#"{"auth":{},"meta":{"apiVersion":"v1"}}"#.utf8)) },
                                      switchTo: { _ in switched = true })
        model.address = "tasks.example.com"
        let connected = await model.connect()
        XCTAssertFalse(connected)
        XCTAssertFalse(switched)
        XCTAssertEqual(model.errorMessage, ServerCompatibility.message(host: "tasks.example.com"))
    }

    func testOnlyAChosenServerIsFlaggedTooOld_ADEV121() async {
        let old: ServerCapabilities = .permissive
        let chosen = ServerCapabilityService(fetch: { old }, storeCopy: { _ in }, isChosenServer: { true })
        let own = ServerCapabilityService(fetch: { old }, storeCopy: { _ in }, isChosenServer: { false })
        await chosen.refresh()
        await own.refresh()
        XCTAssertTrue(chosen.chosenServerTooOld)
        XCTAssertFalse(own.chosenServerTooOld, "the build's own server ships with the build")
    }
}

/// ADEV-122: a company's device management presets, and can lock, the server.
@MainActor
final class ManagedServerTests: XCTestCase {
    private let brand = "https://astrid.cc"
    private var defaults: UserDefaults!
    private var store: ServerSelectionStore!
    private var current = "https://astrid.cc"
    private var events: [String] = []

    override func setUp() {
        super.setUp()
        let name = "ManagedServerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { [defaults] in defaults?.removePersistentDomain(forName: name) }
        store = ServerSelectionStore(defaults: defaults)
        current = brand
        events = []
    }

    private func manage(_ configuration: [String: Any]?) {
        defaults.set(configuration, forKey: ManagedServerConfig.defaultsKey)
    }

    private func makeSwitcher(signedIn: Bool = true) -> ServerSwitcher {
        var signedIn = signedIn
        return ServerSwitcher(.init(
            store: store, brandDefault: brand,
            currentServer: { [unowned self] in current },
            reloadServer: { [unowned self] in current = ServerSelection.resolve(custom: store.custom, brandDefault: brand) },
            isSignedIn: { signedIn },
            signOut: { [unowned self] in events.append("signOut"); signedIn = false },
            clearCookies: { _ in },
            restartCore: { [unowned self] in events.append("restartCore:\(current)") },
            resetCapabilities: {},
            refreshCapabilities: {},
            recordSessionServer: { [unowned self] in events.append("record:\($0)") }))
    }

    func testTheManagedKeysAreRead_ADEV122() {
        XCTAssertEqual(ManagedServerConfig(["serverURL": "tasks.example.com", "serverLocked": true]),
                       ManagedServerConfig(server: "https://tasks.example.com", locked: true))
        XCTAssertEqual(ManagedServerConfig(["serverLocked": NSNumber(value: 1)]).locked, true)
        XCTAssertEqual(ManagedServerConfig(nil), ManagedServerConfig())
    }

    func testAManagedAddressThatDoesNotParseIsIgnored_ADEV122() {
        XCTAssertNil(ManagedServerConfig(["serverURL": "http://insecure.example.com"]).server)
    }

    func testManagedBeatsSavedBeatsTheBuildsOwn_ADEV122() {
        XCTAssertNil(store.custom)
        store.save("https://mine.example.com", brandDefault: brand)
        XCTAssertEqual(store.custom, "https://mine.example.com")
        manage(["serverURL": "https://corp.example.com"])
        XCTAssertEqual(store.custom, "https://corp.example.com")
    }

    func testALockedServerCannotBeChangedOnTheDevice_ADEV122() async {
        manage(["serverURL": "https://corp.example.com", "serverLocked": true])
        let switcher = makeSwitcher()
        await switcher.reconcile()
        XCTAssertTrue(switcher.isLocked)
        events = []
        let changed = await switcher.use(nil)
        XCTAssertFalse(changed)
        XCTAssertEqual(current, "https://corp.example.com")
        XCTAssertEqual(events, [])
    }

    func testAConfigurationChangeSwitchesWithTheSameCleanBreak_ADEV122() async {
        let switcher = makeSwitcher(signedIn: true)
        manage(["serverURL": "https://corp.example.com"])
        let changed = await switcher.managedConfigurationMayHaveChanged()
        XCTAssertTrue(changed)
        XCTAssertEqual(events, ["signOut", "restartCore:https://corp.example.com", "record:https://corp.example.com"])
    }

    func testAnUnrelatedDefaultsWriteDoesNothing_ADEV122() async {
        manage(["serverURL": "https://corp.example.com"])
        let switcher = makeSwitcher()
        await switcher.managedConfigurationMayHaveChanged()
        events = []
        defaults.set(true, forKey: "someOtherSetting")
        let changed = await switcher.managedConfigurationMayHaveChanged()
        XCTAssertFalse(changed)
        XCTAssertEqual(events, [])
    }

    func testTheSessionGuardSpotsAServerThatChangedWhileClosed_ADEV122() {
        XCTAssertFalse(SessionServerGuard.serverChanged(current: brand, defaults: defaults), "first run records only")
        XCTAssertFalse(SessionServerGuard.serverChanged(current: brand, defaults: defaults))
        XCTAssertTrue(SessionServerGuard.serverChanged(current: "https://corp.example.com", defaults: defaults))
        XCTAssertFalse(SessionServerGuard.serverChanged(current: "https://corp.example.com", defaults: defaults))
    }
}
