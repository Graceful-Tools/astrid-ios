//  MonkeyUITests.swift
//  Random-input stress test for the iOS app.
//
//  Scripted UI tests only ever walk paths someone thought of. This one taps, swipes and types
//  at random to find what nobody scripted: a crash, a hang, a screen the app cannot get back
//  from. It asserts three things and deliberately nothing else, because anything more specific
//  would be asserting the app's current shape rather than its survival:
//
//    1. the app never leaves the foreground (a crash or a hang taking it down is a failure)
//    2. no single action takes longer than `hangThreshold` (a beachball is a bug even if the
//       app recovers)
//    3. the app is still driveable at the end — the accessibility tree is still there
//
//  REPRODUCIBILITY. Every run seeds from `MONKEY_SEED`, defaulting to a fixed value so an
//  unattended weekly run is repeatable, and prints the seed plus the full action log on
//  failure. A random monkey that cannot be replayed reports bugs nobody can act on: re-run
//  with the same seed and the same actions land in the same places.
//
//  Tuning, all optional: MONKEY_SEED, MONKEY_ACTIONS (default 150), MONKEY_HANG_SECONDS.

import XCTest

final class MonkeyUITests: XCTestCase {

    /// Seeded so a failure can be replayed exactly. Pass MONKEY_SEED to vary it.
    private var seed: UInt64 { MonkeyConfig.seed }

    private var actionCount: Int { MonkeyConfig.actions }

    /// A single interaction taking longer than this is treated as a hang. XCUITest's own
    /// waiting means an unresponsive app shows up as a slow action rather than an error.
    private var hangThreshold: TimeInterval { MonkeyConfig.hangSeconds }

    override func setUp() {
        super.setUp()
        // Keep going after a failure so one bad action does not hide the rest of the run —
        // the point of a monkey is the whole sweep, not the first stumble.
        continueAfterFailure = true
    }

    @MainActor
    func testMonkeyStressesTheAppWithoutCrashingOrHanging() throws {
        let app = UITestLaunch.makeApp()
        app.launch()
        enterTheApp(app)

        var rng = SeededGenerator(seed: seed)
        var journal: [String] = []
        var slowest: (action: String, seconds: TimeInterval) = ("none", 0)

        XCTAssertEqual(app.state, .runningForeground, "The app was not running before the monkey started")

        for step in 1...actionCount {
            let action = MonkeyAction.random(using: &rng)
            let started = Date()
            perform(action, on: app, using: &rng)
            let elapsed = Date().timeIntervalSince(started)

            journal.append(String(format: "%3d. %@ (%.2fs)", step, action.description, elapsed))
            if elapsed > slowest.seconds { slowest = (action.description, elapsed) }

            if elapsed > hangThreshold {
                attach(journal: journal, app: app, named: "hang at step \(step)")
                XCTFail("""
                    Action \(step) (\(action.description)) took \(String(format: "%.1f", elapsed))s, \
                    over the \(Int(hangThreshold))s hang threshold. Replay: MONKEY_SEED=\(seed).
                    """)
            }

            if app.state != .runningForeground {
                attach(journal: journal, app: app, named: "app left the foreground at step \(step)")
                XCTFail("""
                    The app left the foreground at action \(step) (\(action.description)) — \
                    it crashed or was killed. Replay: MONKEY_SEED=\(seed).
                    """)
                return
            }
        }

        // Still driveable? A live app with an empty accessibility tree is wedged, which a
        // foreground check alone would call healthy.
        XCTAssertEqual(app.state, .runningForeground, "The app did not survive the monkey run")
        XCTAssertTrue(app.descendants(matching: .any).firstMatch.waitForExistence(timeout: 20),
                      "The app is in the foreground but has no accessible UI left — wedged. Replay: MONKEY_SEED=\(seed)")

        attach(journal: journal, app: app, named: "monkey run (seed \(seed))")
        print("MONKEY_SUMMARY actions=\(actionCount) seed=\(seed) slowest=\(String(format: "%.2f", slowest.seconds))s action=\(slowest.action)")
    }


    /// Get past the welcome screen one way or another.
    ///
    /// Deliberately NOT `skipUnlessSignedIn`. A skipped monkey is a monkey that stressed
    /// nothing while reporting green — the exact shape of failure this suite's account exists
    /// to end (see UITestLaunch). When a session is available the run exercises the real thing:
    /// lists, sync, network. When there is none, it takes the offline path instead and still
    /// stresses the whole UI. Either way something gets hammered.
    @MainActor
    private func enterTheApp(_ app: XCUIApplication) {
        let offline = app.buttons["Use without account"]
        if offline.waitForExistence(timeout: 15) {
            UITestLaunch.tapCenter(offline)
            print("MONKEY_MODE offline — no test-account session, stressing the local app")
        } else {
            print("MONKEY_MODE signed-in")
        }
        // Let whatever screen follows settle before the hammering starts, so the first actions
        // are not spent on a launch animation.
        _ = app.descendants(matching: .any).firstMatch.waitForExistence(timeout: 15)
    }

    // MARK: - Actions

    @MainActor
    private func perform(_ action: MonkeyAction, on app: XCUIApplication, using rng: inout SeededGenerator) {
        switch action {
        case .tap(let x, let y):
            app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()

        case .swipe(let direction):
            switch direction {
            case .up: app.swipeUp()
            case .down: app.swipeDown()
            case .left: app.swipeLeft()
            case .right: app.swipeRight()
            }

        case .tapRandomButton:
            let appFrame = app.frame
            let buttons = app.buttons.allElementsBoundByIndex.filter { button in
                guard button.exists else { return false }
                let frame = button.frame
                return !frame.isEmpty && !frame.isNull && !frame.isInfinite && frame.intersects(appFrame)
            }
            if let target = buttons.randomElement(using: &rng) {
                UITestLaunch.tapCenter(target)
            }

        case .type(let text):
            // Only when something is focused; typing into nothing throws rather than failing.
            if app.keyboards.element.exists {
                app.typeText(text)
            }

        case .swipeBack:
            UITestLaunch.swipeBackFromLeftEdge(app)

        case .dismissKeyboard:
            if app.keyboards.element.exists {
                app.typeText("\n")
            }
        }
    }

    @MainActor
    private func attach(journal: [String], app: XCUIApplication, named name: String) {
        let log = XCTAttachment(string: journal.joined(separator: "\n"))
        log.name = "monkey actions — \(name)"
        log.lifetime = .keepAlways
        add(log)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "screen — \(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }
}

// MARK: - The action set

enum MonkeyAction: CustomStringConvertible {
    case tap(x: CGFloat, y: CGFloat)
    case swipe(SwipeDirection)
    case tapRandomButton
    case type(String)
    case swipeBack
    case dismissKeyboard

    enum SwipeDirection: CaseIterable { case up, down, left, right }

    /// Weighted towards taps, which is what a person mostly does and what most reliably walks
    /// the app into unexpected states. Pure-random coordinates alone would spend most of the
    /// run hitting empty space.
    static func random(using rng: inout SeededGenerator) -> MonkeyAction {
        switch Int.random(in: 0..<100, using: &rng) {
        case 0..<35:
            // Avoid the very top: the status bar and the notch are not the app's.
            return .tap(x: CGFloat.random(in: 0.05...0.95, using: &rng),
                        y: CGFloat.random(in: 0.12...0.92, using: &rng))
        case 35..<60: return .tapRandomButton
        case 60..<75: return .swipe(SwipeDirection.allCases.randomElement(using: &rng)!)
        case 75..<85: return .type(randomText(using: &rng))
        case 85..<95: return .swipeBack
        default:      return .dismissKeyboard
        }
    }

    /// Text a person might type, plus the things that break parsers: emoji, quotes, newlines.
    private static func randomText(using rng: inout SeededGenerator) -> String {
        let samples = ["monkey task", "🐒", "'; DROP TABLE tasks; --", "a\nb",
                       "tomorrow at 5pm", "   ", "日本語のタスク", String(repeating: "x", count: 80)]
        return samples.randomElement(using: &rng)!
    }

    var description: String {
        switch self {
        case .tap(let x, let y): return String(format: "tap(%.2f, %.2f)", x, y)
        case .swipe(let d): return "swipe(\(d))"
        case .tapRandomButton: return "tapRandomButton"
        case .type(let t): return "type(\(t.prefix(16).replacingOccurrences(of: "\n", with: "\\n")))"
        case .swipeBack: return "swipeBack"
        case .dismissKeyboard: return "dismissKeyboard"
        }
    }
}

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
