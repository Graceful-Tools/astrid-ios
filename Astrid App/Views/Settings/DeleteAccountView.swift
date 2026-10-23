import SwiftUI

struct DeleteAccountView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject var viewModel: AccountViewModel

    @State private var showFinalConfirmation = false

    var body: some View {
        ZStack {
            Color.clear.themedBackgroundPrimary()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                FloatingTextHeader(NSLocalizedString("settings.account.delete_account", comment: ""), icon: "trash", showBackButton: true)
                    .padding(.top, Theme.spacing8)

                List {
                    // Warning Section
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.title2)
                                Text(NSLocalizedString("settings.account.delete_warning", comment: ""))
                                    .font(Theme.Typography.headline())
                                    .foregroundColor(.red)
                            }

                            Text(NSLocalizedString("settings.account.delete_remove_list_header", comment: ""))
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                            VStack(alignment: .leading, spacing: 8) {
                                bulletPoint(NSLocalizedString("settings.account.delete_remove_tasks", comment: ""))
                                bulletPoint(NSLocalizedString("settings.account.delete_remove_lists", comment: ""))
                                bulletPoint(NSLocalizedString("settings.account.delete_remove_comments", comment: ""))
                                bulletPoint(NSLocalizedString("settings.account.delete_remove_profile", comment: ""))
                                bulletPoint(NSLocalizedString("settings.account.delete_remove_files", comment: ""))
                            }
                            .padding(.leading, 8)
                        }
                        .padding(.vertical, 8)
                    }

                    // Confirmation Section
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(NSLocalizedString("settings.account.delete_confirm_prompt", comment: ""))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                            TextField(NSLocalizedString("settings.account.delete_confirm_placeholder", comment: ""), text: $viewModel.deleteConfirmationText)
                                .autocapitalization(.allCharacters)
                                .disableAutocorrection(true)
                        }
                    } header: {
                        Text(NSLocalizedString("settings.account.delete_confirmation", comment: ""))
                    } footer: {
                        if viewModel.deleteConfirmationText.isEmpty {
                            Text(NSLocalizedString("settings.account.delete_confirm_instruction", comment: ""))
                        } else if viewModel.deleteConfirmationText != NSLocalizedString("settings.account.delete_confirm_phrase", comment: "") {
                            Label(NSLocalizedString("settings.account.delete_confirm_mismatch", comment: ""), systemImage: "xmark.circle")
                                .foregroundColor(.red)
                        } else {
                            Label(NSLocalizedString("settings.account.delete_confirm_match", comment: ""), systemImage: "checkmark.circle")
                                .foregroundColor(.green)
                        }
                    }

                    // Delete Button Section
                    Section {
                        Button(role: .destructive) {
                            showFinalConfirmation = true
                        } label: {
                            HStack {
                                Spacer()
                                if viewModel.isDeleting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text(NSLocalizedString("messages.deleting", comment: ""))
                                } else {
                                    Image(systemName: "trash.fill")
                                    Text(NSLocalizedString("settings.account.delete_my_account_button", comment: ""))
                                }
                                Spacer()
                            }
                        }
                        .disabled(!viewModel.canDeleteAccount || viewModel.isDeleting)
                        .accessibilityIdentifier("account.destructive.deleteMyAccount")
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .navigationBarHidden(true)
        .swipeToDismiss()
        .onDisappear {
            viewModel.resetDeleteFields()
        }
        .alert(NSLocalizedString("messages.error", comment: ""), isPresented: $viewModel.showError) {
            Button(NSLocalizedString("actions.ok", comment: ""), role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert(NSLocalizedString("settings.account.delete_final_confirmation", comment: ""), isPresented: $showFinalConfirmation) {
            Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) { }
            Button(NSLocalizedString("settings.account.delete_forever", comment: ""), role: .destructive) {
                _Concurrency.Task {
                    let success = await viewModel.deleteAccount()
                    if success {
                        // Sign out and dismiss
                        try? await authManager.signOut()
                    }
                }
            }
            .accessibilityIdentifier("account.destructive.deleteForever")
        } message: {
            Text(NSLocalizedString("settings.account.delete_final_warning", comment: ""))
        }
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.red)
            Text(text)
                .font(Theme.Typography.caption1())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
        }
    }
}

#Preview {
    NavigationStack {
        DeleteAccountView(viewModel: AccountViewModel())
            .environmentObject(AuthManager.shared)
    }
}
