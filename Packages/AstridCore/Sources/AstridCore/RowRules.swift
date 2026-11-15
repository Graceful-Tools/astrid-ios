import Foundation

/// The rest of the row rules, asked of astrid-core's rule door (core `2b50348`, AWTD2-216;
/// AITD-622). Each used to be a Swift copy of a function the core already had — the detail
/// layout, the leading picker, a row's list chips and the day offset — and each is now one
/// question. Every answer is nil only when the core could not answer; the caller picks the safe
/// fallback.

/// What a task's detail draws (`rows::detail`): the field order under the title, and whether the
/// board-state and blockers rows appear.
public struct DetailLayoutAnswer: Decodable, Equatable, Sendable {
    /// `assignee`, `when`, `priority`, `lists` — top to bottom.
    public let fieldOrder: [String]
    public let showsBoardState: Bool
    public let showsTaskBlockers: Bool
}

/// What the leading control's picker offers, and whose task it is.
public struct LeadingPickerAnswer: Decodable, Equatable, Sendable {
    public let pickerShowsProjectState: Bool
    public let isSomeoneElsesTask: Bool
}

/// One list the core asks for when it decides a row's chips. Only what the rule reads: the id
/// it hands back, and the type that marks a board column.
public struct ChipListInput: Encodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let listType: String?

    public init(id: String, name: String, listType: String?) {
        self.id = id
        self.name = name
        self.listType = listType
    }
}

extension CoreRules {
    public static func detailLayout(displayMode: String, isInProject: Bool, isReadOnly: Bool,
                                    hasBlockers: Bool = false) -> DetailLayoutAnswer? {
        try? ask(DetailLayoutRequest(displayMode: displayMode, isInProject: isInProject,
                                     isReadOnly: isReadOnly, hasBlockers: hasBlockers),
                 as: DetailLayoutAnswer.self)
    }

    public static func leadingPicker(displayMode: String, surface: String, assigneeId: String?,
                                     currentUserId: String?) -> LeadingPickerAnswer? {
        try? ask(LeadingPickerRequest(displayMode: displayMode, surface: surface,
                                      assigneeId: assigneeId?.isEmpty == false ? assigneeId : nil,
                                      currentUserId: currentUserId),
                 as: LeadingPickerAnswer.self)
    }

    /// The ids of the lists a row draws as chips, in `lists` order, skipping board columns and
    /// `hiddenListIds` (the lists the surrounding view already shows).
    public static func listChipIds(lists: [ChipListInput], hiddenListIds: Set<String>) -> [String]? {
        let request = ListChipsRequest(listIds: lists.map(\.id), lists: lists,
                                       hiddenListIds: hiddenListIds.sorted())
        return (try? ask(request, as: [ListChipAnswer].self))?.map(\.id)
    }

    /// Whole days from the reader's today to `date`. An all-day date is compared as its UTC
    /// calendar date; a timed one as an instant in a zone `utcOffsetMinutes` from UTC.
    public static func dayOffset(to date: Date, isAllDay: Bool, now: Date,
                                 utcOffsetMinutes: Int) -> Int? {
        let request = DayOffsetRequest(date: date, isAllDay: isAllDay, now: now,
                                       utcOffsetMinutes: utcOffsetMinutes)
        return (try? ask(request, as: DayOffsetAnswer.self)).map(\.days)
    }
}

private struct DetailLayoutRequest: Encodable {
    let kind = "detailLayout"
    let displayMode: String
    let isInProject: Bool
    let isReadOnly: Bool
    let hasBlockers: Bool
}

private struct LeadingPickerRequest: Encodable {
    let kind = "leadingPicker"
    let displayMode: String
    let surface: String
    let assigneeId: String?
    let currentUserId: String?
}

private struct ListChipsRequest: Encodable {
    let kind = "listChips"
    let listIds: [String]
    let lists: [ChipListInput]
    let hiddenListIds: [String]
}

private struct ListChipAnswer: Decodable {
    let id: String
}

private struct DayOffsetRequest: Encodable {
    let kind = "dayOffset"
    let date: Date
    let isAllDay: Bool
    let now: Date
    let utcOffsetMinutes: Int
}

private struct DayOffsetAnswer: Decodable {
    let days: Int
}
