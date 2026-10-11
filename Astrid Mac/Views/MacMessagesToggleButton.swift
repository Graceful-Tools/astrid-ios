//
//  MacMessagesToggleButton.swift
//  Astrid Mac
//
//  The toolbar's messages toggle (AITD-485): hides and shows the chat column, the mirror image
//  of the sidebar toggle at the window's other corner. Whether it is OFFERED is the caller's
//  call (`MacLayout.showsChatColumn` asked without `hiddenByUser`) — it only appears where the
//  column would otherwise be, so it never does nothing.
//

import SwiftUI

struct MacMessagesToggleButton: View {
    @Binding var isHidden: Bool

    var body: some View {
        let title = NSLocalizedString(isHidden ? "chat.show_messages" : "chat.hide_messages", comment: "")
        Button { withAnimation(MacMotion.medium) { isHidden.toggle() } } label: {
            Label(title, systemImage: "sidebar.right")
        }
        .help(title)
        .accessibilityIdentifier("messages.togglePane")
    }
}
