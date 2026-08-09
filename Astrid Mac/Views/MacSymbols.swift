//  MacSymbols.swift
//  Astrid for Mac — SF Symbol names that need to be right (task 59d51b80).
//
//  A wrong systemName fails SILENTLY: SwiftUI renders nothing and you get an invisible
//  control. The detail header's overflow menu asked for "ellipsis.vertical", which does not
//  exist on macOS, so its label came out empty and the only visible thing was the chevron
//  .menuStyle(.borderlessButton) draws for itself — the "^" the task reported.
//
//  Named here so MacSymbolsTests can resolve them through NSImage, the way AppKit will.

#if os(macOS)
import Foundation

enum MacSymbols {
    /// The task detail overflow menu (copy / share / delete). macOS has no vertical ellipsis
    /// symbol, so the vertical form is the horizontal one turned a quarter turn — see
    /// `MacSymbols.detailMenuRotation`.
    static let detailMenu = "ellipsis"

    /// Quarter turn that stands the ellipsis up, for the vertical ⋮ the task asked for.
    static let detailMenuRotation: Double = 90
}
#endif
