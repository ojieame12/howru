import SwiftUI
import SwiftData

/// Sheet for supporters to send a poke with optional message
struct PokeComposerSheet: View {
    let circleLink: CircleLink

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var message = ""
    @State private var isSending = false
    @State private var showSuccess = false
    @State private var pokeSyncService = PokeSyncService()

    private let quickMessages = [
        "Just checking in on you",
        "Thinking of you",
        "Hope you're doing well",
        "Miss you"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                HowRUColors.background(colorScheme)
                    .ignoresSafeArea()

                if showSuccess {
                    successView
                } else {
                    composerView
                }
            }
            .navigationTitle("Send a Poke")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !showSuccess {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Composer View

    private var composerView: some View {
        VStack(spacing: HowRUSpacing.lg) {
            // Recipient header
            VStack(spacing: HowRUSpacing.sm) {
                HowRUAvatar(name: circleLink.checker?.name ?? "Unknown", size: 64)

                Text("Poke \(circleLink.checker?.name ?? "them")")
                    .font(HowRUFont.headline2())
                    .foregroundColor(HowRUColors.textPrimary(colorScheme))

                Text("A gentle reminder to check in")
                    .font(HowRUFont.body())
                    .foregroundColor(HowRUColors.textSecondary(colorScheme))
            }
            .padding(.top, HowRUSpacing.lg)

            // Quick message pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HowRUSpacing.sm) {
                    ForEach(quickMessages, id: \.self) { quickMessage in
                        Button(action: {
                            HowRUHaptics.light()
                            message = quickMessage
                        }) {
                            Text(quickMessage)
                                .font(HowRUFont.caption())
                                .foregroundColor(message == quickMessage ? .white : HowRUColors.textPrimary(colorScheme))
                                .padding(.horizontal, HowRUSpacing.md)
                                .padding(.vertical, HowRUSpacing.sm)
                                .background(
                                    Capsule()
                                        .fill(message == quickMessage ? HowRUColors.coral : HowRUColors.surface(colorScheme))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, HowRUSpacing.screenEdge)
            }

            // Message input
            VStack(alignment: .leading, spacing: HowRUSpacing.sm) {
                Text("Add a message (optional)")
                    .font(HowRUFont.caption())
                    .foregroundColor(HowRUColors.textSecondary(colorScheme))

                TextField("Type a message...", text: $message, axis: .vertical)
                    .font(HowRUFont.body())
                    .lineLimit(3...5)
                    .padding(HowRUSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: HowRURadius.md)
                            .fill(HowRUColors.surface(colorScheme))
                            .shadow(color: HowRUColors.shadow(colorScheme), radius: 4, x: 0, y: 2)
                    )
            }
            .padding(.horizontal, HowRUSpacing.screenEdge)

            Spacer()

            // Send button
            Button(action: sendPoke) {
                HStack(spacing: HowRUSpacing.sm) {
                    if isSending {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 18, weight: .medium))
                    }
                    Text(isSending ? "Sending..." : "Send Poke")
                }
            }
            .buttonStyle(HowRUPrimaryButtonStyle())
            .disabled(isSending)
            .padding(.horizontal, HowRUSpacing.screenEdge)
            .padding(.bottom, HowRUSpacing.lg)
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: HowRUSpacing.xl) {
            Spacer()

            // Success animation
            ZStack {
                Circle()
                    .fill(HowRUColors.success(colorScheme).opacity(0.2))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64, weight: .medium))
                    .foregroundColor(HowRUColors.success(colorScheme))
            }

            VStack(spacing: HowRUSpacing.sm) {
                Text("Poke sent!")
                    .font(HowRUFont.headline1())
                    .foregroundColor(HowRUColors.textPrimary(colorScheme))

                Text("\(circleLink.checker?.name ?? "They") will get a gentle reminder to check in.")
                    .font(HowRUFont.body())
                    .foregroundColor(HowRUColors.textSecondary(colorScheme))
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button(action: {
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

    private func sendPoke() {
        guard let supporter = circleLink.supporter,
              let checkerId = circleLink.checker?.id else { return }

        isSending = true
        HowRUHaptics.light()

        // Create the poke locally
        let poke = Poke(
            fromSupporterId: supporter.id,
            fromName: supporter.name,
            toCheckerId: checkerId,
            message: message.isEmpty ? nil : message,
            syncStatus: .new
        )

        modelContext.insert(poke)

        // Sync to server if authenticated
        if AuthManager.shared.isAuthenticated {
            // Use checkerServerId for pokes - this is the checker's actual server user ID
            guard let serverUserId = circleLink.checkerServerId else {
                // Fallback: if we don't have the server ID, poke locally only
                isSending = false
                HowRUHaptics.success()
                withAnimation(.howruSmooth) {
                    showSuccess = true
                }
                return
            }

            Task {
                let success = await pokeSyncService.sendPoke(
                    toUserId: serverUserId,
                    message: message.isEmpty ? nil : message,
                    poke: poke,
                    modelContext: modelContext
                )

                isSending = false
                if success {
                    HowRUHaptics.success()
                } else {
                    HowRUHaptics.light()
                }

                withAnimation(.howruSmooth) {
                    showSuccess = true
                }
            }
        } else {
            // Local only mode
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isSending = false
                HowRUHaptics.success()

                withAnimation(.howruSmooth) {
                    showSuccess = true
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Poke Composer") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: User.self, CheckIn.self, CircleLink.self, Schedule.self, Poke.self, AlertEvent.self, configurations: config)

    let checker = User(phoneNumber: "+1234567890", name: "Grandma Betty")
    let supporter = User(phoneNumber: "+0987654321", name: "Sarah")
    container.mainContext.insert(checker)
    container.mainContext.insert(supporter)

    let link = CircleLink(
        checker: checker,
        supporter: supporter,
        supporterName: "Sarah"
    )
    container.mainContext.insert(link)

    return PokeComposerSheet(circleLink: link)
        .modelContainer(container)
}

#Preview("Poke Composer - Dark") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: User.self, CheckIn.self, CircleLink.self, Schedule.self, Poke.self, AlertEvent.self, configurations: config)

    let checker = User(phoneNumber: "+1234567890", name: "Grandpa Joe")
    let supporter = User(phoneNumber: "+0987654321", name: "Mike")
    container.mainContext.insert(checker)
    container.mainContext.insert(supporter)

    let link = CircleLink(
        checker: checker,
        supporter: supporter,
        supporterName: "Mike"
    )
    container.mainContext.insert(link)

    return PokeComposerSheet(circleLink: link)
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
