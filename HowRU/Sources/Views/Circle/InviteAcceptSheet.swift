import SwiftUI
import SwiftData

/// Sheet for accepting a circle invite from a deep link
struct InviteAcceptSheet: View {
    @Bindable var inviteManager: InviteManager

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            ZStack {
                HowRUColors.background(colorScheme)
                    .ignoresSafeArea()

                if showSuccess {
                    successView
                } else if inviteManager.isLoading {
                    loadingView
                } else if let error = inviteManager.error {
                    errorView(error)
                } else if let preview = inviteManager.invitePreview {
                    invitePreviewView(preview)
                } else {
                    loadingView
                }
            }
            .navigationTitle("Circle Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !showSuccess {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            inviteManager.declineInvite()
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: HowRUSpacing.lg) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Loading invite...")
                .font(HowRUFont.body())
                .foregroundColor(HowRUColors.textSecondary(colorScheme))
        }
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: HowRUSpacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(HowRUColors.error(colorScheme).opacity(0.2))
                    .frame(width: 100, height: 100)

                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(HowRUColors.error(colorScheme))
            }

            VStack(spacing: HowRUSpacing.sm) {
                Text("Invite Error")
                    .font(HowRUFont.headline1())
                    .foregroundColor(HowRUColors.textPrimary(colorScheme))

                Text(error)
                    .font(HowRUFont.body())
                    .foregroundColor(HowRUColors.textSecondary(colorScheme))
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button(action: {
                inviteManager.clearPendingInvite()
                dismiss()
            }) {
                Text("Close")
            }
            .buttonStyle(HowRUSecondaryButtonStyle())
            .padding(.horizontal, HowRUSpacing.screenEdge)
            .padding(.bottom, HowRUSpacing.lg)
        }
    }

    // MARK: - Invite Preview View

    private func invitePreviewView(_ preview: InvitePreview) -> some View {
        VStack(spacing: HowRUSpacing.lg) {
            // Inviter header
            VStack(spacing: HowRUSpacing.sm) {
                HowRUAvatar(name: preview.inviterName, size: 80)

                Text(preview.inviterName)
                    .font(HowRUFont.headline1())
                    .foregroundColor(HowRUColors.textPrimary(colorScheme))

                Text("invited you to their circle")
                    .font(HowRUFont.body())
                    .foregroundColor(HowRUColors.textSecondary(colorScheme))
            }
            .padding(.top, HowRUSpacing.xl)

            // Role badge
            HStack(spacing: HowRUSpacing.sm) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 16, weight: .medium))

                Text("As their supporter")
                    .font(HowRUFont.bodyMedium())
            }
            .foregroundColor(HowRUColors.coral)
            .padding(.horizontal, HowRUSpacing.md)
            .padding(.vertical, HowRUSpacing.sm)
            .background(
                Capsule()
                    .fill(HowRUColors.coral.opacity(0.15))
            )

            // Permissions section
            VStack(alignment: .leading, spacing: HowRUSpacing.md) {
                Text("You'll be able to:")
                    .font(HowRUFont.bodyMedium())
                    .foregroundColor(HowRUColors.textPrimary(colorScheme))

                VStack(alignment: .leading, spacing: HowRUSpacing.sm) {
                    permissionRow(
                        icon: "heart.fill",
                        text: "See their mood updates",
                        enabled: preview.permissions.canSeeMood
                    )
                    permissionRow(
                        icon: "camera.fill",
                        text: "See their selfies",
                        enabled: preview.permissions.canSeeSelfie
                    )
                    permissionRow(
                        icon: "hand.tap.fill",
                        text: "Send them pokes",
                        enabled: preview.permissions.canPoke
                    )
                    permissionRow(
                        icon: "location.fill",
                        text: "See their location",
                        enabled: preview.permissions.canSeeLocation
                    )
                }
            }
            .padding(HowRUSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: HowRURadius.lg)
                    .fill(HowRUColors.surface(colorScheme))
                    .shadow(color: HowRUColors.shadow(colorScheme), radius: 4, x: 0, y: 2)
            )
            .padding(.horizontal, HowRUSpacing.screenEdge)

            Spacer()

            // Action buttons
            VStack(spacing: HowRUSpacing.md) {
                Button(action: acceptInvite) {
                    HStack(spacing: HowRUSpacing.sm) {
                        if inviteManager.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .medium))
                        }
                        Text(inviteManager.isLoading ? "Accepting..." : "Accept Invite")
                    }
                }
                .buttonStyle(HowRUPrimaryButtonStyle())
                .disabled(inviteManager.isLoading)

                Button(action: {
                    inviteManager.declineInvite()
                    dismiss()
                }) {
                    Text("Decline")
                }
                .buttonStyle(HowRUSecondaryButtonStyle())
            }
            .padding(.horizontal, HowRUSpacing.screenEdge)
            .padding(.bottom, HowRUSpacing.lg)
        }
    }

    private func permissionRow(icon: String, text: String, enabled: Bool) -> some View {
        HStack(spacing: HowRUSpacing.md) {
            Image(systemName: enabled ? icon : "xmark.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(enabled ? HowRUColors.success(colorScheme) : HowRUColors.textTertiary(colorScheme))
                .frame(width: 24)

            Text(text)
                .font(HowRUFont.body())
                .foregroundColor(enabled ? HowRUColors.textPrimary(colorScheme) : HowRUColors.textTertiary(colorScheme))

            Spacer()
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: HowRUSpacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(HowRUColors.success(colorScheme).opacity(0.2))
                    .frame(width: 120, height: 120)

                Image(systemName: "person.2.circle.fill")
                    .font(.system(size: 64, weight: .medium))
                    .foregroundColor(HowRUColors.success(colorScheme))
            }

            VStack(spacing: HowRUSpacing.sm) {
                Text("You're in the circle!")
                    .font(HowRUFont.headline1())
                    .foregroundColor(HowRUColors.textPrimary(colorScheme))

                if let preview = inviteManager.invitePreview {
                    Text("You'll now receive updates from \(preview.inviterName).")
                        .font(HowRUFont.body())
                        .foregroundColor(HowRUColors.textSecondary(colorScheme))
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()

            Button(action: {
                inviteManager.clearPendingInvite()
                dismiss()
            }) {
                Text("Done")
            }
            .buttonStyle(HowRUPrimaryButtonStyle())
            .padding(.horizontal, HowRUSpacing.screenEdge)
            .padding(.bottom, HowRUSpacing.lg)
        }
    }

    // MARK: - Actions

    private func acceptInvite() {
        HowRUHaptics.light()

        Task {
            let success = await inviteManager.acceptInvite()

            if success {
                HowRUHaptics.success()
                withAnimation(.howruSmooth) {
                    showSuccess = true
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Invite Accept Sheet") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: User.self, CheckIn.self, CircleLink.self, Schedule.self, Poke.self, AlertEvent.self, configurations: config)

    let inviteManager = InviteManager()
    inviteManager.pendingInviteCode = "ABC123"
    inviteManager.invitePreview = InvitePreview(
        code: "ABC123",
        inviterName: "Mom",
        role: "supporter",
        permissions: InvitePermissions(
            canSeeMood: true,
            canSeeLocation: false,
            canSeeSelfie: true,
            canPoke: true
        ),
        expiresAt: nil
    )

    return InviteAcceptSheet(inviteManager: inviteManager)
        .modelContainer(container)
}

#Preview("Invite Accept Sheet - Loading") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: User.self, CheckIn.self, CircleLink.self, Schedule.self, Poke.self, AlertEvent.self, configurations: config)

    let inviteManager = InviteManager()
    inviteManager.isLoading = true

    return InviteAcceptSheet(inviteManager: inviteManager)
        .modelContainer(container)
}

#Preview("Invite Accept Sheet - Error") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: User.self, CheckIn.self, CircleLink.self, Schedule.self, Poke.self, AlertEvent.self, configurations: config)

    let inviteManager = InviteManager()
    inviteManager.error = "This invite link has expired or is invalid."

    return InviteAcceptSheet(inviteManager: inviteManager)
        .modelContainer(container)
}
