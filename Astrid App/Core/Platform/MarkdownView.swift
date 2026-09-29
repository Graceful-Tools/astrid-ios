//  MarkdownView.swift
//  A description, a comment or a chat message, drawn — on iOS and on the Mac.
//
//  What the text MEANS is astrid-core's: `CoreRules.markdown` renders it the way the web's
//  `renderMarkdownWithLinks` does (full GitHub-flavoured markdown, a newline is a line break, bare
//  URLs link, `@`/`#`/`!` references are pills). This file only draws the answer. Before it, each
//  platform parsed a subset of markdown itself, and the two drifted from each other and from the
//  web (AITD-389, AITD-390, AITD-416).
//
//  One view for both platforms. What differs — fonts, colours, spacing, whether a bubble hugs its
//  text — arrives as a `MarkdownStyle`; the structure is drawn once.

import AstridCore
import SwiftUI

/// How one platform, in one place, wants markdown to look.
struct MarkdownStyle {
    var body: Font
    var heading: (Int) -> Font
    var code: Font
    var text: Color
    var muted: Color
    var codeBackground: Color
    var blockSpacing: CGFloat
    var markerSpacing: CGFloat
    var codePadding: CGFloat
    var codeCornerRadius: CGFloat
    /// Does this fill the width it is given, or hug its text? A description owns its column and
    /// fills; a comment or chat bubble is sized to its content and hugs, or every bubble would
    /// stretch across the thread and lose the left/right layout that says whose message it is.
    var fillsWidth: Bool
}

struct MarkdownView: View {
    let blocks: [MarkdownBlock]
    let style: MarkdownStyle
    /// Set by a comment thread or a chat (AITD-439); everywhere else task ids stay text.
    @Environment(\.taskIdentifierLinks) private var identifiers

    init(source: String, style: MarkdownStyle) {
        self.init(blocks: CoreRules.markdown(source), style: style)
    }

    init(blocks: [MarkdownBlock], style: MarkdownStyle) {
        self.blocks = blocks
        self.style = style
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.blockSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                self.block(block)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: style.fillsWidth ? .infinity : nil, alignment: .leading)
    }

    /// Type-erased because a block can hold blocks — a quote, a list item — and a view whose body
    /// contains itself has no concrete type to name.
    private func block(_ block: MarkdownBlock) -> AnyView {
        switch block {
        case .paragraph(let inlines):
            return AnyView(inline(inlines).font(style.body))
        case .heading(let level, let inlines):
            return AnyView(inline(inlines).font(style.heading(level)).padding(.top, 2))
        case .code(_, let text):
            return AnyView(code(text))
        case .list(let ordered, let start, let items):
            return AnyView(list(ordered: ordered, start: start, items: items))
        case .quote(let blocks):
            return AnyView(
                HStack(alignment: .top, spacing: style.markerSpacing) {
                    RoundedRectangle(cornerRadius: 1).fill(style.muted.opacity(0.5)).frame(width: 3)
                    MarkdownView(blocks: blocks, style: style.quoted)
                }
                .fixedSize(horizontal: false, vertical: true))
        case .rule:
            return AnyView(Divider().padding(.vertical, 2))
        case .table(_, let header, let rows):
            return AnyView(table(header: header, rows: rows))
        }
    }

    private func inline(_ inlines: [MarkdownInline]) -> Text {
        Text(MarkdownRendering.attributed(inlines, defaultColor: style.text, referenceFont: nil,
                                          identifiers: identifiers))
    }

    /// A list row keeps its marker in a column of its own, so wrapped text lines up under itself
    /// rather than under the number. The number is the one the author wrote.
    private func list(ordered: Bool, start: Int, items: [MarkdownListItem]) -> some View {
        VStack(alignment: .leading, spacing: style.blockSpacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: style.markerSpacing) {
                    Text(marker(ordered: ordered, number: start + index, checked: item.checked))
                        .font(style.body)
                        .foregroundColor(style.muted)
                        .frame(minWidth: 14, alignment: .trailing)
                    MarkdownView(blocks: item.blocks, style: style)
                    // Pins the marker column to the left of a view wider than its text. A bubble
                    // has no spare width, and asking for it would demand the whole thread's.
                    if style.fillsWidth { Spacer(minLength: 0) }
                }
            }
        }
    }

    private func marker(ordered: Bool, number: Int, checked: Bool?) -> String {
        switch checked {
        case .some(true): return "☑"
        case .some(false): return "☐"
        case .none: return ordered ? "\(number)." : "•"
        }
    }

    /// Verbatim, monospaced, and never markdown — that is the whole promise of a fence.
    private func code(_ text: String) -> some View {
        // The core keeps the fence's final newline, as the web's `<pre>` does; a view drawing it
        // would show an empty last line.
        Text(text.hasSuffix("\n") ? String(text.dropLast()) : text)
            .font(style.code)
            .foregroundColor(style.text)
            .frame(maxWidth: style.fillsWidth ? .infinity : nil, alignment: .leading)
            .padding(style.codePadding)
            .background(style.codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: style.codeCornerRadius))
    }

    private func table(header: [[MarkdownInline]], rows: [[[MarkdownInline]]]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: style.markerSpacing * 2, verticalSpacing: style.blockSpacing) {
            GridRow {
                ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                    inline(cell).font(style.body.bold())
                }
            }
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        inline(cell).font(style.body)
                    }
                }
            }
        }
    }
}

private extension MarkdownStyle {
    /// A quote is the same text, quieter.
    var quoted: MarkdownStyle {
        var style = self
        style.text = muted
        return style
    }
}

private struct TaskIdentifierLinksKey: EnvironmentKey {
    static let defaultValue: TaskIdentifiers.LinkContext? = nil
}

extension EnvironmentValues {
    /// Which task ids link in the markdown below (AITD-439). A comment thread sets it from its
    /// task, a chat from its list; `nil` — the default — links none.
    var taskIdentifierLinks: TaskIdentifiers.LinkContext? {
        get { self[TaskIdentifierLinksKey.self] }
        set { self[TaskIdentifierLinksKey.self] = newValue }
    }
}

/// The inline half: runs and references as one attributed string. Shared by the block view and
/// by the surfaces that draw a whole text as a single `Text` (the inline editor's preview).
enum MarkdownRendering {
    /// Where a reference goes when tapped. One scheme, so a deep link cannot change on one
    /// platform only.
    static func url(for reference: MarkdownReference, id: String) -> URL? {
        switch reference {
        case .user: return URL(string: "astrid://users/\(id)")
        case .list: return URL(string: "astrid://lists/\(id)")
        case .task: return URL(string: "astrid://tasks/\(id)")
        }
    }

    /// People blue, lists green, tasks orange — as on the web.
    static func color(for reference: MarkdownReference) -> Color {
        switch reference {
        case .user: return .blue
        case .list: return .green
        case .task: return .orange
        }
    }

    static func trigger(for reference: MarkdownReference) -> String {
        switch reference {
        case .user: return "@"
        case .list: return "#"
        case .task: return "!"
        }
    }

    /// - Parameter referenceFont: the font to stamp on a reference, or `nil` to leave it to the
    ///   surrounding view. A block renderer must pass `nil` (AITD-390): stamping `.body` inside a
    ///   heading draws the reference at body size while the words either side stay heading-sized.
    /// - Parameter identifiers: link task ids (`AWTD-12`, `#12`) in prose (AITD-439); `nil` links
    ///   none. Only plain runs are scanned: a code span, a link and a pill are already separate
    ///   inlines here, which is the masking the rule asks for.
    static func attributed(_ inlines: [MarkdownInline], defaultColor: Color,
                           referenceFont: Font?,
                           identifiers: TaskIdentifiers.LinkContext? = nil) -> AttributedString {
        var result = AttributedString()
        for inline in inlines {
            switch inline {
            case .text(let run):
                var piece = AttributedString(run.text)
                piece.foregroundColor = defaultColor
                var intent: InlinePresentationIntent = []
                if run.bold { intent.insert(.stronglyEmphasized) }
                if run.italic { intent.insert(.emphasized) }
                if run.strike { intent.insert(.strikethrough) }
                if run.code { intent.insert(.code) }
                if !intent.isEmpty { piece.inlinePresentationIntent = intent }
                if let link = run.link {
                    piece.link = URL(string: link)
                } else if let identifiers, !run.code {
                    linkIdentifiers(in: &piece, text: run.text, context: identifiers)
                }
                result += piece
            case .reference(let kind, let label, let id):
                var reference = AttributedString(trigger(for: kind) + label)
                reference.foregroundColor = color(for: kind)
                reference.font = referenceFont
                reference.link = url(for: kind, id: id)
                result += reference
            case .lineBreak:
                result += AttributedString("\n")
            }
        }
        return result
    }

    private static func linkIdentifiers(in piece: inout AttributedString, text: String,
                                        context: TaskIdentifiers.LinkContext) {
        for link in TaskIdentifiers.links(in: text, projectKey: context.projectKey,
                                          keys: context.keys, hidden: context.hidden) {
            guard let range = Range(link.range, in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: piece),
                  let upper = AttributedString.Index(range.upperBound, within: piece) else { continue }
            piece[lower..<upper].link = TaskIdentifiers.url(for: link.identifier)
        }
    }

    /// A whole text as one attributed string: each block on its own line, a list item with its
    /// marker, a fence verbatim. For a surface that can only hold a single `Text`.
    static func flattened(_ blocks: [MarkdownBlock], defaultColor: Color,
                          referenceFont: Font?) -> AttributedString {
        var lines: [AttributedString] = []
        for block in blocks {
            switch block {
            case .paragraph(let inlines), .heading(_, let inlines):
                lines.append(attributed(inlines, defaultColor: defaultColor, referenceFont: referenceFont))
            case .code(_, let text):
                var code = AttributedString(text.hasSuffix("\n") ? String(text.dropLast()) : text)
                code.foregroundColor = defaultColor
                code.inlinePresentationIntent = .code
                lines.append(code)
            case .list(let ordered, let start, let items):
                for (index, item) in items.enumerated() {
                    var line = AttributedString(ordered ? "\(start + index). " : "• ")
                    line.foregroundColor = defaultColor
                    line += flattened(item.blocks, defaultColor: defaultColor, referenceFont: referenceFont)
                    lines.append(line)
                }
            case .quote(let blocks):
                lines.append(flattened(blocks, defaultColor: defaultColor, referenceFont: referenceFont))
            case .rule:
                lines.append(AttributedString("—"))
            case .table(_, let header, let rows):
                for row in [header] + rows {
                    var line = AttributedString()
                    for (index, cell) in row.enumerated() {
                        if index > 0 { line += AttributedString(" · ") }
                        line += attributed(cell, defaultColor: defaultColor, referenceFont: referenceFont)
                    }
                    lines.append(line)
                }
            }
        }
        var result = AttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 { result += AttributedString("\n") }
            result += line
        }
        return result
    }
}

extension String {
    /// This text with its markdown marks and `@`/`#`/`!` references rendered, as one attributed
    /// string — through astrid-core, the same answer the block view draws.
    ///
    /// - Parameter referenceFont: see `MarkdownRendering.attributed`. A flat bubble wants `.body`,
    ///   the default; a block renderer passes `nil`.
    func attributedWithReferences(defaultColor: Color = .primary,
                                  referenceFont: Font? = .body) -> AttributedString {
        MarkdownRendering.flattened(CoreRules.markdown(self), defaultColor: defaultColor,
                                    referenceFont: referenceFont)
    }
}
