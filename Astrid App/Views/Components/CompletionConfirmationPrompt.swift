//  CompletionConfirmationPrompt.swift
//  "Complete this task?", drawn in place of a popover's Complete button (ADEV-70).
//
//  Inside the popover rather than as an alert over it: the popover is already on screen and
//  holds the task, and an alert presented while a popover dismisses is one the system drops.
//  Shared by the phone's and the Mac's popovers so the question looks the same on both.

import SwiftUI

struct CompletionConfirmationPrompt: View {
    let assigneeLabel: String?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            Text(CompletionConfirmation.title)
                .fontWeight(.semibold)
            Text(CompletionConfirmation.message(assigneeLabel: assigneeLabel))
                .foregroundStyle(Theme.textMuted)
            HStack {
                Spacer()
                Button(CompletionConfirmation.cancelLabel, action: onCancel)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("completionConfirmation.cancel")
                Button(CompletionConfirmation.confirmLabel, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("completionConfirmation.confirm")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("completionConfirmation")
    }
}
