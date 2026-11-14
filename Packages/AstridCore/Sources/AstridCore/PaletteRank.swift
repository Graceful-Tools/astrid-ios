import Foundation

extension CoreRules {
    /// The indices of the `titles` that match `query`, best first — astrid-core's `paletteRank`
    /// (`palette::rank`, AITD-667), the Mac ⌘K palette's ranking.
    ///
    /// Every character of the query in order, case-insensitively; a run of consecutive
    /// characters, a word start and the start of the title score higher. A tie goes to the
    /// shorter title, then to the order given. The caller trims the query and decides what an
    /// empty one shows. Never throws: a question the core cannot read matches nothing.
    public static func paletteRank(query: String, titles: [String]) -> [Int] {
        (try? ask(PaletteRankRequest(query: query, titles: titles), as: [Int].self)) ?? []
    }
}

private struct PaletteRankRequest: Encodable {
    let kind = "paletteRank"
    let query: String
    let titles: [String]
}
