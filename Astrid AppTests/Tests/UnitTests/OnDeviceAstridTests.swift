//  OnDeviceAstridTests.swift
//  Regression for task 8dded037 — Astrid must answer on device (Apple Intelligence) on Mac too.
//
//  The rule lived inline in iOS's chat input, so the Mac chat never ran it: with Apple Foundation
//  Models chosen as the agent, @mentioning Astrid on Mac did nothing. It is shared now, and these
//  pin the rule so the two platforms cannot answer differently.

import XCTest
@testable import Astrid_App

final class OnDeviceAstridTests: XCTestCase {

    func testAnswersWhenMentionedInAListChannel() {
        XCTAssertTrue(OnDeviceAstrid.shouldRespond(isOnDeviceModel: true, isAvailable: true,
                                                   content: "@[Astrid](u1) what is due today?",
                                                   listId: "list-1"))
    }

    /// In a personal channel she is the only other participant, so every message is for her.
    func testAnswersEveryMessageInAPersonalChannel() {
        XCTAssertTrue(OnDeviceAstrid.shouldRespond(isOnDeviceModel: true, isAvailable: true,
                                                   content: "what is due today?", listId: nil))
        XCTAssertTrue(OnDeviceAstrid.shouldRespond(isOnDeviceModel: true, isAvailable: true,
                                                   content: "hello", listId: "my-tasks"))
    }

    /// A message to other people in a list channel is not hers to answer.
    func testStaysQuietInAListChannelWithoutAMention() {
        XCTAssertFalse(OnDeviceAstrid.shouldRespond(isOnDeviceModel: true, isAvailable: true,
                                                    content: "morning all", listId: "list-1"))
    }

    /// Another agent is selected — the on-device path must not answer over it.
    func testStaysQuietWhenTheOnDeviceModelIsNotSelected() {
        XCTAssertFalse(OnDeviceAstrid.shouldRespond(isOnDeviceModel: false, isAvailable: true,
                                                    content: "@[Astrid](u1) hi", listId: nil))
    }

    /// Selected but unavailable (older OS / unsupported hardware): stay quiet rather than fail.
    func testStaysQuietWhenTheModelIsUnavailable() {
        XCTAssertFalse(OnDeviceAstrid.shouldRespond(isOnDeviceModel: true, isAvailable: false,
                                                    content: "@[Astrid](u1) hi", listId: nil))
    }

    func testMentionIsCaseInsensitiveForTheMarkup() {
        XCTAssertTrue(OnDeviceAstrid.shouldRespond(isOnDeviceModel: true, isAvailable: true,
                                                   content: "@[astrid](u1) hi", listId: "list-1"))
    }

    /// The model should read what a person would — not the mention markup.
    func testStripsMentionMarkup() {
        XCTAssertEqual(OnDeviceAstrid.plainMessage(from: "@[Astrid](user-123) what is due today?"),
                       "what is due today?")
    }

    func testStripsEveryMentionAndTrims() {
        XCTAssertEqual(
            OnDeviceAstrid.plainMessage(from: "  @[Astrid](u1) ping @[Bob](u2)  "),
            "ping")
    }

    /// A bare mention leaves nothing to ask — the caller skips rather than prompting with "".
    func testMentionOnlyMessageReducesToEmpty() {
        XCTAssertTrue(OnDeviceAstrid.plainMessage(from: "@[Astrid](u1)").isEmpty)
    }
}
