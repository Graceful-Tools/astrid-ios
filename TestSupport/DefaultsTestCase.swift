import XCTest

/// A test case with its own `UserDefaults` suite, named uniquely per test and wiped on
/// tearDown — so suites never disturb the app's stored values and can run in parallel.
///
/// Two of the five suites that hand-rolled this used a FIXED suite name, which is not
/// parallel-safe: two clones running the same class would share and clear each other's domain.
class DefaultsTestCase: XCTestCase {
    private(set) var suiteName: String!
    private(set) var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "\(type(of: self)).\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        try super.tearDownWithError()
    }
}
