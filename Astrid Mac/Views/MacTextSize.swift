//  MacTextSize.swift
//  Astrid for Mac — app-wide text size (AITD-469).
//
//  SwiftUI's Dynamic Type is inert on macOS: `.dynamicTypeSize` changes nothing, and System
//  Settings' Text size slider only reaches Apple's own apps — there is no public API for a third
//  party to read it. So the Mac app owns its text size, offered the way Mac apps offer it
//  (View ▸ Bigger / Smaller / Actual Size, ⌘+ ⌘− ⌘0) and in Settings, and every Mac font goes
//  through `MacFont` + `.macFont(...)` so the setting reaches it. At 100% each font is exactly
//  the font it was before, so the default look does not move.

#if os(macOS)
import AppKit
import Combine
import SwiftUI

@MainActor
final class MacTextSize: ObservableObject {
    static let shared = MacTextSize()
    static let defaultsKey = "mac.textScale"
    /// The ladder ⌘+ / ⌘− walk. Below 85% Mac captions (10pt) stop being legible.
    static let steps: [CGFloat] = [0.85, 1.0, 1.15, 1.3, 1.5, 1.75, 2.0]

    @Published private(set) var scale: CGFloat
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.object(forKey: Self.defaultsKey) as? Double ?? 1.0
        scale = Self.steps.min(by: { abs($0 - stored) < abs($1 - stored) }) ?? 1.0
    }

    private var index: Int { Self.steps.firstIndex(of: scale) ?? 1 }
    var canGrow: Bool { index < Self.steps.count - 1 }
    var canShrink: Bool { index > 0 }
    var canReset: Bool { scale != 1.0 }

    func bigger() { set(Self.steps[min(index + 1, Self.steps.count - 1)]) }
    func smaller() { set(Self.steps[max(index - 1, 0)]) }
    func reset() { set(1.0) }

    func set(_ value: CGFloat) {
        guard Self.steps.contains(value), value != scale else { return }
        scale = value
        defaults.set(Double(value), forKey: Self.defaultsKey)
    }
}

/// A font that knows how to grow. `font(scale: 1)` is the plain SwiftUI font it replaces.
struct MacFont {
    private let make: (CGFloat) -> Font

    private init(_ make: @escaping (CGFloat) -> Font) { self.make = make }

    func font(scale: CGFloat) -> Font { make(scale) }

    // Text styles keep their native Font at 100% and become the same NSFont, resized, above it —
    // so headline stays bold and caption keeps its Mac point size as the base.
    private static func style(_ font: Font, _ style: NSFont.TextStyle) -> MacFont {
        MacFont { scale in
            let base = NSFont.preferredFont(forTextStyle: style)
            return scale == 1 ? font : Font(base.withSize(base.pointSize * scale) as CTFont)
        }
    }

    static let largeTitle = style(.largeTitle, .largeTitle)
    static let title = style(.title, .title1)
    static let title2 = style(.title2, .title2)
    static let title3 = style(.title3, .title3)
    static let headline = style(.headline, .headline)
    static let subheadline = style(.subheadline, .subheadline)
    static let body = style(.body, .body)
    static let callout = style(.callout, .callout)
    static let footnote = style(.footnote, .footnote)
    static let caption = style(.caption, .caption1)
    static let caption2 = style(.caption2, .caption2)

    // Optional like SwiftUI's own, so `.system(size: 12)` at 100% is the identical Font.
    static func system(size: CGFloat, weight: Font.Weight? = nil,
                       design: Font.Design? = nil) -> MacFont {
        MacFont { .system(size: size * $0, weight: weight, design: design) }
    }

    static func pointSize(of font: Font.TextStyle, scale: CGFloat) -> CGFloat {
        let ns: NSFont.TextStyle = switch font {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
        return NSFont.preferredFont(forTextStyle: ns).pointSize * scale
    }

    func bold() -> MacFont { MacFont { make($0).bold() } }
    func monospaced() -> MacFont { MacFont { make($0).monospaced() } }
    func weight(_ weight: Font.Weight) -> MacFont { MacFont { make($0).weight(weight) } }
}

private struct MacTextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var macTextScale: CGFloat {
        get { self[MacTextScaleKey.self] }
        set { self[MacTextScaleKey.self] = newValue }
    }
}

private struct MacFontModifier: ViewModifier {
    @Environment(\.macTextScale) private var scale
    let font: MacFont
    func body(content: Content) -> some View { content.font(font.font(scale: scale)) }
}

/// Publishes the text size to a window's views, and sizes the text that sets no font of its own
/// (text fields, plain `Text`) — which is left alone at 100%.
private struct MacTextScaleRoot: ViewModifier {
    @ObservedObject private var size = MacTextSize.shared
    func body(content: Content) -> some View {
        content
            .environment(\.macTextScale, size.scale)
            .font(size.scale == 1 ? nil : MacFont.body.font(scale: size.scale))
    }
}

extension View {
    func macFont(_ font: MacFont) -> some View { modifier(MacFontModifier(font: font)) }
    /// Apply once at the root of every scene.
    func macTextScaleRoot() -> some View { modifier(MacTextScaleRoot()) }
}
#endif
