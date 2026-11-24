//  OrientationLockTests.swift
//  ADEV-233 — Jon, 2026-11-23: "on iphone when looking at a decision matrix I am unable to view it
//  in landscape ... the app generally doesn't allow this, but we should enable this through a
//  button." The iPhone stays upright everywhere until a full-screen grid asks for landscape.

import UIKit
import XCTest
@testable import Astrid_App

@MainActor
final class OrientationLockTests: XCTestCase {

    func testADEV233_anIPhoneStaysUprightUnlessAGridAsks() {
        XCTAssertEqual(OrientationLock.mask(idiom: .phone, landscape: false), [.portrait, .portraitUpsideDown])
        XCTAssertEqual(OrientationLock.mask(idiom: .phone, landscape: true), .landscape)
    }

    func testADEV233_anIPadTurnsFreelyAsBefore() {
        XCTAssertEqual(OrientationLock.mask(idiom: .pad, landscape: false), .all)
        XCTAssertEqual(OrientationLock.mask(idiom: .pad, landscape: true), .all)
    }

    func testADEV233_theAppDelegateAnswersFromTheLock() {
        let answer = AstridAppDelegate().application(.shared, supportedInterfaceOrientationsFor: nil)
        XCTAssertEqual(answer, OrientationLock.current)
        XCTAssertFalse(OrientationLock.landscapeRequested, "upright until a grid asks")
    }
}
