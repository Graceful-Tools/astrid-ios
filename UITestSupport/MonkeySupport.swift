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

/// What the app's state after an action means: still in front, handed the screen to another app,
/// or gone.
///
/// "Not in the foreground" used to be read as "crashed", and the 2026-W45 weekly run failed on
/// both platforms with the app alive (AITD-580, AITD-581): an iOS button opened apple.com in
/// Safari, and on the Mac TestFlight came to the front. Following a link is something the app is
/// meant to do. A crash is the process ending, which is `.notRunning`.
enum MonkeySurvival: Equatable {
    case foreground
    case handedOff
    case died

    static func classify(_ state: XCUIApplication.State) -> MonkeySurvival {
        switch state {
        case .runningForeground: return .foreground
        case .runningBackground: return .handedOff
        #if os(iOS)
        case .runningBackgroundSuspended: return .handedOff
        #endif
        // `.unknown` stays a death: a monkey that cannot tell is not entitled to a pass.
        default: return .died
        }
    }

    /// Checks the app after an action and brings it back if another app took the screen.
    /// Returns nil while the run can go on, or why it cannot. The hand-off is journalled, so a
    /// replay shows which action left the app.
    @MainActor
    static func check(_ app: XCUIApplication, journal: inout [String]) -> String? {
        switch classify(app.state) {
        case .foreground:
            return nil
        case .handedOff:
            journal.append("     ↳ another app came to the front; bringing the app back")
            app.activate()
            return app.wait(for: .runningForeground, timeout: 10)
                ? nil
                : "it handed the screen to another app and could not be brought back"
        case .died:
            return "it crashed or was killed"
        }
    }
}
