import XCTest
@testable import Astrid_App

/// The hi-fi empathy-state art (ADEV-127): which metaphor a list shows today, which frame a
/// column shows, and that the hi-fi art is only ever an upgrade over the built-in character.
///
/// The rule cases come from `Tests/Fixtures/empathy-art.json`, a verbatim copy of astrid-web
/// `contracts/fixtures/empathy-art.json` (ADEV-142). Web and iOS must agree on the metaphor for a
/// list on a given day, so a change starts there and is copied here.
final class EmpathyArtTests: XCTestCase {

    // MARK: - Fixture

    private struct Fixture: Decodable {
        struct Hash: Decodable { let text: String; let fnv1a32: UInt32 }
        struct Rotation: Decodable { let listId: String; let at: String; let daysSinceEpochUTC: Int; let metaphor: String }
        struct Column: Decodable { let completed: Bool; let statusRole: String?; let state: String? }
        let metaphors: [String]
        let states: [String]
        let hashes: [Hash]
        let rotation: [Rotation]
        let columns: [Column]
    }

    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "empathy-art", withExtension: "json"),
                                "empathy-art.json is missing from the test bundle")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private func date(_ iso: String) throws -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try XCTUnwrap(f.date(from: iso), iso)
    }

    // MARK: - Rules

    func testADEV127FixtureNamesTheMetaphorsAndStatesThisCodeKnows() throws {
        let f = try fixture()
        XCTAssertEqual(f.metaphors, EmpathyArt.defaultMetaphors)
        XCTAssertEqual(f.states, EmpathyArtState.allCases.map(\.rawValue))
    }

    func testADEV127HashesMatchTheFixture() throws {
        for h in try fixture().hashes {
            XCTAssertEqual(EmpathyArt.fnv1a32(h.text), h.fnv1a32, "fnv1a32(\"\(h.text)\")")
        }
    }

    func testADEV127RotationMatchesTheFixture() throws {
        let f = try fixture()
        for r in f.rotation {
            let at = try date(r.at)
            XCTAssertEqual(EmpathyArt.daysSinceEpochUTC(at), r.daysSinceEpochUTC, r.at)
            XCTAssertEqual(EmpathyArt.metaphor(listId: r.listId, at: at, metaphors: f.metaphors), r.metaphor,
                           "\(r.listId) at \(r.at)")
        }
    }

    func testADEV127ColumnsMapToStatesLikeTheFixture() throws {
        for c in try fixture().columns {
            XCTAssertEqual(EmpathyArt.state(completed: c.completed, statusRole: c.statusRole)?.rawValue, c.state,
                           "completed=\(c.completed) statusRole=\(c.statusRole ?? "nil")")
        }
    }

    func testADEV127BoardColumnsMapToStates() {
        func col(_ id: String, _ kind: ProjectBoardColumnKind = .status) -> ProjectBoardColumn {
            ProjectBoardColumn(id: id, name: id, description: "", kind: kind)
        }
        XCTAssertEqual(EmpathyArt.state(for: col(VIRTUAL_INBOX_COLUMN_ID, .inbox)), .inbox)
        XCTAssertEqual(EmpathyArt.state(for: col("ready")), .ready)
        XCTAssertEqual(EmpathyArt.state(for: col("doing")), .doing)
        XCTAssertEqual(EmpathyArt.state(for: col("waiting")), .waiting)
        XCTAssertEqual(EmpathyArt.state(for: col(VIRTUAL_DONE_COLUMN_ID, .done)), .done)
        XCTAssertNil(EmpathyArt.state(for: col("custom-review")))
    }

    func testADEV127NoMetaphorsMeansNoMetaphor() {
        XCTAssertNil(EmpathyArt.metaphor(listId: "x", at: Date(), metaphors: []))
    }

    // MARK: - Manifest

    private let manifestJSON = """
    {"version":1,"revision":"rev1","metaphors":["race","wall"],"states":["inbox","ready","doing","waiting","done"],
     "frames":[{"metaphor":"race","state":"inbox","url":"https://www.astrid.cc/images/empathy-art/race-inbox.abc.webp",
                "sha256":"\(String(repeating: "a", count: 64))","bytes":10}]}
    """

    func testADEV127DecodesTheServerManifest() throws {
        let m = try JSONDecoder().decode(EmpathyArtManifest.self, from: Data(manifestJSON.utf8))
        XCTAssertEqual(m.version, 1)
        XCTAssertEqual(m.revision, "rev1")
        XCTAssertEqual(m.metaphors, ["race", "wall"])
        XCTAssertEqual(m.frames.first?.state, "inbox")
        XCTAssertEqual(m.frames.first?.bytes, 10)
    }

    func testADEV127AnUnknownManifestVersionIsNotUsed() throws {
        let m = try JSONDecoder().decode(EmpathyArtManifest.self,
                                         from: Data(manifestJSON.replacingOccurrences(of: "\"version\":1", with: "\"version\":2").utf8))
        XCTAssertFalse(m.isSupported)
    }

    // MARK: - Store: hi-fi is an upgrade, never a requirement

    private func tempStore() throws -> EmpathyArtStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("empathy-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return EmpathyArtStore(directory: dir)
    }

    /// A 1×1 PNG: any decodable image will do for the store.
    private let pixel = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    func testADEV127NothingCachedMeansNoFrame() throws {
        let store = try tempStore()
        XCTAssertNil(store.frameData(metaphor: "race", state: .inbox))
        XCTAssertEqual(store.metaphors, [])
    }

    func testADEV127AFrameIsKeptOnlyWhenItsChecksumMatches() throws {
        let store = try tempStore()
        XCTAssertFalse(store.save(pixel, metaphor: "race", state: .inbox, sha256: String(repeating: "0", count: 64)))
        XCTAssertNil(store.frameData(metaphor: "race", state: .inbox))

        XCTAssertTrue(store.save(pixel, metaphor: "race", state: .inbox, sha256: EmpathyArtStore.sha256Hex(pixel)))
        XCTAssertEqual(store.frameData(metaphor: "race", state: .inbox), pixel)
    }

    func testADEV127AFrameAlreadyOnDiskIsNotFetchedAgain() throws {
        let store = try tempStore()
        let sha = EmpathyArtStore.sha256Hex(pixel)
        XCTAssertFalse(store.has(metaphor: "race", state: .inbox, sha256: sha))
        _ = store.save(pixel, metaphor: "race", state: .inbox, sha256: sha)
        XCTAssertTrue(store.has(metaphor: "race", state: .inbox, sha256: sha))
        XCTAssertFalse(store.has(metaphor: "race", state: .inbox, sha256: String(repeating: "f", count: 64)),
                       "a new revision of the same frame is fetched")
    }

    func testADEV127TheStoreRemembersTheManifestMetaphors() throws {
        let store = try tempStore()
        let m = try JSONDecoder().decode(EmpathyArtManifest.self, from: Data(manifestJSON.utf8))
        store.saveManifest(m)
        XCTAssertEqual(store.metaphors, ["race", "wall"])
        XCTAssertEqual(store.revision, "rev1")
        XCTAssertEqual(EmpathyArtStore(directory: store.directory).metaphors, ["race", "wall"], "survives relaunch")
    }

    func testADEV127AMetaphorIsShownOnlyWhenAllItsFramesAreCached() throws {
        let store = try tempStore()
        let m = try JSONDecoder().decode(EmpathyArtManifest.self, from: Data(manifestJSON.utf8))
        store.saveManifest(m)
        let sha = EmpathyArtStore.sha256Hex(pixel)
        for state in EmpathyArtState.allCases.dropLast() {
            _ = store.save(pixel, metaphor: "race", state: state, sha256: sha)
        }
        XCTAssertFalse(store.isComplete(metaphor: "race"),
                       "a half-fetched set would mix hi-fi and built-in art across one board")
        _ = store.save(pixel, metaphor: "race", state: .done, sha256: sha)
        XCTAssertTrue(store.isComplete(metaphor: "race"))
    }

    // MARK: - Who may show it

    func testADEV127OnlyAstridsOwnCharacterGetsTheOctopusArt() {
        XCTAssertTrue(EmpathyArt.brandMayShow(characterImage: "AstridCharacter"))
        XCTAssertFalse(EmpathyArt.brandMayShow(characterImage: "whitelabel-logo"),
                       "a partner brand must never show Astrid's mascot")
        XCTAssertFalse(EmpathyArt.brandMayShow(characterImage: nil))
    }

    func testADEV127PrefetchWaitsForAnUnmeteredConnection() {
        XCTAssertTrue(EmpathyArt.isIdleNetwork(type: .wifi, constrained: false))
        XCTAssertTrue(EmpathyArt.isIdleNetwork(type: .ethernet, constrained: false))
        XCTAssertFalse(EmpathyArt.isIdleNetwork(type: .cellular, constrained: false))
        XCTAssertFalse(EmpathyArt.isIdleNetwork(type: .wifi, constrained: true), "Low Data Mode")
        XCTAssertFalse(EmpathyArt.isIdleNetwork(type: .unknown, constrained: false))
    }

    func testADEV127PrefetchIsThrottled() {
        let now = Date()
        XCTAssertTrue(EmpathyArt.isDue(lastChecked: nil, now: now))
        XCTAssertFalse(EmpathyArt.isDue(lastChecked: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(EmpathyArt.isDue(lastChecked: now.addingTimeInterval(-EmpathyArt.recheckInterval - 1), now: now))
    }
}
