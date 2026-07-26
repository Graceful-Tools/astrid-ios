//  OnDeviceAstrid.swift
//  When Astrid should answer ON DEVICE (Apple Intelligence), and how — shared by iOS and Mac.
//
//  This lived inline in iOS's ChatInputView, so the Mac chat never triggered it: with Apple
//  Foundation Models chosen as the default agent, @mentioning Astrid on Mac did nothing at all
//  (task 8dded037). The decision and the mention-stripping are pure here so both platforms answer
//  identically, and so the rules are testable without a model on the machine.
import Foundation
import os.log

private let logger = Logger(subsystem: "com.graceful-tools.astrid", category: "OnDeviceAstrid")

enum OnDeviceAstrid {

    /// Should this message be answered by the on-device model?
    ///
    /// Mirrors iOS: only when the on-device model is the selected agent AND available, and only
    /// for a message that is actually addressed to Astrid — an @mention, or any message in a
    /// personal channel (where she is the only other participant).
    static func shouldRespond(isOnDeviceModel: Bool, isAvailable: Bool,
                              content: String, listId: String?) -> Bool {
        guard isOnDeviceModel, isAvailable else { return false }
        let mentionsAstrid = content.contains("@[Astrid]") || content.contains("@[astrid]")
        let isPersonalChannel = listId == nil || listId == "my-tasks"
        return mentionsAstrid || isPersonalChannel
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
    static func respondIfNeeded(channelId: String, content: String, listId: String?) async {
        guard let settings = try? await ChatService.shared.getAIAssistantSettings(),
              settings.isOnDeviceModel else { return }
        guard shouldRespond(isOnDeviceModel: true,
                            isAvailable: AppleFoundationModelService.shared.isAvailable,
                            content: content, listId: listId) else { return }

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
}
