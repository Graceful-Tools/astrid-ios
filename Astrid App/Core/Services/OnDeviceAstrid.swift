//  OnDeviceAstrid.swift
//  When Astrid should answer ON DEVICE (Apple Intelligence), and how — shared by iOS and Mac.
//
//  This lived inline in iOS's ChatInputView, so the Mac chat never triggered it: with Apple
//  Foundation Models chosen as the default agent, @mentioning Astrid on Mac did nothing at all
//  (task 8dded037). The decision and the mention-stripping are pure here so both platforms answer
//  identically, and so the rules are testable without a model on the machine.
import Foundation
import os.log

private let logger = Logger(subsystem: Brand.logSubsystem, category: "OnDeviceAstrid")

enum OnDeviceAstrid {

    /// Who answers this message (task 9dce4c73).
    ///
    /// The point of having three cases rather than a Bool: "we will not answer" and "there is
    /// nothing to answer" are different situations that used to share one `return`, so a user
    /// with a server-side agent selected got silence and the code looked correct.
    enum Responder: Equatable {
        /// Apple Intelligence answers here — private, fast, and the reason it exists.
        case onDevice
        /// Addressed to Astrid, but this device cannot answer. The server is asked instead.
        case server
        /// Not addressed to her. Answering would be barging into someone else's conversation.
        case nobody
    }

    /// Is this message Astrid's to answer at all, regardless of who ends up answering it?
    ///
    /// An @mention, or any message in a personal channel — there she is the only other
    /// participant, so everything said is said to her.
    static func isAddressed(content: String, listId: String?) -> Bool {
        let mentionsAstrid = content.contains("@[Astrid]") || content.contains("@[astrid]")
        let isPersonalChannel = listId == nil || listId == "my-tasks"
        return mentionsAstrid || isPersonalChannel
    }

    /// Route the message. On-device is preferred whenever it can run; the server is the
    /// fallback, never the first choice.
    static func responder(isOnDeviceModel: Bool, isAvailable: Bool,
                          content: String, listId: String?) -> Responder {
        guard isAddressed(content: content, listId: listId) else { return .nobody }
        return (isOnDeviceModel && isAvailable) ? .onDevice : .server
    }

    /// Should this message be answered by the on-device model?
    ///
    /// Mirrors iOS: only when the on-device model is the selected agent AND available, and only
    /// for a message that is actually addressed to Astrid — an @mention, or any message in a
    /// personal channel (where she is the only other participant).
    static func shouldRespond(isOnDeviceModel: Bool, isAvailable: Bool,
                              content: String, listId: String?) -> Bool {
        responder(isOnDeviceModel: isOnDeviceModel, isAvailable: isAvailable,
                  content: content, listId: listId) == .onDevice
    }

    /// The message with mention markup removed — the model should read what a person would, not
    /// "@[Astrid](user-123)".
    static func plainMessage(from content: String) -> String {
        content
            .replacingOccurrences(of: "@\\[[^\\]]+\\]\\([^)]+\\)", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Full flow: decide, generate on device, and post the reply through ChatService (the canonical
    /// entry point for anything that writes to a channel). Silent when it does not apply.
    @MainActor
    static func respondIfNeeded(channelId: String, content: String, listId: String?,
                                messageId: String? = nil) async {
        // A failed settings fetch is not "she is not selected" — we simply do not know, and the
        // server does, so let it decide rather than going quiet on a network blip.
        let isOnDeviceModel = (try? await ChatService.shared.getAIAssistantSettings())?.isOnDeviceModel ?? false

        switch responder(isOnDeviceModel: isOnDeviceModel,
                         isAvailable: AppleFoundationModelService.shared.isAvailable,
                         content: content, listId: listId) {
        case .nobody:
            return
        case .server:
            await handOffToServer(channelId: channelId, content: content, messageId: messageId)
            return
        case .onDevice:
            break
        }

        let plain = plainMessage(from: content)
        guard !plain.isEmpty else { return }

        guard let response = await AppleFoundationModelService.shared.processChatMessage(plain) else {
            logger.error("On-device processing returned no response")
            return
        }
        do {
            try await ChatService.shared.postAgentResponse(channelId: channelId, content: response)
            logger.notice("On-device response posted to channel")
        } catch {
            logger.error("Failed to post on-device response: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Ask the server to answer as Astrid, because this device cannot.
    ///
    /// Failure is deliberately quiet. Until the server ships its half (web task f0700542) this
    /// call 404s, and the user sees exactly the silence they already saw — so the client half is
    /// safe to ship first, and starts working on its own once the server deploys.
    @MainActor
    private static func handOffToServer(channelId: String, content: String, messageId: String?) async {
        let plain = plainMessage(from: content)
        guard !plain.isEmpty else { return }
        do {
            try await ChatService.shared.requestServerAstridResponse(
                channelId: channelId, messageId: messageId, content: plain)
            logger.notice("Astrid handed off to the server")
        } catch {
            logger.info("Server Astrid handoff unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }
}
