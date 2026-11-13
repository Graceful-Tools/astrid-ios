import Foundation

/// What a description, a comment or a chat message says, as blocks a view draws — astrid-core's
/// `markdown::render`, which mirrors the web's `renderMarkdownWithLinks`: full GitHub-flavoured
/// markdown with `breaks: true`, bare URLs as links, only `http`/`https`/`mailto` links kept, HTML
/// as text, and Astrid's `@[Name](id)` / `#[List](id)` / `![Task](id)` references as pills.
///
/// The core decides what the text *means*; the view decides fonts and colours, and nothing else.
public indirect enum MarkdownBlock: Equatable, Sendable, Decodable {
    case paragraph([MarkdownInline])
    /// 1 through 6.
    case heading(level: Int, [MarkdownInline])
    /// A fenced or indented block, verbatim.
    case code(language: String?, text: String)
    /// `start` is the first number of an ordered list, as the author wrote it; `1` for bullets.
    case list(ordered: Bool, start: Int, items: [MarkdownListItem])
    case quote([MarkdownBlock])
    case rule
    case table(alignments: [MarkdownAlignment], header: [[MarkdownInline]], rows: [[[MarkdownInline]]])
    /// A table whose body cells all lead with a rating: a trade-off grid, picked out by the core
    /// (astrid-core AWTD-1626). `header` is the option column's heading, then one per criterion.
    /// `Decisions.grids` turns it into the `TradeOff` the views draw.
    case tradeoffGrid(header: [[MarkdownInline]], rows: [MarkdownGridRow])

    private enum Keys: String, CodingKey {
        case kind, inlines, level, language, text, ordered, start, items, blocks, alignments, header, rows
    }

    public init(from decoder: Decoder) throws {
        let block = try decoder.container(keyedBy: Keys.self)
        switch try block.decode(String.self, forKey: .kind) {
        case "paragraph":
            self = .paragraph(try block.decode([MarkdownInline].self, forKey: .inlines))
        case "heading":
            self = .heading(
                level: try block.decode(Int.self, forKey: .level),
                try block.decode([MarkdownInline].self, forKey: .inlines))
        case "code":
            self = .code(
                language: try block.decodeIfPresent(String.self, forKey: .language),
                text: try block.decode(String.self, forKey: .text))
        case "list":
            self = .list(
                ordered: try block.decode(Bool.self, forKey: .ordered),
                start: try block.decode(Int.self, forKey: .start),
                items: try block.decode([MarkdownListItem].self, forKey: .items))
        case "quote":
            self = .quote(try block.decode([MarkdownBlock].self, forKey: .blocks))
        case "rule":
            self = .rule
        case "table":
            self = .table(
                alignments: try block.decode([MarkdownAlignment].self, forKey: .alignments),
                header: try block.decode([[MarkdownInline]].self, forKey: .header),
                rows: try block.decode([[[MarkdownInline]]].self, forKey: .rows))
        case "tradeoffGrid":
            self = .tradeoffGrid(
                header: try block.decode([[MarkdownInline]].self, forKey: .header),
                rows: try block.decode([MarkdownGridRow].self, forKey: .rows))
        default:
            // A block kind a newer core draws and this build does not: keep its words.
            self = .paragraph([])
        }
    }
}

public struct MarkdownListItem: Equatable, Sendable, Decodable {
    /// `true`/`false` for a `- [x]` / `- [ ]` item; `nil` for an ordinary one.
    public let checked: Bool?
    public let blocks: [MarkdownBlock]

    public init(checked: Bool?, blocks: [MarkdownBlock]) {
        self.checked = checked
        self.blocks = blocks
    }
}

/// One option of a trade-off grid, as the core answers it.
public struct MarkdownGridRow: Equatable, Sendable, Decodable {
    /// The option, without the marker its writer put in front (`A. Lisbon` → `Lisbon`).
    public let name: [MarkdownInline]
    /// One per criterion.
    public let cells: [MarkdownGridCell]

    public init(name: [MarkdownInline], cells: [MarkdownGridCell]) {
        self.name = name
        self.cells = cells
    }
}

/// One criterion's cell in a trade-off grid.
public struct MarkdownGridCell: Equatable, Sendable, Decodable {
    /// The rating's label key — `veryPoor`, `poor`, `mixed`, `good`, `veryGood` — or nil for an
    /// empty cell.
    public let rating: String?
    /// The reason, without its rating. A cell that is only a rating carries the token.
    public let inlines: [MarkdownInline]

    public init(rating: String?, inlines: [MarkdownInline]) {
        self.rating = rating
        self.inlines = inlines
    }
}

public enum MarkdownAlignment: String, Equatable, Sendable, Decodable {
    case left, center, right, none
}

public enum MarkdownInline: Equatable, Sendable, Decodable {
    case text(MarkdownRun)
    /// A person (`@`), a list (`#`) or a task (`!`), by id.
    case reference(MarkdownReference, label: String, id: String)
    case lineBreak

    private enum Keys: String, CodingKey { case kind, reference, label, id }

    public init(from decoder: Decoder) throws {
        let inline = try decoder.container(keyedBy: Keys.self)
        switch try inline.decode(String.self, forKey: .kind) {
        case "reference":
            self = .reference(
                try inline.decode(MarkdownReference.self, forKey: .reference),
                label: try inline.decode(String.self, forKey: .label),
                id: try inline.decode(String.self, forKey: .id))
        case "lineBreak":
            self = .lineBreak
        default:
            self = .text(try MarkdownRun(from: decoder))
        }
    }
}

/// One run of text and the marks on it.
public struct MarkdownRun: Equatable, Sendable, Decodable {
    public var text: String
    public var bold = false
    public var italic = false
    public var strike = false
    /// An inline code span.
    public var code = false
    /// An absolute `http`, `https` or `mailto` address, when the run is a link.
    public var link: String?

    public init(text: String, bold: Bool = false, italic: Bool = false, strike: Bool = false,
                code: Bool = false, link: String? = nil) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.strike = strike
        self.code = code
        self.link = link
    }
}

public enum MarkdownReference: String, Equatable, Sendable, Decodable {
    case user, list, task
}

extension CoreRules {
    /// Render `text` the way the web renders it. Never throws: text the core somehow cannot
    /// answer for comes back as one plain paragraph, because a message must never vanish.
    ///
    /// A link written relative to the app (`/lists/…`, `/u/…`, a task id's `/t/…`) opens on
    /// `origin` — the server the running session was started on unless one is named here. Without
    /// any, an ordinary core falls back to astrid.cc and a `require-base-url` one leaves the link
    /// relative, so a partner build must have one (AITD-652, astrid-web AWTD-1630).
    public static func markdown(_ text: String, origin: String? = nil) -> [MarkdownBlock] {
        struct Request: Encodable {
            let kind = "renderMarkdown"
            let text: String
            let origin: String?
        }
        return (try? ask(Request(text: text, origin: origin ?? markdownOrigin), as: [MarkdownBlock].self))
            ?? [.paragraph([.text(MarkdownRun(text: text))])]
    }

    /// Where `markdown`'s relative links open when a call names no origin. `CoreSession` sets it to
    /// its `baseURL` — the brand's server, which is the shell's to name (AITD-651) — so the app never
    /// threads it through each view.
    static var markdownOrigin: String? {
        get { originLock.withLock { storedOrigin } }
        set { originLock.withLock { storedOrigin = newValue } }
    }
    private static let originLock = NSLock()
    private nonisolated(unsafe) static var storedOrigin: String?
}
