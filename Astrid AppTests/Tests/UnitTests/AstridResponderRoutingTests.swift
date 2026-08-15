//  AstridResponderRoutingTests.swift
//  Regression for task 9dce4c73 — Astrid never answered a chat @mention when a SERVER-SIDE agent
//  was the selected assistant.
//
//  The bug was invisible in the code because two different situations shared one `return`:
//
//    - the message was not addressed to Astrid    → correct silence
//    - it WAS, but we cannot answer it here       → the bug
//
//  `shouldRespond` answers Bool, so the second case could only ever be spelled "false", the same
//  as the first. These pin the three-way answer, and in particular that "addressed to her but we
//  cannot" routes to the server rather than going quiet.

import XCTest
@testable import Astrid_App

final class AstridResponderRoutingTests: XCTestCase {

    // MARK: - The case the task is about

    /// A server-side agent is selected. She is still being asked, so somebody has to answer —
    /// and it cannot be this device.
    func testHandsOffToTheServerWhenAnotherAgentIsSelected() {
        XCTAssertEqual(OnDeviceAstrid.responder(isOnDeviceModel: false, isAvailable: true,
                                                content: "@[Astrid](u1) what is due today?",
                                                listId: "list-1"),
                       .server)
    }

    /// Selected, but the model is unavailable — older OS, unsupported hardware, or Apple
    /// Intelligence switched off. Same conclusion: not answerable here.
    func testHandsOffToTheServerWhenTheModelIsUnavailable() {
        XCTAssertEqual(OnDeviceAstrid.responder(isOnDeviceModel: true, isAvailable: false,
                                                content: "@[Astrid](u1) hi", listId: nil),
                       .server)
    }

    /// A personal channel is entirely hers, so an unanswerable message there hands off too —
    /// no @mention required.
    func testHandsOffInAPersonalChannelWithoutAMention() {
        XCTAssertEqual(OnDeviceAstrid.responder(isOnDeviceModel: false, isAvailable: true,
                                                content: "what is due today?", listId: nil),
                       .server)
    }

    // MARK: - What must NOT change

    /// The on-device path is still preferred whenever it can run. Handing this to the server
    /// would give up the privacy and latency that on-device Astrid exists for.
    func testStillAnswersOnDeviceWhenItCan() {
        XCTAssertEqual(OnDeviceAstrid.responder(isOnDeviceModel: true, isAvailable: true,
                                                content: "@[Astrid](u1) hi", listId: "list-1"),
                       .onDevice)
    }

    /// Chatter between people in a list channel is not addressed to her. This is the case that
    /// must stay silent — routing it to the server would make Astrid answer conversations she
    /// was never part of, which is worse than the bug being fixed.
    func testStaysQuietWhenSheWasNotAddressedAtAll() {
        XCTAssertEqual(OnDeviceAstrid.responder(isOnDeviceModel: false, isAvailable: false,
                                                content: "morning all", listId: "list-1"),
                       .nobody)
    }

    /// Not addressed to her stays silent even when the on-device model is ready and waiting.
    func testStaysQuietWithoutAMentionEvenWhenTheModelIsReady() {
        XCTAssertEqual(OnDeviceAstrid.responder(isOnDeviceModel: true, isAvailable: true,
                                                content: "morning all", listId: "list-1"),
                       .nobody)
    }

    // MARK: - Agreement with the old rule

    /// `shouldRespond` is what both chat views have always asked. It must keep meaning exactly
    /// "the on-device model answers this", or the split would silently change who replies.
    func testShouldRespondStillMeansOnDeviceExactly() {
        let cases: [(Bool, Bool, String, String?)] = [
            (true,  true,  "@[Astrid](u1) hi", "list-1"),
            (true,  true,  "hello",            nil),
            (false, true,  "@[Astrid](u1) hi", "list-1"),
            (true,  false, "@[Astrid](u1) hi", nil),
            (true,  true,  "morning all",      "list-1"),
            (false, false, "morning all",      "list-1"),
        ]
        for (onDevice, available, content, listId) in cases {
            let legacy = OnDeviceAstrid.shouldRespond(isOnDeviceModel: onDevice, isAvailable: available,
                                                      content: content, listId: listId)
            let routed = OnDeviceAstrid.responder(isOnDeviceModel: onDevice, isAvailable: available,
                                                  content: content, listId: listId) == .onDevice
            XCTAssertEqual(legacy, routed,
                           "shouldRespond and responder disagree for (\(onDevice), \(available), \(content))")
        }
    }
}
