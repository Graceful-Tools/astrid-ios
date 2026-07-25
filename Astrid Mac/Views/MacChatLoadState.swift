//  MacChatLoadState.swift
//  Astrid for Mac — pure chat surface state (Task e4d0eb84). The spinner shows ONLY during the
//  initial load with nothing cached; once loading completes the surface must resolve to empty or
//  messages — an indefinite spinner is a bug (the SSE typing subscription used to block the load
//  path so `loading` never cleared).

#if os(macOS)
import Foundation

enum MacChatSurface: Equatable {
    case spinner, empty, messages
}

enum MacChatLoadState {
    static func surface(loading: Bool, hasMessages: Bool) -> MacChatSurface {
        if hasMessages { return .messages }          // cached messages always win over the spinner
        return loading ? .spinner : .empty
    }
}
#endif
