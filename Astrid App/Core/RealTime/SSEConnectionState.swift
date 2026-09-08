//  SSEConnectionState.swift
//  Whether the live-update stream is actually delivering — observable from SwiftUI.
//
//  `SSEClient` is an actor and its `isConnected` is private, so no view could ask. That is why
//  the chat panel's "SSE backup" poll ran unconditionally: 20 full message fetches a minute, for
//  as long as a list's chat was on screen, alongside a stream delivering the same events.
//
//  This tracks something stricter than `isConnected`, deliberately. `connect()` sets that flag
//  optimistically before the stream is established, so a view that trusted it would drop its
//  fallback at exactly the moment the connection was failing — which is the one moment the
//  fallback exists for.
import Combine
import Foundation

@MainActor
final class SSEConnectionState: ObservableObject {
    static let shared = SSEConnectionState()

    /// Starts false: until the stream has proven itself, callers should assume they are on their own.
    @Published private(set) var isStreamLive = false

    /// Bytes are arriving — the `✅ Connected and streaming` transition, not `connect()`.
    func streamDidBecomeLive() {
        isStreamLive = true
    }

    /// The stream ended, errored, or was disconnected on purpose.
    func streamDidStop() {
        isStreamLive = false
    }
}
