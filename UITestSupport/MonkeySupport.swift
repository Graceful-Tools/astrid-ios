//  MonkeySupport.swift
//  Shared by `MonkeyUITests` (iOS) and `MacMonkeyUITests` (Mac): the seeded generator and the
//  run configuration. Compiled into both UI-test targets through the `UITestSupport` group —
//  a file can belong to any number of targets; the two copies this replaces were
//  character-identical apart from a type name.

import XCTest

/// Deterministic PRNG — `SystemRandomNumberGenerator` cannot be seeded, and an unreplayable
/// monkey failure is close to useless. SplitMix64.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// How the run is tuned: actions, seed, hang threshold.
///
/// Read from a generated bundle resource, NOT the environment. xcodebuild does not forward the
/// shell environment to the xctrunner process — measured here on 2026-08-27, when `--actions 25`
/// produced a 150-action run — and this suite already learned that once with the test-account
/// cookie (see UITestLaunch). The environment is still consulted first so running from Xcode
/// with a scheme variable set keeps working.
enum MonkeyConfig {
    static let actions = value("actions", default: 150)
    static let seed = UInt64(value("seed", default: 20_260_826))
    static let hangSeconds = TimeInterval(value("hangSeconds", default: 10))

    private static let plist: [String: Any] = {
        let bundle = Bundle(for: MonkeyConfigToken.self)
        guard let url = bundle.url(forResource: "MonkeyConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return dict
    }()

    private static func value(_ key: String, default fallback: Int) -> Int {
        let envKey = "MONKEY_" + key.uppercased()
        if let fromEnv = ProcessInfo.processInfo.environment[envKey], let n = Int(fromEnv) { return n }
        if let fromPlist = plist[key] as? Int { return fromPlist }
        if let text = plist[key] as? String, let n = Int(text) { return n }
        return fallback
    }
}

private final class MonkeyConfigToken {}
