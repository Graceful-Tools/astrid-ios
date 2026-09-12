import SwiftUI

/// "A new Astrid is ready" — the update CTA, in the style of a reminder (AITD-383).
///
/// ONE FILE FOR BOTH PLATFORMS. It lives in `Views/Components/`, which the Mac target compiles
/// unless a file is explicitly excluded, so iOS and Mac cannot end up describing the same update
/// two different ways. That is also why there is no UIKit in here.
///
/// IT IS STYLED LIKE A REMINDER, NOT SCHEDULED LIKE ONE. Jon asked for "an 'Update' CTA in the
/// style of a reminder"; the card borrows `ReminderView`'s shape — dimmed ground, one card, one
/// clear action — but nothing is queued, no notification is posted and no task is involved. It
/// appears when the app notices a newer version and goes away when it is answered.
struct AppUpdateReminderCard: View {
    let update: AppUpdateService.AvailableUpdate
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            // The dimmed ground is what makes this read as a reminder rather than a banner.
            // Tapping it is "not now" — the same answer as the button, because a card you cannot
            // get out of by tapping away is a trap.
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: Theme.spacing16) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(Theme.accent)

                Text(NSLocalizedString("update.available_title", comment: ""))
                    .font(Theme.Typography.title3())
                    .foregroundColor(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(String(format: NSLocalizedString("update.available_body", comment: ""),
                            update.version))
                    .font(Theme.Typography.body())
                    .foregroundColor(Theme.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // Only when the server actually sent notes — an empty box is worse than none.
                if let notes = update.releaseNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ScrollView {
                        Text(notes)
                            .font(Theme.Typography.caption1())
                            .foregroundColor(Theme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                }

                VStack(spacing: Theme.spacing8) {
                    Button {
                        openURL(update.updateURL)
                        onUpdate()
                    } label: {
                        Text(NSLocalizedString("update.action", comment: ""))
                            .font(Theme.Typography.headline())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: onDismiss) {
                        Text(NSLocalizedString("update.later", comment: ""))
                            .font(Theme.Typography.body())
                            .foregroundColor(Theme.textMuted)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.spacing24)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.bgPrimary)
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            )
            .padding(Theme.spacing24)
        }
    }
}

/// Show the card whenever the service has something to say.
///
/// A modifier rather than a view each root has to assemble, so adding it to a new surface cannot
/// accidentally wire up a different set of buttons.
struct AppUpdateReminderModifier: ViewModifier {
    @ObservedObject private var service = AppUpdateService.shared

    func body(content: Content) -> some View {
        content
            .overlay {
                if let update = service.availableUpdate {
                    AppUpdateReminderCard(
                        update: update,
                        onUpdate: { service.acknowledgeUpdateOpened() },
                        onDismiss: { service.dismiss() }
                    )
                    .transition(.opacity)
                }
            }
            .task { await service.checkForUpdate() }
    }
}

extension View {
    /// Offer the update card on this surface (AITD-383).
    func appUpdateReminder() -> some View { modifier(AppUpdateReminderModifier()) }
}
