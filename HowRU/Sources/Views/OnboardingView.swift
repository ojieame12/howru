import SwiftUI
import SwiftData
import PhotosUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Onboarding Flow
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case userInfo
    case otpVerification
    case accountSetup
    case timeRange
    case contacts
}

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentStep: OnboardingStep = .welcome

    // User data being collected
    @State private var fullName: String = ""
    @State private var emailOrPhone: String = ""
    @State private var isEmailMode: Bool = true
    @State private var country: String = "United States"
    @State private var otpCode: String = ""
    @State private var profileImage: UIImage?
    @State private var address: String = ""
    @State private var startTime: Date = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
    @State private var endTime: Date = Calendar.current.date(from: DateComponents(hour: 21, minute: 0)) ?? Date()
    @State private var selectedContacts: [MockContact] = []
    @State private var sendEmail: Bool = true
    @State private var sendText: Bool = true

    // Auth state
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var isExistingUser: Bool = false
    @State private var serverUserId: String?

    var body: some View {
        ZStack {
            // Animated gradient background for welcome, warm background for other screens
            if currentStep == .welcome {
                AnimatedGradientBackground()
            } else {
                WarmBackground()
            }

            VStack(spacing: 0) {
                // Header with logo and back button
                HStack {
                    if currentStep != .welcome {
                        Button(action: goBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(HowRUColors.textPrimary(colorScheme))
                                .frame(width: 44, height: 44)
                                .background(HowRUColors.surfaceWarm(colorScheme))
                                .cornerRadius(HowRURadius.md)
                                .shadow(color: HowRUColors.shadow(colorScheme), radius: 8, x: 0, y: 2)
                        }
                    } else {
                        Spacer().frame(width: 44)
                    }

                    Spacer()

                    // Logo
                    HowRULogo()

                    Spacer()

                    Spacer().frame(width: 44)
                }
                .padding(.horizontal, HowRUSpacing.screenEdge)
                .padding(.top, HowRUSpacing.md)

                // Content
                Group {
                    switch currentStep {
                    case .welcome:
                        WelcomeScreen(onContinue: { currentStep = .userInfo })
                            .frame(maxWidth: .infinity)
                    case .userInfo:
                        UserInfoScreen(
                            fullName: $fullName,
                            emailOrPhone: $emailOrPhone,
                            isEmailMode: $isEmailMode,
                            country: $country,
                            isLoading: $isLoading,
                            errorMessage: $errorMessage,
                            onContinue: requestOTPAndContinue
                        )
                    case .otpVerification:
                        OTPVerificationScreen(
                            email: emailOrPhone,
                            otpCode: $otpCode,
                            isLoading: $isLoading,
                            errorMessage: $errorMessage,
                            onContinue: verifyOTPAndContinue,
                            onResend: resendOTP
                        )
                    case .accountSetup:
                        AccountSetupScreen(
                            profileImage: $profileImage,
                            address: $address,
                            onContinue: { currentStep = .timeRange }
                        )
                    case .timeRange:
                        TimeRangeScreen(
                            startTime: $startTime,
                            endTime: $endTime,
                            onContinue: { currentStep = .contacts }
                        )
                    case .contacts:
                        ContactsScreen(
                            selectedContacts: $selectedContacts,
                            sendEmail: $sendEmail,
                            sendText: $sendText,
                            onContinue: createUserAndComplete
                        )
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
    }

    private func goBack() {
        if let previousIndex = OnboardingStep.allCases.firstIndex(of: currentStep), previousIndex > 0 {
            currentStep = OnboardingStep.allCases[previousIndex - 1]
        }
    }

    // MARK: - OTP Methods

    private func requestOTPAndContinue() {
        guard !isLoading else { return }
        errorMessage = nil

        // Email mode is not supported by current backend - require phone
        if isEmailMode {
            errorMessage = "Phone number is required. Please switch to phone sign-in."
            return
        }

        Task {
            isLoading = true
            defer { isLoading = false }

            do {
                let countryCode = getCountryCode(for: country)
                _ = try await AuthManager.shared.requestOTP(phone: emailOrPhone, countryCode: countryCode)
                currentStep = .otpVerification
            } catch {
                errorMessage = AuthManager.shared.authError ?? error.localizedDescription
            }
        }
    }

    private func verifyOTPAndContinue() {
        guard !isLoading else { return }
        errorMessage = nil

        Task {
            isLoading = true
            defer { isLoading = false }

            do {
                let countryCode = getCountryCode(for: country)
                let response = try await AuthManager.shared.verifyOTP(
                    phone: emailOrPhone,
                    code: otpCode,
                    name: fullName,
                    countryCode: countryCode
                )

                // Store user info from server
                serverUserId = response.user.id
                isExistingUser = !response.isNewUser

                // Register for push notifications now that user is authenticated
                NotificationService.registerForPushNotifications()

                // If existing user, we could skip onboarding and sync their data
                // For now, just continue to account setup
                if response.isNewUser {
                    currentStep = .accountSetup
                } else {
                    // Existing user - could potentially fetch their profile and skip to main app
                    // For now, still show account setup to let them review
                    currentStep = .accountSetup
                }
            } catch {
                errorMessage = AuthManager.shared.authError ?? error.localizedDescription
            }
        }
    }

    private func resendOTP() {
        guard !isLoading else { return }
        errorMessage = nil

        Task {
            isLoading = true
            defer { isLoading = false }

            do {
                let countryCode = getCountryCode(for: country)
                _ = try await AuthManager.shared.requestOTP(phone: emailOrPhone, countryCode: countryCode)
            } catch {
                errorMessage = AuthManager.shared.authError ?? error.localizedDescription
            }
        }
    }

    private func getCountryCode(for countryName: String) -> String {
        let countryCodes: [String: String] = [
            "United States": "US",
            "United Kingdom": "GB",
            "Canada": "CA",
            "Australia": "AU",
            "Germany": "DE",
            "France": "FR",
            "Spain": "ES",
            "Italy": "IT",
            "Netherlands": "NL",
            "Japan": "JP",
            "South Korea": "KR",
            "India": "IN",
            "Brazil": "BR",
            "Mexico": "MX"
        ]
        return countryCodes[countryName] ?? "US"
    }

    private func createUserAndComplete() {
        let user = User(
            phoneNumber: isEmailMode ? nil : emailOrPhone,
            email: isEmailMode ? emailOrPhone : nil,
            name: fullName,
            isChecker: true,
            profileImageData: profileImage?.jpegData(compressionQuality: 0.8),
            address: address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : address.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(user)

        // Create schedule
        let calendar = Calendar.current
        let schedule = Schedule(
            user: user,
            windowStartHour: calendar.component(.hour, from: startTime),
            windowEndHour: calendar.component(.hour, from: endTime)
        )
        modelContext.insert(schedule)

        // Create supporters from selected contacts
        var createdLinks: [CircleLink] = []
        for contact in selectedContacts {
            let link = CircleLink(
                checker: user,
                supporterPhone: contact.phone,
                supporterName: contact.name
            )
            modelContext.insert(link)
            createdLinks.append(link)
        }

        // Sync to server if authenticated
        if AuthManager.shared.isAuthenticated {
            Task {
                // Sync user profile and schedule to server
                let userSyncService = UserSyncService()
                _ = await userSyncService.syncUserProfile(user, schedule: schedule)

                // Sync circle members to server
                let circleSyncService = CircleSyncService()
                for link in createdLinks {
                    _ = await circleSyncService.createMember(link, modelContext: modelContext)
                }

                // Upload profile image if present
                if let imageData = user.profileImageData {
                    _ = await userSyncService.uploadProfileImage(imageData)
                }
            }
        }
    }
}

// MARK: - Logo Component
struct HowRULogo: View {
    var size: CGFloat = 120

    var body: some View {
        if let _ = UIImage(named: "Logo") {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(height: size * 0.4)
        } else {
            Text("HOWRU")
                .font(.system(size: size * 0.2, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.howruCoral, Color.howruCoralLight],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}

// MARK: - Screen 1: Welcome
struct WelcomeScreen: View {
    let onContinue: () -> Void

    var body: some View {
        VStack {
            Spacer()

            // Headlines
            VStack(spacing: HowRUSpacing.sm) {
                HeadlineText(text: "Checking Up", style: .secondary)
                HeadlineText(text: "Loved Ones", style: .primary)
            }

            Spacer()

            Button("Get Started", action: onContinue)
                .buttonStyle(HowRUPrimaryButtonStyle(isFullWidth: false))
                .padding(.bottom, HowRUSpacing.xxl)
        }
        .padding(.horizontal, HowRUSpacing.screenEdge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Screen 2: User Info
struct UserInfoScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var fullName: String
    @Binding var emailOrPhone: String
    @Binding var isEmailMode: Bool
    @Binding var country: String
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?

    let onContinue: () -> Void

    @FocusState private var focusedField: Field?
    enum Field { case name, emailPhone }

    @State private var showCountryPicker = false

    private let countries = [
        "United States", "United Kingdom", "Canada", "Australia",
        "Germany", "France", "Spain", "Italy", "Netherlands",
        "Japan", "South Korea", "India", "Brazil", "Mexico"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: HowRUSpacing.lg) {
            VStack(alignment: .leading, spacing: HowRUSpacing.xs) {
                HeadlineText(text: "Tell Us About Yourself", style: .title)

                Text("How can we reach you")
                    .font(HowRUFont.body())
                    .foregroundColor(HowRUColors.textSecondary(colorScheme))
            }
            .padding(.top, HowRUSpacing.xl)

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(HowRUFont.caption())
                    .foregroundColor(HowRUColors.error(colorScheme))
                    .padding(.horizontal, HowRUSpacing.md)
                    .padding(.vertical, HowRUSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: HowRURadius.sm)
                            .fill(HowRUColors.error(colorScheme).opacity(0.1))
                    )
            }

            VStack(spacing: HowRUSpacing.md) {
                // Full Name with warm input style
                TextField("Full Name", text: $fullName)
                    .focused($focusedField, equals: .name)
                    .howruTextFieldStyle(isFocused: focusedField == .name)

                // Email/Phone with toggle
                HStack(spacing: 0) {
                    TextField(isEmailMode ? "Email Address" : "Phone Number", text: $emailOrPhone)
                        .font(HowRUFont.body())
                        .keyboardType(isEmailMode ? .emailAddress : .phonePad)
                        .textContentType(isEmailMode ? .emailAddress : .telephoneNumber)
                        .focused($focusedField, equals: .emailPhone)

                    HStack(spacing: HowRUSpacing.xs) {
                        Button(action: { isEmailMode = true }) {
                            Image(systemName: "envelope")
                                .font(.system(size: 16))
                                .foregroundColor(isEmailMode ? HowRUColors.textPrimary(colorScheme) : HowRUColors.textSecondary(colorScheme))
                                .frame(width: 36, height: 36)
                                .background(isEmailMode ? HowRUColors.surfaceWarm(colorScheme) : Color.clear)
                                .cornerRadius(HowRURadius.sm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: HowRURadius.sm)
                                        .stroke(isEmailMode ? Color.howruCoral.opacity(0.3) : Color.clear, lineWidth: 1)
                                )
                        }

                        Button(action: { isEmailMode = false }) {
                            Image(systemName: "phone")
                                .font(.system(size: 16))
                                .foregroundColor(!isEmailMode ? HowRUColors.textPrimary(colorScheme) : HowRUColors.textSecondary(colorScheme))
                                .frame(width: 36, height: 36)
                                .background(!isEmailMode ? HowRUColors.surfaceWarm(colorScheme) : Color.clear)
                                .cornerRadius(HowRURadius.sm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: HowRURadius.sm)
                                        .stroke(!isEmailMode ? Color.howruCoral.opacity(0.3) : Color.clear, lineWidth: 1)
                                )
                        }
                    }
                }
                .howruTextFieldStyle(isFocused: focusedField == .emailPhone)

                // Country picker - tappable
                Button(action: { showCountryPicker = true }) {
                    HStack {
                        Text(country.isEmpty ? "Country" : country)
                            .font(HowRUFont.body())
                            .foregroundColor(country.isEmpty ? HowRUColors.textSecondary(colorScheme) : HowRUColors.textPrimary(colorScheme))

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.system(size: 14))
                            .foregroundColor(HowRUColors.textSecondary(colorScheme))
                    }
                    .howruTextFieldStyle()
                }
            }

            Spacer()

            Button(action: onContinue) {
                HStack(spacing: HowRUSpacing.sm) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isLoading ? "Sending Code..." : "Continue")
                }
            }
            .buttonStyle(HowRUPrimaryButtonStyle())
            .disabled(!canContinue || isLoading)
            .opacity(canContinue && !isLoading ? 1 : 0.6)
            .padding(.bottom, HowRUSpacing.xxl)
        }
        .padding(.horizontal, HowRUSpacing.screenEdge)
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerSheet(selectedCountry: $country, countries: countries)
        }
    }

    private var canContinue: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !emailOrPhone.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - Screen 3: OTP Verification
struct OTPVerificationScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    let email: String
    @Binding var otpCode: String
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    let onContinue: () -> Void
    let onResend: () -> Void

    @FocusState private var focusedField: Int?
    @State private var digits: [String] = ["", "", "", "", "", ""]  // 6 digits for backend
    @State private var resendCountdown: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: HowRUSpacing.lg) {
            VStack(alignment: .leading, spacing: HowRUSpacing.xs) {
                HeadlineText(text: "Enter Code Sent", style: .title)

                HStack(spacing: 4) {
                    Text("We sent a code to")
                        .font(HowRUFont.body())
                        .foregroundColor(HowRUColors.textSecondary(colorScheme))
                    Text(email)
                        .font(HowRUFont.bodyMedium())
                        .foregroundColor(HowRUColors.textPrimary(colorScheme))
                }
            }
            .padding(.top, HowRUSpacing.xl)

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(HowRUFont.caption())
                    .foregroundColor(HowRUColors.error(colorScheme))
                    .padding(.horizontal, HowRUSpacing.md)
                    .padding(.vertical, HowRUSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: HowRURadius.sm)
                            .fill(HowRUColors.error(colorScheme).opacity(0.1))
                    )
            }

            // OTP Input boxes with warm styling (6 digits)
            HStack(spacing: HowRUSpacing.sm) {
                ForEach(0..<6, id: \.self) { index in
                    OTPDigitBox(
                        digit: $digits[index],
                        isFocused: focusedField == index,
                        onTap: { focusedField = index }
                    )
                    .onChange(of: digits[index]) { _, newValue in
                        if newValue.count == 1 && index < 5 {
                            focusedField = index + 1
                        }
                        otpCode = digits.joined()
                    }
                }
            }
            .padding(.top, HowRUSpacing.md)

            // Resend code option
            HStack {
                Spacer()
                if resendCountdown > 0 {
                    Text("Resend code in \(resendCountdown)s")
                        .font(HowRUFont.caption())
                        .foregroundColor(HowRUColors.textSecondary(colorScheme))
                } else {
                    Button(action: {
                        onResend()
                        startResendCountdown()
                    }) {
                        Text("Resend Code")
                            .font(HowRUFont.caption())
                            .foregroundColor(.howruCoral)
                    }
                    .disabled(isLoading)
                }
                Spacer()
            }
            .padding(.top, HowRUSpacing.md)

            Spacer()

            Button(action: onContinue) {
                HStack(spacing: HowRUSpacing.sm) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isLoading ? "Verifying..." : "Continue")
                }
            }
            .buttonStyle(HowRUPrimaryButtonStyle())
            .disabled(otpCode.count < 6 || isLoading)
            .opacity(otpCode.count >= 6 && !isLoading ? 1 : 0.6)
            .padding(.bottom, HowRUSpacing.xxl)
        }
        .padding(.horizontal, HowRUSpacing.screenEdge)
        .onAppear {
            startResendCountdown()
        }
    }

    private func startResendCountdown() {
        resendCountdown = 30
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if resendCountdown > 0 {
                resendCountdown -= 1
            } else {
                timer.invalidate()
            }
        }
    }
}

struct OTPDigitBox: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var digit: String
    let isFocused: Bool
    let onTap: () -> Void

    var body: some View {
        TextField("", text: $digit)
            .font(.system(size: 24, weight: .semibold))
            .foregroundColor(HowRUColors.textPrimary(colorScheme))
            .multilineTextAlignment(.center)
            .keyboardType(.numberPad)
            .frame(width: 64, height: 64)
            .background(
                RoundedRectangle(cornerRadius: HowRURadius.lg)
                    .fill(HowRUColors.surfaceWarm(colorScheme))
                    .shadow(
                        color: isFocused ? Color.howruCoral.opacity(0.15) : HowRUColors.shadow(colorScheme),
                        radius: isFocused ? 12 : 8,
                        x: 0,
                        y: isFocused ? 4 : 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: HowRURadius.lg)
                    .stroke(isFocused ? Color.howruCoral.opacity(0.4) : Color.clear, lineWidth: 1.5)
            )
            .onChange(of: digit) { _, newValue in
                if newValue.count > 1 {
                    digit = String(newValue.suffix(1))
                }
            }
            .onTapGesture(perform: onTap)
    }
}

// MARK: - Screen 4: Account Setup (1/5)
struct AccountSetupScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var profileImage: UIImage?
    @Binding var address: String
    let onContinue: () -> Void

    @FocusState private var isAddressFocused: Bool
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: HowRUSpacing.lg) {
            // Progress indicator
            HowRUProgressIndicator(current: 1, total: 5)
                .padding(.top, HowRUSpacing.lg)

            HeadlineText(text: "Setup Your Account", style: .title)

            // Profile image upload area with warm styling
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                VStack(spacing: HowRUSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(HowRUColors.coralGlow(colorScheme))
                            .frame(width: 100, height: 100)

                        if let image = profileImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                        } else {
                            // Placeholder avatar
                            Image(systemName: "person.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.howruCoralLight)
                        }

                        // Camera badge with soft shadow
                        Circle()
                            .fill(HowRUColors.surfaceWarm(colorScheme))
                            .frame(width: 32, height: 32)
                            .shadow(color: HowRUColors.shadow(colorScheme), radius: 8, x: 0, y: 2)
                            .overlay(
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(HowRUColors.textPrimary(colorScheme))
                            )
                            .offset(x: 35, y: 35)
                    }

                    Text(profileImage == nil ? "Upload your image" : "Change your image")
                        .font(HowRUFont.caption())
                        .foregroundColor(HowRUColors.textSecondary(colorScheme))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, HowRUSpacing.xl)
                .background(
                    RoundedRectangle(cornerRadius: HowRURadius.lg)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [8]))
                        .foregroundColor(HowRUColors.divider(colorScheme))
                )
            }
            .buttonStyle(.plain)
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    await loadPhoto(from: newValue)
                }
            }

            // Address input with warm styling
            TextField("Address", text: $address, axis: .vertical)
                .font(HowRUFont.body())
                .lineLimit(3...5)
                .focused($isAddressFocused)
                .frame(height: 100, alignment: .top)
                .howruTextFieldStyle(isFocused: isAddressFocused)

            Spacer()

            Button("Continue", action: onContinue)
                .buttonStyle(HowRUPrimaryButtonStyle())
                .padding(.bottom, HowRUSpacing.xxl)
        }
        .padding(.horizontal, HowRUSpacing.screenEdge)
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
}

// MARK: - Screen 5: Time Range (2/5)
struct TimeRangeScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var startTime: Date
    @Binding var endTime: Date
    let onContinue: () -> Void

    @State private var showStartPicker = false
    @State private var showEndPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: HowRUSpacing.lg) {
            // Progress indicator
            HowRUProgressIndicator(current: 2, total: 5)
                .padding(.top, HowRUSpacing.lg)

            HeadlineText(text: "Time Range for a checkin?", style: .title)

            VStack(spacing: HowRUSpacing.md) {
                // Start Time with warm styling
                HStack {
                    Text("Start Time")
                        .font(HowRUFont.body())
                        .foregroundColor(HowRUColors.textSecondary(colorScheme))

                    Spacer()

                    Button(action: { showStartPicker.toggle() }) {
                        HStack {
                            Text(formatTime(startTime))
                                .font(HowRUFont.bodyMedium())
                                .foregroundColor(HowRUColors.textPrimary(colorScheme))

                            Image(systemName: "chevron.down")
                                .font(.system(size: 12))
                                .foregroundColor(HowRUColors.textSecondary(colorScheme))
                        }
                    }
                }
                .howruTextFieldStyle()

                // End Time with warm styling
                HStack {
                    Text("End Time")
                        .font(HowRUFont.body())
                        .foregroundColor(HowRUColors.textSecondary(colorScheme))

                    Spacer()

                    Button(action: { showEndPicker.toggle() }) {
                        HStack {
                            Text(formatTime(endTime))
                                .font(HowRUFont.bodyMedium())
                                .foregroundColor(HowRUColors.textPrimary(colorScheme))

                            Image(systemName: "chevron.down")
                                .font(.system(size: 12))
                                .foregroundColor(HowRUColors.textSecondary(colorScheme))
                        }
                    }
                }
                .howruTextFieldStyle()
            }

            Spacer()

            // Time picker (shown when active) with warm background
            if showStartPicker || showEndPicker {
                DatePicker(
                    "",
                    selection: showStartPicker ? $startTime : $endTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .background(
                    RoundedRectangle(cornerRadius: HowRURadius.lg)
                        .fill(HowRUColors.surfaceWarm(colorScheme))
                        .shadow(color: HowRUColors.shadow(colorScheme), radius: 12, x: 0, y: 4)
                )
            }

            Button("Continue", action: onContinue)
                .buttonStyle(HowRUPrimaryButtonStyle())
                .padding(.bottom, HowRUSpacing.xxl)
        }
        .padding(.horizontal, HowRUSpacing.screenEdge)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: date).lowercased()
    }
}

// MARK: - Screen 6: Contacts (3/5)
struct ContactsScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedContacts: [MockContact]
    @Binding var sendEmail: Bool
    @Binding var sendText: Bool
    let onContinue: () -> Void

    @State private var showContactPicker = false
    @State private var searchText = ""

    // Mock contacts for preview
    let mockContacts = [
        MockContact(name: "Dane Twelly", phone: "(307) 555-0133", color: .howruAvatarBlue),
        MockContact(name: "Bessie Cooper", phone: "(302) 555-0107", color: .howruAvatarRose),
        MockContact(name: "Robert Fox", phone: "(704) 555-0127", color: .howruAvatarGreen),
        MockContact(name: "Devon Lane", phone: "(406) 555-0120", color: .howruAvatarPink),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: HowRUSpacing.lg) {
            // Progress indicator
            HowRUProgressIndicator(current: 3, total: 5)
                .padding(.top, HowRUSpacing.lg)

            HeadlineText(text: "Who should we alert if you miss?", style: .title)

            // Import from device card with warm styling
            VStack(alignment: .leading, spacing: HowRUSpacing.md) {
                HStack {
                    Image(systemName: "person.crop.rectangle.stack")
                        .font(.system(size: 20))
                        .foregroundColor(HowRUColors.info(colorScheme))

                    Text("Import from device")
                        .font(HowRUFont.bodyMedium())
                        .foregroundColor(HowRUColors.textPrimary(colorScheme))
                }

                // Selected contacts list
                ForEach(mockContacts, id: \.phone) { contact in
                    ContactRow(
                        contact: contact,
                        isSelected: selectedContacts.contains(where: { $0.phone == contact.phone }),
                        onToggle: {
                            if let index = selectedContacts.firstIndex(where: { $0.phone == contact.phone }) {
                                selectedContacts.remove(at: index)
                            } else {
                                selectedContacts.append(contact)
                            }
                        }
                    )
                }

                // Toggle options with warm backgrounds
                VStack(spacing: HowRUSpacing.sm) {
                    Toggle("Send Email", isOn: $sendEmail)
                        .font(HowRUFont.body())
                        .tint(HowRUColors.success(colorScheme))
                        .padding(HowRUSpacing.md)
                        .background(HowRUColors.backgroundWarm(colorScheme))
                        .cornerRadius(HowRURadius.md)

                    Toggle("Send Text", isOn: $sendText)
                        .font(HowRUFont.body())
                        .tint(HowRUColors.success(colorScheme))
                        .padding(HowRUSpacing.md)
                        .background(HowRUColors.backgroundWarm(colorScheme))
                        .cornerRadius(HowRURadius.md)
                }
            }
            .padding(HowRUSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: HowRURadius.lg)
                    .fill(HowRUColors.surfaceWarm(colorScheme))
                    .shadow(color: HowRUColors.shadow(colorScheme), radius: 12, x: 0, y: 4)
            )

            // Add manually option with warm card style
            Button(action: {}) {
                HStack {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 20))
                        .foregroundColor(HowRUColors.info(colorScheme))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add Manually")
                            .font(HowRUFont.bodyMedium())
                            .foregroundColor(HowRUColors.textPrimary(colorScheme))

                        Text("Enter contact details manually")
                            .font(HowRUFont.caption())
                            .foregroundColor(HowRUColors.textSecondary(colorScheme))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(HowRUColors.textSecondary(colorScheme))
                }
                .padding(HowRUSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: HowRURadius.lg)
                        .fill(HowRUColors.surfaceWarm(colorScheme))
                        .shadow(color: HowRUColors.shadow(colorScheme), radius: 8, x: 0, y: 2)
                )
            }

            Spacer()

            Button("Continue", action: onContinue)
                .buttonStyle(HowRUPrimaryButtonStyle())
                .padding(.bottom, HowRUSpacing.xxl)
        }
        .padding(.horizontal, HowRUSpacing.screenEdge)
    }
}

struct ContactRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let contact: MockContact
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: HowRUSpacing.md) {
                // Radio button
                Circle()
                    .stroke(isSelected ? Color.howruCoral : HowRUColors.divider(colorScheme), lineWidth: 2)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .fill(isSelected ? Color.howruCoral : Color.clear)
                            .frame(width: 12, height: 12)
                    )

                // Contact name and phone
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name)
                        .font(HowRUFont.bodyMedium())
                        .foregroundColor(HowRUColors.textPrimary(colorScheme))

                    Text(contact.phone)
                        .font(HowRUFont.caption())
                        .foregroundColor(HowRUColors.textSecondary(colorScheme))
                }

                Spacer()
            }
            .padding(.vertical, HowRUSpacing.sm)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helper Components
struct HowRUInputField: View {
    let placeholder: String
    @Binding var text: String
    var isFocused: Bool = false

    var body: some View {
        TextField(placeholder, text: $text)
            .howruTextFieldStyle(isFocused: isFocused)
    }
}

struct MockContact: Equatable {
    let name: String
    let phone: String
    let color: Color
}

// MARK: - Country Picker Sheet
struct CountryPickerSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedCountry: String
    let countries: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(countries, id: \.self) { country in
                Button(action: {
                    selectedCountry = country
                    dismiss()
                }) {
                    HStack {
                        Text(country)
                            .font(HowRUFont.body())
                            .foregroundColor(HowRUColors.textPrimary(colorScheme))

                        Spacer()

                        if selectedCountry == country {
                            Image(systemName: "checkmark")
                                .foregroundColor(.howruCoral)
                        }
                    }
                }
            }
            .navigationTitle("Select Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Previews
#Preview("Welcome") {
    ZStack {
        WarmBackground()
        WelcomeScreen(onContinue: {})
    }
}

#Preview("User Info") {
    ZStack {
        WarmBackground()
        UserInfoScreen(
            fullName: .constant(""),
            emailOrPhone: .constant(""),
            isEmailMode: .constant(true),
            country: .constant(""),
            isLoading: .constant(false),
            errorMessage: .constant(nil),
            onContinue: {}
        )
    }
}

#Preview("OTP") {
    ZStack {
        WarmBackground()
        OTPVerificationScreen(
            email: "natefloss@gmail.com",
            otpCode: .constant(""),
            isLoading: .constant(false),
            errorMessage: .constant(nil),
            onContinue: {},
            onResend: {}
        )
    }
}

#Preview("Account Setup") {
    ZStack {
        WarmBackground()
        AccountSetupScreen(
            profileImage: .constant(nil),
            address: .constant(""),
            onContinue: {}
        )
    }
}

#Preview("Time Range") {
    ZStack {
        WarmBackground()
        TimeRangeScreen(
            startTime: .constant(Date()),
            endTime: .constant(Date()),
            onContinue: {}
        )
    }
}

#Preview("Contacts") {
    ZStack {
        WarmBackground()
        ContactsScreen(
            selectedContacts: .constant([]),
            sendEmail: .constant(true),
            sendText: .constant(true),
            onContinue: {}
        )
    }
}

#Preview("Full Onboarding") {
    OnboardingView()
        .modelContainer(for: [User.self, Schedule.self, CircleLink.self], inMemory: true)
}
