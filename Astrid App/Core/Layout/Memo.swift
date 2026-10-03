//  Memo.swift
//  Remember one derived value until its inputs change (AITD-455).
//
//  A SwiftUI body is re-evaluated far more often than its data changes — a selection, a drag
//  hover, a sheet. Work derived from every task (the list rows, the sidebar badges) was redone on
//  each of those. Hold one of these in `@State` and ask it for the value with a key that names
//  every input: it is a class, so remembering does not itself invalidate the view.
//
//  Put arrays in the key as they are stored (`taskService.tasks`, not a concatenation): Array's
//  `==` returns at once when both sides share a buffer, so an unchanged array costs nothing to
//  check.

import Foundation

final class Memo<Key: Equatable, Value> {
    private var key: Key?
    private var value: Value?

    func value(for key: Key, compute: () -> Value) -> Value {
        if let value, self.key == key { return value }
        let fresh = compute()
        self.key = key
        value = fresh
        return fresh
    }
}
