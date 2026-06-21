import XCTest
@testable import Astrid_App

/// Tests the error → OutboxResult classification. Getting this wrong is how a
/// transient network blip would dead-letter an offline write (data loss) or a
/// hard 404 would retry forever — so it's pure and unit-tested.
final class OutboxResultMapperTests: XCTestCase {

    private func isPermanent(_ r: OutboxResult) -> Bool { if case .permanent = r { return true }; return false }
    private func isRetryable(_ r: OutboxResult) -> Bool { if case .retryable = r { return true }; return false }

    func testHttp404IsPermanent() {
        XCTAssertTrue(isPermanent(OutboxResultMapper.classify(
            AstridAPIError.httpError(statusCode: 404, message: "not found"))))
    }

    func testHttp403And422ArePermanent() {
        XCTAssertTrue(isPermanent(OutboxResultMapper.classify(AstridAPIError.httpError(statusCode: 403, message: "x"))))
        XCTAssertTrue(isPermanent(OutboxResultMapper.classify(AstridAPIError.httpError(statusCode: 422, message: "x"))))
    }

    func testHttp500And429AreRetryable() {
        XCTAssertTrue(isRetryable(OutboxResultMapper.classify(AstridAPIError.httpError(statusCode: 500, message: "x"))))
        XCTAssertTrue(isRetryable(OutboxResultMapper.classify(AstridAPIError.httpError(statusCode: 429, message: "x"))))
    }

    func testUnauthorizedIsPermanent() {
        XCTAssertTrue(isPermanent(OutboxResultMapper.classify(AstridAPIError.unauthorized)))
    }

    func testNetworkErrorIsRetryable() {
        XCTAssertTrue(isRetryable(OutboxResultMapper.classify(URLError(.notConnectedToInternet))))
        XCTAssertTrue(isRetryable(OutboxResultMapper.classify(URLError(.timedOut))))
    }
}
