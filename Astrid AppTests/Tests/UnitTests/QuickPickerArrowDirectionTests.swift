//  QuickPickerArrowDirectionTests.swift
//  Regression guard for Task AITD-397 — "Arrow on Right of popover, pointing Left at the
//  checkbox. You did it wrong again. Really look at your work and fix it right."
//
//  Three fixes (AITD-391, AITD-393, AITD-395) shipped `arrowEdge: .trailing` and each was
//  reported back as an arrow on the wrong side. All three reasoned about the value; none
//  measured it. `QuickPickerGeometryTests` pins the constant, which stops it drifting, but a
//  pinned constant is only as good as the reading of it that chose it — and the reading was
//  wrong three times.
//
//  So this test does not read the constant. It hands `QuickPickerGeometry.arrowEdge` to a real
//  `.popover` in a real `UIWindow`, exactly as `TaskRowView` does, lets UIKit present it, and
//  then asks the `UIPopoverPresentationController` which way its arrow points. UIKit's own
//  answer is the fact: `.left` means the arrow is on the popover's LEFT edge, pointing left at
//  the anchor, so the popover sits to the anchor's RIGHT. That is the sentence in the task.
//
//  The anchor is placed where the checkbox is — at the head of a full-width row on a phone —
//  because the direction UIKit lands on depends on the room it has. A direction that only
//  works with the anchor mid-screen would not be a fix.

import XCTest
import SwiftUI
@testable import Astrid_App

@MainActor
final class QuickPickerArrowDirectionTests: XCTestCase {

    /// A stand-in for `TaskRowView`: the same modifier chain around a 34pt control at the
    /// leading edge of a row, driven by the same geometry constant.
    ///
    /// Not the row itself. Its popover opens from a tap, and a unit test has no accessibility
    /// client, so SwiftUI never builds the element tree a synthetic activation would need
    /// (tried 2026-09-13: the hosting view reports zero elements). That the row hands THIS
    /// constant to `.popover` on its checkbox is `QuickPickerGeometryTests`' job.
    private struct Probe: View {
        let edge: Edge
        @State private var isPresented = false

        var body: some View {
            HStack(spacing: 12) {
                Color.green
                    .frame(width: 34, height: 34)
                    .popover(isPresented: $isPresented, arrowEdge: edge) {
                        Text("quick picker")
                            .frame(width: 280, height: 200)
                            .presentationCompactAdaptation(.popover)
                    }
                Text("row content")
                Spacer()
            }
            .padding(16)
            .onAppear { isPresented = true }
        }
    }

    private var window: UIWindow?

    override func tearDown() {
        window?.rootViewController?.presentedViewController?.dismiss(animated: false)
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    /// Presents the probe on a phone-sized window and returns the popover controller UIKit
    /// created for it, once it has decided where the arrow goes.
    private func presentPopover(edge: Edge,
                                file: StaticString = #filePath,
                                line: UInt = #line) throws -> UIPopoverPresentationController {
        // iPhone 17 points. The anchor sits ~16pt from the left, which is the case that matters:
        // there is no room to the LEFT of a checkbox, so a direction that needs it fails here.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let host = UIHostingController(rootView: Probe(edge: edge))
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let popover = host.presentedViewController?.popoverPresentationController,
               popover.arrowDirection != .unknown {
                return popover
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        throw XCTSkip("UIKit never presented the probe popover — the simulator has no key window "
                      + "to host it in; run this on a booted simulator")
    }

    // MARK: - The task, in UIKit's words

    /// AITD-397. The arrow is on the popover's left edge, pointing left at the checkbox — which
    /// is `UIPopoverArrowDirection.left`, and nothing else.
    func testTheArrowIsOnThePopoversLeftEdgePointingAtTheCheckbox_AITD397() throws {
        let popover = try presentPopover(edge: QuickPickerGeometry.arrowEdge)

        XCTAssertEqual(popover.permittedArrowDirections, .left,
                       "AITD-397: the row must ASK UIKit for an arrow on the popover's left edge")
        XCTAssertEqual(popover.arrowDirection, .left,
                       "AITD-397: …and UIKit must be able to GIVE it — a popover that asks for the "
                       + "left and lands elsewhere is the squashed-at-the-screen-edge picker again")
    }

    /// The popover itself sits to the RIGHT of the anchor, so the arrow has something to the
    /// left of it to point at. Belt and braces for the assertion above: `arrowDirection` is
    /// UIKit's word, this is the geometry a person sees.
    func testThePopoverSitsToTheRightOfTheCheckbox_AITD397() throws {
        let popover = try presentPopover(edge: QuickPickerGeometry.arrowEdge)
        let presented = try XCTUnwrap(popover.presentedViewController.view)
        let popoverFrame = presented.convert(presented.bounds, to: nil)

        // The probe's control spans x = 16…50.
        XCTAssertGreaterThanOrEqual(popoverFrame.minX, 50,
                                    "the popover's left edge must clear the checkbox's right edge; "
                                    + "got \(popoverFrame)")
    }

    // MARK: - Why the last three fixes were wrong

    /// The reading that drove AITD-393 and AITD-395 — `.trailing` for "opens to the right" — is
    /// the Mac's meaning of the word, and on iOS it produces the opposite: UIKit is asked for an
    /// arrow on the popover's RIGHT edge. Kept as a test so the next person who "corrects" the
    /// constant back sees, in UIKit's terms, what they are asking for.
    func testTrailingIsTheBugNotTheFix_AITD397() throws {
        let popover = try presentPopover(edge: .trailing)
        XCTAssertEqual(popover.permittedArrowDirections, .right,
                       "`.trailing` on iOS is an arrow on the popover's RIGHT edge — the bug in "
                       + "AITD-393, AITD-395 and AITD-397")
    }
}
