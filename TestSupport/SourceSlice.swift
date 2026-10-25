//  SourceSlice.swift
//  The part of a source file a guard test reads, or a failure saying the marker moved (AITD-533).
//
//  `source.components(separatedBy: marker).last` returns the WHOLE file when the marker is not
//  there — so a guard whose function was renamed went on scanning everything, passing on any line
//  anywhere in the file. These fail instead, naming the marker that is gone.

import Foundation
import XCTest

enum SourceSlice {

    /// Everything after the first `marker`.
    static func after(_ marker: String, in source: String,
                      file: StaticString = #filePath, line: UInt = #line) throws -> String {
        guard let range = source.range(of: marker) else {
            XCTFail("\"\(marker)\" is not in the source any more — the guard is reading nothing", file: file, line: line)
            throw SourceSliceError.markerMissing(marker)
        }
        return String(source[range.upperBound...])
    }

    /// What lies between `start` and the first `end` after it.
    static func between(_ start: String, and end: String, in source: String,
                        file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let rest = try after(start, in: source, file: file, line: line)
        guard let stop = rest.range(of: end) else {
            XCTFail("\"\(end)\" no longer follows \"\(start)\" — the guard is reading nothing", file: file, line: line)
            throw SourceSliceError.markerMissing(end)
        }
        return String(rest[..<stop.lowerBound])
    }
}

enum SourceSliceError: Error {
    case markerMissing(String)
}
