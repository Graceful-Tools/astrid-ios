//  ChatComposer.swift
//  The two decisions a message composer makes before anything reaches the network. (AITD-538)
//
//  Both used to live inline — `canSend` in RichTextInput, the upload context in ChatInputView —
//  and their tests re-implemented them, so a change to either could never fail a test. Mac's
//  chat panel had drifted from iOS on the context: a My Tasks upload went out with `[:]`.

import Foundation

enum ChatComposer {

    /// The send button is live when there is something to say or something attached.
    /// Whitespace alone is nothing — autocomplete and a stray return both leave some behind.
    static func canSend(text: String, hasAttachments: Bool) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasAttachments
    }

    /// Which owner an attachment uploaded from chat belongs to. A real list owns its files;
    /// a virtual channel (My Tasks) has no list, so the file belongs to the channel.
    static func uploadContext(channelId: String, listId: String?) -> [String: String] {
        if let listId, listId != "my-tasks" {
            return ["listId": listId]
        }
        return ["channelId": channelId]
    }
}
