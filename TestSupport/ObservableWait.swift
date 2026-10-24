//  ObservableWait.swift
//  Wait for an ObservableObject to reach a state — on its change signal, not on a clock (AITD-534).
//
//  The tests this replaced slept 20 ms at a time for up to five seconds and read a property. On a
//  loaded runner that is a flake; on a fast one it is wasted time. Here the condition is checked
//  each time the object announces a change, and the wait fails, naming what it waited for, only
//  if no announcement ever makes it true.

import Combine
import Foundation
import XCTest

extension XCTestCase {
    @MainActor
    func waitUntil<Object: ObservableObject>(_ object: Object, timeout: TimeInterval = 5,
                                             _ what: String,
                                             _ condition: @escaping @MainActor () -> Bool) async {
        if condition() { return }
        let reached = expectation(description: what)
        reached.assertForOverFulfill = false
        // `objectWillChange` fires BEFORE the change lands, so look again on the next main-queue turn.
        let watch = object.objectWillChange.receive(on: DispatchQueue.main).sink { _ in
            MainActor.assumeIsolated { if condition() { reached.fulfill() } }
        }
        await fulfillment(of: [reached], timeout: timeout)
        watch.cancel()
    }
}
