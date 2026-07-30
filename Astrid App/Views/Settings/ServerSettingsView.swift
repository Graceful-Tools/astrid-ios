import SwiftUI

/// Server configuration view (DEBUG builds only)
/// Allows developers to switch between localhost, local network, and production servers
#if DEBUG
struct ServerSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @AppStorage("debug_server_url") private var serverURL: String = ""
    @State private var showingRestartAlert = false
    @State private var pendingURL: String?

    var body: some View {
        ZStack {
            // Theme background
            Color.clear.themedBackgroundPrimary()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Floating header
                FloatingTextHeader("Server Configuration", icon: "server.rack", showBackButton: true)
                    .padding(.top, Theme.spacing8)

                // Content
                Form {
                    Section {
                VStack(alignment: .leading, spacing: Theme.spacing8) {
                    Text(NSLocalizedString("debug.current_server", comment: "Current Server"))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                    Text(Constants.API.baseURL)
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                        .padding(Theme.spacing12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colorScheme == .dark ? Theme.Dark.bgTertiary : Theme.bgTertiary)
                        .cornerRadius(Theme.radiusMedium)
                }
            } header: {
                Text(NSLocalizedString("debug.active_config", comment: "Active Configuration"))
            } footer: {
                Text(NSLocalizedString("debug.restart_required", comment: "Changes require app restart to take effect"))
                    .font(Theme.Typography.caption2())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
            }

            Section {
                ForEach(Constants.API.ServerOption.allCases, id: \.rawValue) { option in
                    Button {
                        selectServer(option)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.displayName)
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                Text(option.url)
                                    .font(Theme.Typography.caption2())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            }

                            Spacer()

                            if isCurrentServer(option) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Theme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(NSLocalizedString("debug.available_servers", comment: "Available Servers"))
            }

            Section {
                Button(role: .destructive) {
                    resetToDefault()
                } label: {
                    HStack {
                        Spacer()
                        Text(NSLocalizedString("debug.reset_default", comment: "Reset to Default"))
                        Spacer()
                    }
                }
            }
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .navigationBarHidden(true)
        .swipeToDismiss()
        .alert(NSLocalizedString("server.restart_required", comment: "Restart Required"), isPresented: $showingRestartAlert) {
            Button("OK") {
                // User acknowledges restart is needed
            }
        } message: {
            if let url = pendingURL {
                Text(String(format: NSLocalizedString("server.restart_message", comment: "Server restart message"), url))
            }
        }
    }

    private func isCurrentServer(_ option: Constants.API.ServerOption) -> Bool {
        return Constants.API.baseURL == option.url
    }

    private func selectServer(_ option: Constants.API.ServerOption) {
        guard !isCurrentServer(option) else { return }

        serverURL = option.url
        pendingURL = option.url
        showingRestartAlert = true

        print("🔧 [ServerSettings] Server changed to: \(option.url)")
        print("⚠️ [ServerSettings] App restart required for changes to take effect")
    }

    private func resetToDefault() {
        serverURL = ""
        pendingURL = Constants.API.environment.baseURL
        showingRestartAlert = true

        print("🔧 [ServerSettings] Server reset to default: \(Constants.API.environment.baseURL)")
        print("⚠️ [ServerSettings] App restart required for changes to take effect")
    }
}

#Preview {
    NavigationStack {
        ServerSettingsView()
    }
}
#endif
