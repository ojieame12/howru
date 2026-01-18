import Foundation
import SwiftData

/// Service for syncing user profile data with the server
@MainActor
@Observable
final class UserSyncService {
    // MARK: - Properties

    private let apiClient: APIClient
    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    var syncError: String?

    // MARK: - Initialization

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    // MARK: - Sync Operations

    /// Fetch user profile from server and merge with local data
    /// - Parameter modelContext: SwiftData context for local operations
    /// - Returns: The synced User object or nil if sync failed
    func fetchUserProfile(modelContext: ModelContext) async -> User? {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return nil
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            let response: UserProfileResponse = try await apiClient.get("/users/me")

            // Find or create local user
            let fetchDescriptor = FetchDescriptor<User>(
                predicate: #Predicate { $0.isChecker == true }
            )
            let existingUsers = try modelContext.fetch(fetchDescriptor)
            let localUser = existingUsers.first

            if let user = localUser {
                // Update existing user with server data
                user.name = response.user.name
                if let email = response.user.email {
                    user.email = email
                }
                if let phone = response.user.phoneNumber {
                    user.phoneNumber = phone
                }
                if let address = response.user.address {
                    user.address = address
                }
                // Note: Profile image URL would need to be downloaded and stored

                // Sync schedule if present
                if let apiSchedule = response.schedule {
                    syncSchedule(apiSchedule, for: user, modelContext: modelContext)
                }

                try modelContext.save()
                lastSyncedAt = Date()
                return user
            } else {
                // Create new local user from server data
                let newUser = User(
                    phoneNumber: response.user.phoneNumber,
                    email: response.user.email,
                    name: response.user.name,
                    isChecker: response.user.isChecker,
                    address: response.user.address
                )
                modelContext.insert(newUser)

                // Sync schedule if present
                if let apiSchedule = response.schedule {
                    syncSchedule(apiSchedule, for: newUser, modelContext: modelContext)
                }

                try modelContext.save()
                lastSyncedAt = Date()
                return newUser
            }
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("Failed to fetch user profile: \(error)")
            }
            syncError = error.localizedDescription
            return nil
        }
    }

    /// Sync local user profile to server after onboarding
    /// - Parameters:
    ///   - user: Local User object to sync
    ///   - schedule: Optional Schedule to sync
    /// - Returns: True if sync was successful
    func syncUserProfile(_ user: User, schedule: Schedule? = nil) async -> Bool {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return false
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            // Update profile
            let profileBody = UpdateProfileBody(
                name: user.name,
                email: user.email,
                profileImageUrl: nil, // Would need to upload image first
                address: user.address
            )

            let _: UserProfileResponse = try await apiClient.patch("/users/me", body: profileBody)

            // Sync schedule if provided
            if let schedule = schedule {
                let scheduleBody = UpdateScheduleBody(
                    windowStartHour: schedule.windowStartHour,
                    windowStartMinute: schedule.windowStartMinute,
                    windowEndHour: schedule.windowEndHour,
                    windowEndMinute: schedule.windowEndMinute,
                    timezone: schedule.timezoneIdentifier,
                    activeDays: schedule.activeDays,
                    gracePeriodMinutes: schedule.gracePeriodMinutes,
                    reminderEnabled: schedule.reminderEnabled,
                    reminderMinutesBefore: schedule.reminderMinutesBefore
                )

                let _: SuccessResponse = try await apiClient.put("/users/me/schedule", body: scheduleBody)
            }

            lastSyncedAt = Date()
            return true
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("Failed to sync user profile: \(error)")
            }
            syncError = error.localizedDescription
            return false
        }
    }

    /// Update user profile on server
    /// - Parameters:
    ///   - name: Optional new name
    ///   - email: Optional new email
    ///   - address: Optional new address
    /// - Returns: True if update was successful
    func updateUserProfile(name: String? = nil, email: String? = nil, address: String? = nil) async -> Bool {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return false
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            let body = UpdateProfileBody(
                name: name,
                email: email,
                profileImageUrl: nil,
                address: address
            )

            let _: UserProfileResponse = try await apiClient.patch("/users/me", body: body)
            lastSyncedAt = Date()
            return true
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("Failed to update user profile: \(error)")
            }
            syncError = error.localizedDescription
            return false
        }
    }

    /// Upload profile image and update user
    /// - Parameter imageData: JPEG image data
    /// - Returns: URL of uploaded image or nil if failed
    func uploadProfileImage(_ imageData: Data) async -> String? {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return nil
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            // Backend expects JSON with base64-encoded image data at /uploads/avatar
            let base64Image = imageData.base64EncodedString()
            let body = UploadAvatarBody(
                imageData: base64Image,
                mimeType: "image/jpeg"
            )

            let response: UploadResponse = try await apiClient.post("/uploads/avatar", body: body)

            // Update profile with new image URL
            let profileBody = UpdateProfileBody(
                name: nil,
                email: nil,
                profileImageUrl: response.url,
                address: nil
            )
            let _: UserProfileResponse = try await apiClient.patch("/users/me", body: profileBody)

            return response.url
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("Failed to upload profile image: \(error)")
            }
            syncError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Private Helpers

    private func syncSchedule(_ apiSchedule: APISchedule, for user: User, modelContext: ModelContext) {
        // Find existing schedule or create new
        let fetchDescriptor = FetchDescriptor<Schedule>(
            predicate: #Predicate<Schedule> { schedule in
                schedule.isActive == true
            }
        )

        do {
            let existingSchedules = try modelContext.fetch(fetchDescriptor)
            let localSchedule = existingSchedules.first { $0.user?.id == user.id }

            if let schedule = localSchedule {
                // Update existing schedule
                schedule.windowStartHour = apiSchedule.windowStartHour
                schedule.windowStartMinute = apiSchedule.windowStartMinute
                schedule.windowEndHour = apiSchedule.windowEndHour
                schedule.windowEndMinute = apiSchedule.windowEndMinute
                schedule.timezoneIdentifier = apiSchedule.timezone
                schedule.activeDays = apiSchedule.activeDays
                schedule.gracePeriodMinutes = apiSchedule.gracePeriodMinutes
                schedule.reminderEnabled = apiSchedule.reminderEnabled
                schedule.reminderMinutesBefore = apiSchedule.reminderMinutesBefore
            } else {
                // Create new schedule
                let newSchedule = Schedule(
                    user: user,
                    windowStartHour: apiSchedule.windowStartHour,
                    windowStartMinute: apiSchedule.windowStartMinute,
                    windowEndHour: apiSchedule.windowEndHour,
                    windowEndMinute: apiSchedule.windowEndMinute,
                    timezoneIdentifier: apiSchedule.timezone,
                    activeDays: apiSchedule.activeDays,
                    gracePeriodMinutes: apiSchedule.gracePeriodMinutes,
                    reminderEnabled: apiSchedule.reminderEnabled,
                    reminderMinutesBefore: apiSchedule.reminderMinutesBefore
                )
                modelContext.insert(newSchedule)
            }
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("Failed to sync schedule: \(error)")
            }
        }
    }
}
