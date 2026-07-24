//  GoogleTasksConnectCallbackTests.swift
//  Regression for task 6745f40f — the in-app Google Tasks connect flow parses the
//  astrid://google-tasks/... callback the backend redirects to: success vs error(message).

import XCTest
@testable import Astrid_Mac

final class GoogleTasksConnectCallbackTests: XCTestCase {

    private func url(_ s: String) -> URL { URL(string: s)! }

    func testSuccessCallbackHasNoError() {
        XCTAssertNil(GoogleTasksConnectCallback.errorMessage(from: url("astrid://google-tasks/connected")))
    }

    func testErrorCallbackCarriesMessage() {
        let msg = GoogleTasksConnectCallback.errorMessage(
            from: url("astrid://google-tasks/error?message=Tasks%20access%20not%20granted"))
        XCTAssertEqual(msg, "Tasks access not granted")
    }

    func testErrorCallbackWithoutMessageFallsBack() {
        XCTAssertEqual(GoogleTasksConnectCallback.errorMessage(from: url("astrid://google-tasks/error")),
                       "Connection didn't complete.")
    }
}
