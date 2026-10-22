//  AstridAPIClientRequestTests.swift
//  The HTTP client's request contract, through `StubURLProtocol` instead of the server (AITD-535):
//  what goes on the wire, and how each kind of answer comes back.

import XCTest
@testable import Astrid_App

final class AstridAPIClientRequestTests: XCTestCase {
    private var client: AstridAPIClient!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        client = AstridAPIClient(session: StubURLProtocol.session())
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func onlyRequest(file: StaticString = #filePath, line: UInt = #line) throws -> StubURLProtocol.Recorded {
        let sent = StubURLProtocol.requests
        XCTAssertEqual(sent.count, 1, "exactly one request goes out", file: file, line: line)
        return try XCTUnwrap(sent.first, file: file, line: line)
    }

    // MARK: What goes out

    func testAGetSendsTheJSONHeadersAndThePlatform_AITD535() async throws {
        StubURLProtocol.respond = { _ in .json(#"{"targetType":"task","targetId":"t-1"}"#) }

        let resolved = try await client.resolveShortcode("abc123")

        XCTAssertEqual(resolved.targetType, "task")
        XCTAssertEqual(resolved.targetId, "t-1")
        let sent = try onlyRequest()
        XCTAssertEqual(sent.method, "GET")
        XCTAssertEqual(sent.path, "/api/v1/shortcodes/abc123")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: AnalyticsPlatformHeader.headerName),
                       AnalyticsPlatformHeader.current)
        XCTAssertNil(sent.body)
    }

    func testAPostEncodesItsBody_AITD535() async throws {
        StubURLProtocol.respond = { _ in
            .json(#"{"shortcode":{"code":"xyz","targetType":"list","targetId":"l-9"},"url":"https://astrid.cc/s/xyz"}"#)
        }

        _ = try? await client.createShortcode(targetType: "list", targetId: "l-9")

        let sent = try onlyRequest()
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.path, "/api/v1/shortcodes")
        XCTAssertEqual(sent.jsonBody?["targetType"] as? String, "list")
        XCTAssertEqual(sent.jsonBody?["targetId"] as? String, "l-9")
    }

    func testQueryItemsReachTheURL_AITD535() async throws {
        StubURLProtocol.respond = { _ in .json("{}") }

        _ = try? await client.getAppVersion(platform: "ios")

        XCTAssertEqual(try onlyRequest().query, ["platform": "ios"])
    }

    /// A traversal segment (one that arrived percent-encoded from a deep link) is refused before
    /// anything is sent: a server would normalise it to a different endpoint.
    func testATraversalPathIsRefusedWithoutSending_AITD535() async {
        do {
            let _: EmptyResponse = try await client.request(method: "GET", path: "/api/v1/tasks/a/../admin")
            XCTFail("a traversal path must not be sent")
        } catch AstridAPIError.invalidURL {
        } catch {
            XCTFail("expected invalidURL, got \(error)")
        }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    // MARK: How answers come back

    func testA401IsUnauthorized_AITD535() async {
        StubURLProtocol.respond = { _ in .json(#"{"error":"no session"}"#, status: 401) }

        do {
            _ = try await client.resolveShortcode("abc")
            XCTFail("a 401 must throw")
        } catch AstridAPIError.unauthorized {
        } catch {
            XCTFail("expected unauthorized, got \(error)")
        }
    }

    func testAnErrorStatusCarriesTheStatusAndBody_AITD535() async {
        StubURLProtocol.respond = { _ in .json(#"{"error":"nope"}"#, status: 409) }

        do {
            _ = try await client.resolveShortcode("abc")
            XCTFail("a 409 must throw")
        } catch AstridAPIError.httpError(let status, let message) {
            XCTAssertEqual(status, 409)
            XCTAssertEqual(message, #"{"error":"nope"}"#)
        } catch {
            XCTFail("expected httpError, got \(error)")
        }
    }

    /// A 204 with no body is success for a caller that expects nothing back.
    func testAnEmptyBodyIsAnEmptyResponse_AITD535() async throws {
        StubURLProtocol.respond = { _ in .http(status: 204, body: Data()) }

        let _: EmptyResponse = try await client.request(method: "DELETE", path: "/api/v1/whatever/1")

        XCTAssertEqual(try onlyRequest().method, "DELETE")
    }

    func testABodyThatDoesNotDecodeIsADecodingError_AITD535() async {
        StubURLProtocol.respond = { _ in .json(#"{"unexpected":true}"#) }

        do {
            _ = try await client.resolveShortcode("abc")
            XCTFail("a body of the wrong shape must throw")
        } catch AstridAPIError.decodingError {
        } catch {
            XCTFail("expected decodingError, got \(error)")
        }
    }

    /// The server writes dates with and without fractional seconds; both decode.
    func testDatesDecodeWithAndWithoutFractionalSeconds_AITD535() async throws {
        struct Stamped: Codable { let a: Date; let b: Date }
        StubURLProtocol.respond = { _ in
            .json(#"{"a":"2026-10-22T12:00:00.250Z","b":"2026-10-22T12:00:00Z"}"#)
        }

        let stamped: Stamped = try await client.request(method: "GET", path: "/api/v1/stamped")

        XCTAssertEqual(stamped.a.timeIntervalSince1970, 1_792_670_400.25, accuracy: 0.001)
        XCTAssertEqual(stamped.b.timeIntervalSince1970, 1_792_670_400)
    }

    /// A transport failure surfaces as the URLError itself — what offline handling looks for.
    func testATransportFailureIsTheURLError_AITD535() async {
        StubURLProtocol.respond = { _ in .failure(URLError(.notConnectedToInternet)) }

        do {
            _ = try await client.resolveShortcode("abc")
            XCTFail("a transport failure must throw")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        } catch {
            XCTFail("expected URLError, got \(error)")
        }
    }

    // MARK: Endpoints the app still calls

    func testDeleteCustomAgentSendsADelete_AITD535() async throws {
        StubURLProtocol.respond = { _ in .json(#"{"success":true}"#) }

        try await client.deleteCustomAgent(id: "agent-7")

        let sent = try onlyRequest()
        XCTAssertEqual(sent.method, "DELETE")
        XCTAssertEqual(sent.path, "/api/v1/custom-agents/agents/agent-7")
    }

    func testExportAccountDataReturnsTheRawFile_AITD535() async throws {
        let csv = Data("title,completed\nMilk,false\n".utf8)
        StubURLProtocol.respond = { _ in .http(status: 200, body: csv, headers: ["Content-Type": "text/csv"]) }

        let data = try await client.exportAccountData(format: "csv")

        XCTAssertEqual(data, csv)
        let sent = try onlyRequest()
        XCTAssertEqual(sent.path, "/api/v1/users/me/export")
        XCTAssertEqual(sent.query, ["format": "csv"])
    }

    func testExportAccountDataRefusalIsAnError_AITD535() async {
        StubURLProtocol.respond = { _ in .json("{}", status: 401) }

        do {
            _ = try await client.exportAccountData(format: "json")
            XCTFail("a 401 must throw")
        } catch AstridAPIError.unauthorized {
        } catch {
            XCTFail("expected unauthorized, got \(error)")
        }
    }
}
