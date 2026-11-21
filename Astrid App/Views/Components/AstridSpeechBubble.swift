import SwiftUI

/// How much room an empty state's art gets (ADEV-166): iOS's full 160 pt, the Mac's denser
/// window, where a pane or a board column is smaller and read at desk distance, or none at all —
/// a project's short board rows, which skip the art so one board never shows a different metaphor
/// per row (ADEV-127).
enum EmptyStateDensity {
    case regular, compact, textOnly

    var artSize: CGFloat {
        switch self {
        case .regular: return AstridTokens.Layout.Comfortable.emptyArt
        case .compact: return AstridTokens.Layout.Compact.emptyArt
        case .textOnly: return 0
        }
    }
}

/// The one empty state (ADEV-166): Astrid — or a board column's hi-fi art — beside a speech
/// bubble. iOS's `EmptyStateView`, `ReminderView`, the Mac's `MacEmptyState` and an empty Mac board
/// column all draw through it; only the art size (`density`) differs.
struct AstridSpeechBubble: View {
    @ThemedPalette private var palette
    @AppStorage("themeMode") private var themeMode: String = "ocean"

    let message: String
    /// A muted second line under the message (the Mac's search hint, "clear the filter"…).
    var detail: String? = nil
    /// Art to draw in place of the brand character — a board column's cached hi-fi empathy
    /// frame (ADEV-127). Nil draws the built-in character, as always.
    var character: PlatformImage? = nil
    var density: EmptyStateDensity = .regular
    /// Names the message for the UI suite when the copy is localized (AITD-526).
    var messageIdentifier: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if density == .textOnly {
                EmptyView()
            } else if let character {
                Image(platformImage: character)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: density.artSize, height: density.artSize)
                    .accessibilityHidden(true)
            } else if let character = Brand.characterImage {
                Image(character)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: density.artSize, height: density.artSize)
            }

            // Speech bubble (flexible width)
            ZStack(alignment: .leading) {
                // Bubble content
                VStack(alignment: .leading, spacing: Theme.spacing4) {
                    messageText
                    if let detail {
                        detailText(detail)
                    }
                }
                .padding(density == .regular ? Theme.spacing16 : Theme.spacing12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(getBubbleBackground())
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(getBubbleBorder(), lineWidth: 2)
                )

                // Speech bubble pointer (comic-style arrow pointing left to Astrid)
                // Matches web design: layered triangles for border effect
                if density != .textOnly {
                    GeometryReader { geometry in
                        let centerY = geometry.size.height / 2

                        ZStack {
                            // Outer triangle (border) - 16px wide total, extends 3px into bubble
                            Path { path in
                                path.move(to: CGPoint(x: -16, y: centerY))           // Left point (centered)
                                path.addLine(to: CGPoint(x: 3, y: centerY - 12))    // Top right (16px wide + 3px overlap)
                                path.addLine(to: CGPoint(x: 3, y: centerY + 12))    // Bottom right
                                path.closeSubpath()
                            }
                            .fill(getPointerBorderColor())

                            // Inner triangle (fill) - 13px wide total, extends 3px into bubble
                            Path { path in
                                path.move(to: CGPoint(x: -13, y: centerY))           // Left point (3px inset)
                                path.addLine(to: CGPoint(x: 3, y: centerY - 9.5))   // Top right (13px wide + 3px overlap)
                                path.addLine(to: CGPoint(x: 3, y: centerY + 9.5))   // Bottom right
                                path.closeSubpath()
                            }
                            .fill(getBubbleBackground())
                        }
                        .offset(x: 0, y: 0)  // Positioned at bubble edge
                    }
                }
            }
        }
    }

    // MARK: - Text

    @ViewBuilder
    private var messageText: some View {
        let text = Text(message)
            #if os(macOS)
            .macFont(.body.weight(.semibold))
            #else
            .font(Theme.Typography.body())
            .fontWeight(.semibold)
            #endif
            .foregroundColor(palette.textPrimary)
        if let messageIdentifier {
            text.accessibilityIdentifier(messageIdentifier)
        } else {
            text
        }
    }

    private func detailText(_ detail: String) -> some View {
        Text(detail)
            #if os(macOS)
            .macFont(.caption)
            #else
            .font(Theme.Typography.caption1())
            #endif
            .foregroundColor(palette.textMuted)
    }

    // MARK: - Theme Helpers
    //
    // The palette already resolves Ocean (black text on a white bubble with a cyan border), so the
    // fixed `Theme.Ocean.*` reads these used to make are the palette's own values.

    private func getBubbleBackground() -> Color { palette.bgSecondary }

    private func getBubbleBorder() -> Color { palette.border }

    /// Get pointer border color - cyan on Ocean theme
    private func getPointerBorderColor() -> Color {
        themeMode == "ocean" ? palette.border : palette.borderHover
    }
}

#Preview {
    VStack(spacing: 32) {
        AstridSpeechBubble(message: "Hi there! Have a sec? Ready to put this in the past?")
            .padding()

        AstridSpeechBubble(message: "Create a list to organize your tasks and keep everything in order!")
            .padding()
    }
    .background(Theme.bgPrimary)
}

#Preview("Dark Mode") {
    VStack(spacing: 32) {
        AstridSpeechBubble(message: "Time to work! I promise you'll feel better if you finish this!")
            .padding()
    }
    .background(Theme.bgPrimary)
    .preferredColorScheme(.dark)
}
