//  SSEFrameBuffer.swift
//  Splits a Server-Sent Events byte stream into complete events.
//
//  Task 977ceb0d (AITD-313). The stream used to be assembled with
//  `String(bytes: [byte], encoding: .utf8)` per byte. A byte ≥ 0x80 is not valid UTF-8 on its own,
//  so that returns nil and the byte is dropped — every accent, CJK glyph and emoji in an SSE
//  payload was destroyed before the JSON decoder saw it, in an app that ships in 12 languages.
//  The 3 s chat poll was quietly repairing the damage.
//
//  Bytes now accumulate as bytes and are decoded once per complete event. Extracted as a pure
//  value type for the same reason `SSEReconnectPolicy` was: the logic inside `startStreaming`
//  cannot be tested, and this is the part that has to be right.

import Foundation

struct SSEFrameBuffer {

    /// A server that never sends a blank line must not be able to grow this without bound.
    /// Well past any real event; reaching it means the stream is malformed.
    static let maxPendingBytes = 1_048_576  // 1 MiB

    private static let lf: UInt8 = 0x0A
    private static let cr: UInt8 = 0x0D

    private var pending: [UInt8] = []

    /// How far into `pending` the terminator scan has already reached. Without this, every
    /// incoming byte re-scanned the whole buffer — quadratic in the size of an event.
    private var scanned = 0

    var pendingByteCount: Int { pending.count }

    /// Feed one byte. Returns any events completed by it (usually none).
    mutating func append(_ byte: UInt8) -> [String] {
        append(contentsOf: CollectionOfOne(byte))
    }

    /// Feed a chunk. Returns every event completed by it — a chunk can carry more than one, and
    /// the old suffix check could only ever see a boundary at the very end.
    mutating func append<Bytes: Sequence>(contentsOf chunk: Bytes) -> [String] where Bytes.Element == UInt8 {
        pending.append(contentsOf: chunk)

        var frames: [String] = []
        while let split = nextTerminator() {
            let frame = Array(pending[0..<split.frameEnd])
            pending.removeFirst(split.resumeAt)
            scanned = 0
            // Decode ONCE, over a whole event, so multi-byte characters are intact.
            if !frame.isEmpty {
                frames.append(String(decoding: frame, as: UTF8.self))
            }
        }

        if pending.count > Self.maxPendingBytes {
            // Malformed stream: drop it rather than grow forever. The next well-formed event
            // still parses, because a terminator resets us to a clean boundary.
            pending.removeAll(keepingCapacity: false)
            scanned = 0
        }

        return frames
    }

    /// The end of the first complete event in `pending`, if there is one.
    ///
    /// An SSE event ends at a blank line. A line ends with CRLF, LF or CR, so a blank line is any
    /// two consecutive line breaks — `\n\n`, `\r\n\r\n`, `\r\r` and the mixed forms. The old
    /// suffix check only ever recognised `\n\n`.
    ///
    /// `frameEnd` excludes the terminator; `resumeAt` is where the next event starts.
    private mutating func nextTerminator() -> (frameEnd: Int, resumeAt: Int)? {
        var i = max(scanned, 0)

        while i < pending.count {
            switch lineBreak(at: i) {
            case .none:
                i += 1

            case .incomplete:
                // A trailing CR may still become a CRLF. Re-examine it once more bytes land.
                scanned = i
                return nil

            case .length(let first):
                switch lineBreak(at: i + first) {
                case .none:
                    i += first
                case .incomplete:
                    scanned = i
                    return nil
                case .length(let second):
                    return (i, i + first + second)
                }
            }
        }

        scanned = i
        return nil
    }

    private enum LineBreak {
        case none
        /// The buffer ends mid-break; deciding now would split an event in the wrong place.
        case incomplete
        case length(Int)
    }

    private func lineBreak(at i: Int) -> LineBreak {
        guard i < pending.count else { return .incomplete }

        switch pending[i] {
        case Self.lf:
            return .length(1)
        case Self.cr:
            guard i + 1 < pending.count else { return .incomplete }
            return .length(pending[i + 1] == Self.lf ? 2 : 1)
        default:
            return .none
        }
    }
}
