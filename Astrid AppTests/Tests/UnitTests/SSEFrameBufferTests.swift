//  SSEFrameBufferTests.swift
//  Regression coverage for task 977ceb0d (AITD-313).
//
//  The SSE stream used to be assembled a byte at a time:
//
//      if let character = String(bytes: [byte], encoding: .utf8) { buffer.append(character) }
//
//  A single byte ≥ 0x80 is not valid UTF-8 on its own, so that initialiser returns nil and the
//  byte is dropped — silently, with no error anywhere. Every accented, CJK or emoji character in
//  an SSE payload lost both its lead byte and its continuation bytes before the JSON decoder ever
//  saw it. The app ships in 12 languages; the 3 s chat poll was repairing the damage afterwards,
//  which is why nobody filed it as a bug.
//
//  These tests feed the parser ONE BYTE AT A TIME, because that is what `URLSession.AsyncBytes`
//  actually yields. A test that hands over a whole event in one chunk would pass against the old
//  broken code too.

import XCTest
@testable import Astrid_App

final class SSEFrameBufferTests: XCTestCase {

    /// Feed a string through the buffer the way the socket does: byte by byte.
    private func frames(streaming text: String) -> [String] {
        var buffer = SSEFrameBuffer()
        var out: [String] = []
        for byte in Array(text.utf8) {
            out.append(contentsOf: buffer.append(byte))
        }
        return out
    }

    // MARK: - The bug

    func testNonASCIIPayloadSurvivesAByteAtATimeStream() {
        let payload = #"data: {"text":"Café 日本 🚀"}"#
        let received = frames(streaming: payload + "\n\n")

        XCTAssertEqual(received, [payload],
                       "every non-ASCII character must survive the stream byte-for-byte")
    }

    func testMultiByteCharacterSplitAcrossTheFrameIsNotDropped() {
        // Deliberately awkward: a 4-byte emoji, a 3-byte CJK glyph and a 2-byte accent together.
        let payload = #"data: {"a":"é","b":"日","c":"🚀","d":"Ω≈ç√"}"#
        XCTAssertEqual(frames(streaming: payload + "\n\n"), [payload])
    }

    func testDecodedFrameIsByteIdenticalToWhatWasSent() {
        let payload = "data: Grüße aus München — 東京 🎌"
        let received = frames(streaming: payload + "\n\n")
        XCTAssertEqual(Array(received[0].utf8), Array(payload.utf8))
    }

    // MARK: - Framing

    func testSeveralEventsArrivingInOneChunkAreAllReturned() {
        var buffer = SSEFrameBuffer()
        let chunk = Array("data: one\n\ndata: two\n\ndata: three\n\n".utf8)
        XCTAssertEqual(buffer.append(contentsOf: chunk), ["data: one", "data: two", "data: three"])
    }

    func testIncompleteEventIsHeldUntilItsTerminatorArrives() {
        var buffer = SSEFrameBuffer()
        XCTAssertTrue(buffer.append(contentsOf: Array("data: partial".utf8)).isEmpty)
        XCTAssertTrue(buffer.append(contentsOf: Array("\n".utf8)).isEmpty)
        XCTAssertEqual(buffer.append(contentsOf: Array("\n".utf8)), ["data: partial"])
    }

    func testMultiLineEventKeepsItsInternalNewlines() {
        let received = frames(streaming: "event: comment_added\ndata: {\"id\":\"1\"}\n\n")
        XCTAssertEqual(received, ["event: comment_added\ndata: {\"id\":\"1\"}"])
    }

    func testCarriageReturnLineEndingsTerminateAnEvent() {
        // SSE ends an event on a blank line, which may be CRLF-delimited. The old suffix check
        // only ever looked for "\n\n".
        XCTAssertEqual(frames(streaming: "data: crlf\r\n\r\n"), ["data: crlf"])
        XCTAssertEqual(frames(streaming: "data: cr\r\rdata: next\r\rx"), ["data: cr", "data: next"])
    }

    func testATrailingLoneCarriageReturnIsHeldRatherThanGuessedAt() {
        // A CR at the end of the buffer may still turn out to be the first half of a CRLF.
        // Splitting there would cut an event in the wrong place, so the parser waits.
        var buffer = SSEFrameBuffer()
        XCTAssertTrue(buffer.append(contentsOf: Array("data: x\r\r".utf8)).isEmpty)
        XCTAssertEqual(buffer.append(contentsOf: Array("\ndata: y\n\n".utf8)), ["data: x", "data: y"])
    }

    func testEmptyFramesFromKeepaliveBlankLinesAreNotEmitted() {
        XCTAssertEqual(frames(streaming: "\n\n\n\ndata: real\n\n"), ["data: real"])
    }

    func testCommentOnlyKeepaliveIsReturnedAndHarmless() {
        // ": ping" is the conventional SSE keepalive. It should frame normally; the event parser
        // above ignores it because it has no data: line.
        XCTAssertEqual(frames(streaming: ": ping\n\n"), [": ping"])
    }

    // MARK: - Hardening

    func testAServerThatNeverSendsABlankLineCannotGrowTheBufferWithoutBound() {
        var buffer = SSEFrameBuffer()
        let junk = Array(String(repeating: "x", count: 64 * 1024).utf8)

        for _ in 0..<64 {
            _ = buffer.append(contentsOf: junk)
            XCTAssertLessThanOrEqual(buffer.pendingByteCount, SSEFrameBuffer.maxPendingBytes)
        }
    }

    func testBufferRecoversAndParsesTheNextEventAfterAnOverflow() {
        var buffer = SSEFrameBuffer()
        _ = buffer.append(contentsOf: Array(String(repeating: "x", count: SSEFrameBuffer.maxPendingBytes + 1).utf8))
        XCTAssertEqual(buffer.append(contentsOf: Array("data: after\n\n".utf8)), ["data: after"])
    }

    // MARK: - The guard

    func testStreamingLoopDoesNotDecodeASingleByteAsUTF8() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Astrid App/Core/RealTime/SSEClient.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("String(bytes: [byte]"),
                       "decoding one byte at a time drops every non-ASCII character — "
                       + "accumulate bytes and decode once per frame (AITD-313)")
        XCTAssertFalse(source.contains(#"hasSuffix("\n\n")"#),
                       "scanning the whole growing buffer per byte is quadratic — SSEFrameBuffer "
                       + "tracks how far it has already scanned")
    }
}
