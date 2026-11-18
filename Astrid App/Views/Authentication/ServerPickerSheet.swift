#if os(iOS)
import SwiftUI

/// The sign-in screen's "Use a different server" sheet (ADEV-118).
struct ServerPickerSheet: View {
    @ThemedPalette private var palette
    @StateObject private var model = ServerPickerModel()
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing16) {
            Text(NSLocalizedString("server.picker_title", comment: ""))
                .font(Theme.Typography.headline())
                .foregroundColor(palette.textPrimary)

            Text(NSLocalizedString("server.picker_message", comment: ""))
                .font(Theme.Typography.caption1())
                .foregroundColor(palette.textSecondary)

            TextField(NSLocalizedString("server.address_placeholder", comment: ""), text: $model.address)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .submitLabel(.go)
                .onSubmit(connect)
                .padding(Theme.spacing12)
                .background(palette.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .accessibilityIdentifier("server.address")

            if let error = model.errorMessage {
                Text(error)
                    .font(Theme.Typography.caption1())
                    .foregroundColor(palette.errorInk)
                    .accessibilityIdentifier("server.error")
            }

            HStack(spacing: Theme.spacing12) {
                Button(NSLocalizedString("actions.cancel", comment: ""), action: onDone)
                    .buttonStyle(.bordered)
                Spacer()
                if model.isChecking { ProgressView() }
                Button(NSLocalizedString("server.connect", comment: ""), action: connect)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canConnect)
                    .accessibilityIdentifier("server.connect")
            }
        }
        .padding(Theme.spacing24)
        .background(palette.bgPrimary)
    }

    private func connect() {
        _Concurrency.Task {
            if await model.connect() { onDone() }
        }
    }
}
#endif
