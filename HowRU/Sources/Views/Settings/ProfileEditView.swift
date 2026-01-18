import SwiftUI
import SwiftData
import PhotosUI

/// View for editing user profile details including avatar
struct ProfileEditView: View {
    @Bindable var user: User
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var address: String = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profileImage: UIImage?
    @State private var showingDeletePhotoAlert = false

    var body: some View {
        NavigationStack {
            Form {
                // Profile Photo Section
                Section {
                    HStack {
                        Spacer()
                        profileImageView
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                // Photo Actions
                Section {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose Photo", systemImage: "photo.on.rectangle")
                    }

                    if user.profileImageData != nil || profileImage != nil {
                        Button(role: .destructive) {
                            showingDeletePhotoAlert = true
                        } label: {
                            Label("Remove Photo", systemImage: "trash")
                        }
                    }
                }

                // Name & Contact
                Section("Profile") {
                    HStack {
                        Label("Name", systemImage: "person")
                            .foregroundColor(HowRUColors.textSecondary(colorScheme))
                        Spacer()
                        TextField("Your name", text: $name)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(HowRUColors.textPrimary(colorScheme))
                    }

                    HStack {
                        Label("Email", systemImage: "envelope")
                            .foregroundColor(HowRUColors.textSecondary(colorScheme))
                        Spacer()
                        TextField("Email address", text: $email)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .foregroundColor(HowRUColors.textPrimary(colorScheme))
                    }

                    if user.phoneNumber != nil {
                        HStack {
                            Label("Phone", systemImage: "phone")
                                .foregroundColor(HowRUColors.textSecondary(colorScheme))
                            Spacer()
                            Text(user.phoneNumber ?? "")
                                .foregroundColor(HowRUColors.textSecondary(colorScheme))
                        }
                    }
                }

                // Address (optional for emergency contacts)
                Section {
                    HStack {
                        Label("Address", systemImage: "location")
                            .foregroundColor(HowRUColors.textSecondary(colorScheme))
                        Spacer()
                    }
                    TextField("Optional: for emergency contacts", text: $address)
                        .foregroundColor(HowRUColors.textPrimary(colorScheme))
                } footer: {
                    Text("Your address can be shared with supporters in emergencies")
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadCurrentValues()
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    await loadPhoto(from: newValue)
                }
            }
            .alert("Remove Photo?", isPresented: $showingDeletePhotoAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) {
                    removePhoto()
                }
            } message: {
                Text("Your profile photo will be removed.")
            }
        }
    }

    // MARK: - Profile Image View

    @ViewBuilder
    private var profileImageView: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = profileImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if let data = user.profileImageData,
                          let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    // Default avatar
                    Circle()
                        .fill(HowRUGradients.coral)
                        .overlay(
                            Text(String(name.prefix(1)).uppercased())
                                .font(.system(size: 40, weight: .semibold))
                                .foregroundColor(.white)
                        )
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(HowRUColors.divider(colorScheme), lineWidth: 2)
            )

            // Edit badge
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                ZStack {
                    Circle()
                        .fill(HowRUColors.surface(colorScheme))
                        .frame(width: 36, height: 36)
                        .shadow(color: HowRUColors.shadow(colorScheme), radius: 4, y: 2)

                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(HowRUColors.textPrimary(colorScheme))
                }
            }
        }
        .padding(.vertical, HowRUSpacing.md)
    }

    // MARK: - Actions

    private func loadCurrentValues() {
        name = user.name
        email = user.email ?? ""
        address = user.address ?? ""
    }

    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item = item else { return }

        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                await MainActor.run {
                    profileImage = uiImage
                }
            }
        } catch {
            print("Failed to load photo: \(error)")
        }
    }

    private func removePhoto() {
        profileImage = nil
        user.profileImageData = nil
    }

    private func saveChanges() {
        user.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        user.email = email.isEmpty ? nil : email.trimmingCharacters(in: .whitespacesAndNewlines)
        user.address = address.isEmpty ? nil : address.trimmingCharacters(in: .whitespacesAndNewlines)

        // Save profile image
        if let image = profileImage {
            user.profileImageData = image.jpegData(compressionQuality: 0.8)
        }

        HowRUHaptics.success()
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var previewUser = User(phoneNumber: "+1234567890", email: "test@example.com", name: "Test User")
    ProfileEditView(user: previewUser)
}
