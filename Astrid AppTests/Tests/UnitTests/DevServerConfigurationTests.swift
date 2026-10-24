//  DevServerConfigurationTests.swift
//  Task AITD-351 — one developer's home LAN IP was the on-device Debug server.
//
//  `Constants.Environment.development.baseURL` (non-simulator) and `ServerOption.localNetwork`
//  both carried `192.168.50.254:3000`, and `Info-Debug.plist`'s ATS exception carried
//  `192.168.50.161` — a DIFFERENT address, so the exception had not covered the one in use for
//  some time. A Debug build on anyone else's device, or on another network, pointed silently at
//  an unreachable host.
//
//  Release was never affected, so this is hygiene. The guard is what keeps it from returning.

import XCTest
@testable import Astrid_App

final class DevServerConfigurationTests: XCTestCase {

    // MARK: - The fallback

    func testAnUnsetDevServerReadsAsAbsent() {
        // Nothing sets ASTRID_DEV_SERVER_URL in CI or on a fresh clone, so this is the default
        // state: no dev server, and the device Debug build falls back to production.
        XCTAssertNil(Constants.API.devServerURL,
                     "an undefined build setting expands to an empty string, which must read as "
                     + "'no dev server' rather than as a URL")
    }

    #if DEBUG
    func testTheDevServerRowIsHiddenWhenNoneIsConfigured() {
        XCTAssertFalse(Constants.API.ServerOption.available.contains(.devServer),
                       "an option that silently means 'production' is worse than no option")
        XCTAssertTrue(Constants.API.ServerOption.available.contains(.production))
        XCTAssertTrue(Constants.API.ServerOption.available.contains(.localhost))
    }
    #endif
}
