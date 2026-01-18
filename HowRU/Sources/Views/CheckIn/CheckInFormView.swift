import SwiftUI

struct CheckInFormView: View {
    @Binding var mentalScore: Int
    @Binding var bodyScore: Int
    @Binding var moodScore: Int

    let isEditing: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showCancelConfirmation = false
    @State private var initialValues: (Int, Int, Int)?

    private var hasChanges: Bool {
        guard let initial = initialValues else { return true }
        return mentalScore != initial.0 || bodyScore != initial.1 || moodScore != initial.2
    }

    var body: some View {
        ZStack {
            HowRUColors.background(colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with back button
                HStack {
                    Button(action: handleCancel) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(HowRUIconButtonStyle())
                    .accessibilityLabel("Go back")
                    .accessibilityHint("Double tap to cancel and return")

                    Spacer()
                }
                .padding(.horizontal, HowRUSpacing.screenEdge)
                .padding(.top, HowRUSpacing.md)

                ScrollView {
                    VStack(spacing: HowRUSpacing.lg) {
                        // Title
                        Text("How are you today?")
                            .font(HowRUFont.headline2())
                            .foregroundColor(HowRUColors.textPrimary(colorScheme))
                            .padding(.top, HowRUSpacing.lg)
                            .accessibilityAddTraits(.isHeader)

                        // Sliders
                        VStack(spacing: HowRUSpacing.md) {
                            CheckInSlider(category: .mind, value: $mentalScore)
                            CheckInSlider(category: .body, value: $bodyScore)
                            CheckInSlider(category: .mood, value: $moodScore)
                        }
                        .padding(.horizontal, HowRUSpacing.screenEdge)

                        Spacer(minLength: HowRUSpacing.xxl)
                    }
                }

                // Submit button
                Button(action: {
                    HowRUHaptics.light()
                    onSubmit()
                }) {
                    Text(isEditing ? "Update" : "Done")
                }
                .buttonStyle(HowRUPrimaryButtonStyle())
                .padding(.horizontal, HowRUSpacing.screenEdge)
                .padding(.bottom, HowRUSpacing.lg)
                .accessibilityLabel(isEditing ? "Update check-in" : "Complete check-in")
                .accessibilityHint("Double tap to save your wellness scores")
            }
        }
        .onAppear {
            // Store initial values for change detection
            if initialValues == nil {
                initialValues = (mentalScore, bodyScore, moodScore)
            }
        }
        .confirmationDialog(
            "Discard changes?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                onCancel()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("You have unsaved changes to your check-in.")
        }
    }

    private func handleCancel() {
        if hasChanges {
            showCancelConfirmation = true
        } else {
            onCancel()
        }
    }
}

// MARK: - Preview

#Preview("New Check-In") {
    @Previewable @State var mental = 3
    @Previewable @State var bodyScore = 3
    @Previewable @State var mood = 3

    CheckInFormView(
        mentalScore: $mental,
        bodyScore: $bodyScore,
        moodScore: $mood,
        isEditing: false,
        onSubmit: { print("Submitted") },
        onCancel: { print("Cancelled") }
    )
}

#Preview("Editing") {
    @Previewable @State var mental = 4
    @Previewable @State var bodyScore = 3
    @Previewable @State var mood = 5

    CheckInFormView(
        mentalScore: $mental,
        bodyScore: $bodyScore,
        moodScore: $mood,
        isEditing: true,
        onSubmit: { print("Updated") },
        onCancel: { print("Cancelled") }
    )
}

#Preview("Dark Mode") {
    @Previewable @State var mental = 3
    @Previewable @State var bodyScore = 3
    @Previewable @State var mood = 3

    CheckInFormView(
        mentalScore: $mental,
        bodyScore: $bodyScore,
        moodScore: $mood,
        isEditing: false,
        onSubmit: { print("Submitted") },
        onCancel: { print("Cancelled") }
    )
    .preferredColorScheme(.dark)
}
