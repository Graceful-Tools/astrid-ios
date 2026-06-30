import XCTest
@testable import Astrid_App

/// Blocker #4: the temp→real task-id map must survive relaunch, or a photo/comment
/// queued against an offline-created task is stranded after an app kill.
final class TempTaskMappingStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        suite = "temp-map-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }
    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testSaveThenLoadRoundTrips() {
        TempTaskMappingStore.save(["temp_a": "real_a", "temp_b": "real_b"], to: defaults)
        XCTAssertEqual(TempTaskMappingStore.load(defaults), ["temp_a": "real_a", "temp_b": "real_b"])
    }

    func testLoadMissingIsEmpty() {
        XCTAssertEqual(TempTaskMappingStore.load(defaults), [:])
    }

    func testRecordingAddsMapping() {
        let m = TempTaskMappingStore.recording([:], temp: "temp_1", real: "real_1")
        XCTAssertEqual(m["temp_1"], "real_1")
    }

    func testRecordingIgnoresNonTempOrSelfMapping() {
        XCTAssertTrue(TempTaskMappingStore.recording([:], temp: "real_x", real: "real_y").isEmpty,
                      "a non-temp id is not a mapping")
        XCTAssertTrue(TempTaskMappingStore.recording([:], temp: "temp_z", real: "temp_z").isEmpty,
                      "mapping an id to itself is meaningless")
    }

    func testRecordingIsBounded() {
        var m: [String: String] = [:]
        for i in 0..<(TempTaskMappingStore.maxEntries + 50) {
            m = TempTaskMappingStore.recording(m, temp: "temp_\(i)", real: "real_\(i)")
        }
        XCTAssertLessThanOrEqual(m.count, TempTaskMappingStore.maxEntries,
                                 "the map can't grow without bound")
        XCTAssertEqual(m["temp_\(TempTaskMappingStore.maxEntries + 49)"], "real_\(TempTaskMappingStore.maxEntries + 49)",
                       "the most recent mapping is retained")
    }
}
