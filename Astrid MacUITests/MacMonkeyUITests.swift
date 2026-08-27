//  MacMonkeyUITests.swift
//  Random-input stress test for the Mac app. The iOS half is `MonkeyUITests.swift`; the two
//  cannot share code because a file belongs to one test target, so the small pieces below
//  (the seeded generator, the action set) are deliberately duplicated rather than fought over.
//
//  Same contract as the iOS monkey: the app must stay in the foreground, no single action may
//  take longer than the hang threshold, and the app must still be driveable at the end.
//
//  HERMETIC. Runs in offline mode, like every other Mac UI test — the Mac suite shares the real
//  app container, so a run that signed in would be operating on a real account.
//
//  TWO THINGS THE MONKEY DELIBERATELY DOES NOT TOUCH, both of which would produce false
//  failures rather than findings:
//    • the menu bar — a random menu item is eventually Quit, and an app that quit because it
//      was told to is not a crash
//    • modifier keys — ⌘Q and ⌘W are one keystroke away from the same false positive
//
//  Tuning: MONKEY_SEED, MONKEY_ACTIONS (default 150), MONKEY_HANG_SECONDS.

import XCTest

final class MacMonkeyUITests: XCTestCase {

    private var seed: UInt64 { MonkeyConfig.seed }
    private var actionCount: Int { MonkeyConfig.actions }
    private var hangThreshold: TimeInterval { MonkeyConfig.hangSeconds }

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    @MainActor
    func testMonkeyStressesTheMacAppWithoutCrashingOrHanging() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting"]
        app.launch()

        // Reach the shell the way the rest of the Mac suite does.
        let offline = app.descendants(matching: .any).matching(identifier: "login.offline").firstMatch
        let myTasks = app.descendants(matching: .any).matching(identifier: "sidebar.myTasks").firstMatch
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline && !myTasks.exists {
            if offline.exists { offline.click() }
            _ = myTasks.waitForExistence(timeout: 2)
        }
        try XCTSkipUnless(myTasks.exists, "Never reached the shell, so there is nothing to stress")

        var rng = MacSeededGenerator(seed: seed)
        var journal: [String] = []
        var slowest: (String, TimeInterval) = ("none", 0)

        for step in 1...actionCount {
            let action = MacMonkeyAction.random(using: &rng)
            let started = Date()
            perform(action, on: app, using: &rng)
            let elapsed = Date().timeIntervalSince(started)

            journal.append(String(format: "%3d. %@ (%.2fs)", step, action.description, elapsed))
            if elapsed > slowest.1 { slowest = (action.description, elapsed) }

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
                    The Mac app left the foreground at action \(step) (\(action.description)) — \
                    it crashed or was killed. Replay: MONKEY_SEED=\(seed).
                    """)
                return
            }
        }

        XCTAssertEqual(app.state, .runningForeground, "The app did not survive the monkey run")
        XCTAssertTrue(app.descendants(matching: .any).firstMatch.waitForExistence(timeout: 20),
                      "The app is running but has no accessible UI left — wedged. Replay: MONKEY_SEED=\(seed)")

        attach(journal: journal, app: app, named: "monkey run (seed \(seed))")
        print("MONKEY_SUMMARY actions=\(actionCount) seed=\(seed) slowest=\(String(format: "%.2f", slowest.1))s action=\(slowest.0) windows=\(app.windows.count)")
    }

    @MainActor
    private func perform(_ action: MacMonkeyAction, on app: XCUIApplication, using rng: inout MacSeededGenerator) {
        switch action {
        case .click(let x, let y):
            app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).click()
        case .rightClick(let x, let y):
            app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).rightClick()
        case .clickRandomButton:
            // Window controls excluded: closing the window is not a crash, but every action
            // after it would land on nothing and the run would report a wedged app.
            let buttons = app.windows.buttons.allElementsBoundByIndex.filter {
                $0.exists && $0.isHittable && !["close", "minimize", "zoom"].contains($0.identifier)
            }
            if let target = buttons.randomElement(using: &rng) { target.click() }
        case .type(let text):
            app.typeText(text)
        case .escape:
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        case .scroll(let delta):
            app.windows.firstMatch.scroll(byDeltaX: 0, deltaY: delta)
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

enum MacMonkeyAction: CustomStringConvertible {
    case click(x: CGFloat, y: CGFloat)
    case rightClick(x: CGFloat, y: CGFloat)
    case clickRandomButton
    case type(String)
    case escape
    case scroll(CGFloat)

    static func random(using rng: inout MacSeededGenerator) -> MacMonkeyAction {
        switch Int.random(in: 0..<100, using: &rng) {
        case 0..<30:
            return .click(x: CGFloat.random(in: 0.05...0.95, using: &rng),
                          y: CGFloat.random(in: 0.08...0.95, using: &rng))
        case 30..<55: return .clickRandomButton
        case 55..<65:
            return .rightClick(x: CGFloat.random(in: 0.2...0.9, using: &rng),
                               y: CGFloat.random(in: 0.2...0.9, using: &rng))
        case 65..<80: return .type(randomText(using: &rng))
        case 80..<92: return .scroll(CGFloat.random(in: -10...10, using: &rng))
        default:      return .escape
        }
    }

    private static func randomText(using rng: inout MacSeededGenerator) -> String {
        let samples = ["monkey task", "🐒", "'; DROP TABLE tasks; --",
                       "tomorrow at 5pm", "   ", "日本語のタスク", String(repeating: "x", count: 80)]
        return samples.randomElement(using: &rng)!
    }

    var description: String {
        switch self {
        case .click(let x, let y): return String(format: "click(%.2f, %.2f)", x, y)
        case .rightClick(let x, let y): return String(format: "rightClick(%.2f, %.2f)", x, y)
        case .clickRandomButton: return "clickRandomButton"
        case .type(let t): return "type(\(t.prefix(16)))"
        case .escape: return "escape"
        case .scroll(let d): return String(format: "scroll(%.1f)", d)
        }
    }
}

/// SplitMix64 — see the iOS monkey for why a seeded generator matters here.
struct MacSeededGenerator: RandomNumberGenerator {
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
        let bundle = Bundle(for: MacMonkeyConfigToken.self)
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

private final class MacMonkeyConfigToken {}
