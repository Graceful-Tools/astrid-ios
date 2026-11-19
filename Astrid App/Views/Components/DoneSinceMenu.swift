import SwiftUI

/// The Done column's count, as a menu choosing how far back Done goes (ADEV-131): "15 ✓ This week",
/// and on tap the quick picks (Today, This week, This month, This year), Pick a date…, and All time.
/// iOS and Mac alike; each draws the label its own way (`label`), so it sits in its header's style.
struct DoneSinceMenu<Label: View>: View {
    @Binding var since: DoneSince
    let count: Int
    @ViewBuilder let label: (String) -> Label

    @State private var pickingDate = false
    @State private var pickedDay = Date()

    var body: some View {
        let text = DoneSince.headerText(count: count, label: since.label())
        Menu {
            Section(NSLocalizedString("board.done_since.menu_title", comment: "")) {
                ForEach(DoneSince.presets, id: \.self) { preset in
                    choice(preset)
                }
                Button {
                    if case .date(let day) = since { pickedDay = day } else { pickedDay = Date() }
                    pickingDate = true
                } label: {
                    if case .date = since {
                        SwiftUI.Label(since.label(), systemImage: "checkmark")
                    } else {
                        Text(NSLocalizedString("board.done_since.pick_date", comment: ""))
                    }
                }
                choice(.all)
            }
        } label: {
            label(text)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(DoneSince.accessibilityLabel(count: count, label: since.label()))
        .accessibilityIdentifier("board.done.since")
        .popover(isPresented: $pickingDate) {
            DatePicker(NSLocalizedString("board.done_since.pick_date", comment: ""),
                       selection: $pickedDay, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding()
                .frame(minWidth: 300)
                .onChange(of: pickedDay) { _, day in
                    since = .date(day)
                    pickingDate = false
                }
                #if os(iOS)
                .presentationCompactAdaptation(.popover)
                #endif
        }
    }

    private func choice(_ option: DoneSince) -> some View {
        Button {
            since = option
        } label: {
            if option == since {
                SwiftUI.Label(option.label(), systemImage: "checkmark")
            } else {
                Text(option.label())
            }
        }
    }
}
