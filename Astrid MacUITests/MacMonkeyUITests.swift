//  MacMonkeyUITests.swift
//  Random-input stress test for the Mac app. The iOS half is `MonkeyUITests.swift`; the seeded
//  generator and run configuration are shared through `UITestSupport/MonkeySupport.swift`. The
//  action set is platform-specific and stays here.
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
        let app = MacUITestLaunch.makeApp()
        app.launch()

        // Reach the shell the way the rest of the Mac suite does.
        let myTasks = MacUITestLaunch.enterShell(app)
        try XCTSkipUnless(myTasks.exists, "Never reached the shell, so there is nothing to stress")

        var rng = SeededGenerator(seed: seed)
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
    private func perform(_ action: MacMonkeyAction, on app: XCUIApplication, using rng: inout SeededGenerator) {
        // Coordinates are taken from the WINDOW, never from the application element. On macOS
        // XCUIApplication has no meaningful frame, so a normalised offset against it resolves to
        // INFINITY and XCTest traps with "Invalid parameter not satisfying: point.x != INFINITY".
        // On iOS the app element is the screen and this distinction does not exist, which is what
        // makes it easy to write the iOS version and assume it ports.
        let window = app.windows.firstMatch
        let hasWindow = window.exists && window.frame.width > 1 && window.frame.height > 1

        switch action {
        case .click(let x, let y):
            guard hasWindow else { return }
            window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).click()
        case .rightClick(let x, let y):
            guard hasWindow else { return }
            window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).rightClick()
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
            guard hasWindow else { return }
            window.scroll(byDeltaX: 0, deltaY: delta)
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

    static func random(using rng: inout SeededGenerator) -> MacMonkeyAction {
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

    private static func randomText(using rng: inout SeededGenerator) -> String {
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
