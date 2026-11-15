import CoreGraphics
import Foundation

/// Where a task callout opens from the card or row it belongs to, and where its arrow points —
/// astrid-core's `calloutPlacement` rule (`rows::callout::place`, core b1f6f2e; AITD-678, AITD-679).
///
/// The side is whichever has more room (ties go right), the box is clamped into the viewport, and
/// the arrow aims at the anchor's middle, kept clear of both corners. The caller measures the
/// callout's SIZE; the rule only places it. One coordinate space, y increasing downward, in points.
public struct CalloutPlacement: Decodable, Equatable, Sendable {
    public enum Side: String, Decodable, Sendable {
        case left, right
    }

    public let side: Side
    public let left: Double
    public let top: Double
    public let width: Double
    public let height: Double
    /// How far down the callout's anchored edge to draw the arrow, from `top`.
    public let arrowOffset: Double

    /// The callout's box, already clamped into the viewport.
    public var frame: CGRect { CGRect(x: left, y: top, width: width, height: height) }
}

extension CoreRules {
    /// Place a callout of `size` against `anchor`, inside `viewport`, all in one space.
    public static func calloutPlacement(anchor: CGRect, viewport: CGRect, size: CGSize) throws -> CalloutPlacement {
        try ask(CalloutPlacementRequest(anchor: WireRect(anchor), viewport: WireRect(viewport),
                                        width: Double(size.width), height: Double(size.height)),
                as: CalloutPlacement.self)
    }
}

private struct CalloutPlacementRequest: Encodable {
    let kind = "calloutPlacement"
    let anchor: WireRect
    let viewport: WireRect
    let width: Double
    let height: Double
}

private struct WireRect: Encodable {
    let left: Double
    let top: Double
    let width: Double
    let height: Double

    init(_ rect: CGRect) {
        left = Double(rect.minX)
        top = Double(rect.minY)
        width = Double(rect.width)
        height = Double(rect.height)
    }
}
