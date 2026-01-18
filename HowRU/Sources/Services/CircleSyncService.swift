import Foundation
import SwiftData

/// Service for syncing circle members (supporters) with the server
@MainActor
@Observable
final class CircleSyncService {
    // MARK: - Properties

    private let apiClient: APIClient
    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    var syncError: String?

    // MARK: - Initialization

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    // MARK: - Fetch Circle

    /// Fetch circle members from server
    /// - Parameter modelContext: SwiftData context
    /// - Returns: Number of members fetched/updated
    func fetchCircle(modelContext: ModelContext) async -> Int {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return 0
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            let response: CircleResponse = try await apiClient.get("/circle")

            // Find the current user (checker)
            let userFetch = FetchDescriptor<User>(
                predicate: #Predicate { $0.isChecker == true }
            )
            let users = try modelContext.fetch(userFetch)
            guard let currentUser = users.first else {
                syncError = "No local user found"
                return 0
            }

            var syncedCount = 0

            for apiMember in response.circle {
                // Check if we already have this member locally
                let existingLinks = try modelContext.fetch(FetchDescriptor<CircleLink>())
                let existingLink = existingLinks.first { $0.syncId == apiMember.id }

                if let link = existingLink {
                    // Update existing link
                    link.supporterName = apiMember.name
                    link.supporterPhone = apiMember.phone
                    link.supporterEmail = apiMember.email
                    link.supporterServerId = apiMember.supporterId  // Store supporter's server user ID
                    link.canSeeMood = apiMember.permissions.canSeeMood
                    link.canSeeLocation = apiMember.permissions.canSeeLocation
                    link.canSeeSelfie = apiMember.permissions.canSeeSelfie
                    link.canPoke = apiMember.permissions.canPoke
                    link.alertViaPush = apiMember.alertPreferences.push
                    link.alertViaSMS = apiMember.alertPreferences.sms
                    link.alertViaEmail = apiMember.alertPreferences.email
                    link.acceptedAt = apiMember.acceptedAt
                    link.syncStatus = .synced
                    link.syncedAt = Date()
                    syncedCount += 1
                } else {
                    // Create new local link from server data
                    let newLink = CircleLink(
                        checker: currentUser,
                        supporterPhone: apiMember.phone,
                        supporterEmail: apiMember.email,
                        supporterName: apiMember.name,
                        canSeeMood: apiMember.permissions.canSeeMood,
                        canSeeLocation: apiMember.permissions.canSeeLocation,
                        canSeeSelfie: apiMember.permissions.canSeeSelfie,
                        canPoke: apiMember.permissions.canPoke,
                        alertViaPush: apiMember.alertPreferences.push,
                        alertViaSMS: apiMember.alertPreferences.sms,
                        alertViaEmail: apiMember.alertPreferences.email,
                        invitedAt: apiMember.invitedAt,
                        acceptedAt: apiMember.acceptedAt,
                        syncId: apiMember.id,
                        supporterServerId: apiMember.supporterId,  // Store supporter's server user ID
                        syncStatus: .synced,
                        syncedAt: Date()
                    )
                    modelContext.insert(newLink)
                    syncedCount += 1
                }
            }

            try modelContext.save()
            lastSyncedAt = Date()

            if AppConfig.shared.isLoggingEnabled {
                print("Synced \(syncedCount) circle members from server")
            }

            return syncedCount
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("Failed to fetch circle: \(error)")
            }
            syncError = error.localizedDescription
            return 0
        }
    }

    // MARK: - Fetch Supporting (people the user supports)

    /// Fetch people the current user supports from server
    /// - Parameter modelContext: SwiftData context
    /// - Returns: Number of supported users fetched/updated
    func fetchSupporting(modelContext: ModelContext) async -> Int {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return 0
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            let response: SupportingResponse = try await apiClient.get("/circle/supporting")

            // Find the current user (as supporter)
            let userFetch = FetchDescriptor<User>(
                predicate: #Predicate { $0.isChecker == true }
            )
            let users = try modelContext.fetch(userFetch)
            guard let currentUser = users.first else {
                syncError = "No local user found"
                return 0
            }

            var syncedCount = 0

            for apiSupported in response.supporting {
                // Check if we already have this link locally
                let existingLinks = try modelContext.fetch(FetchDescriptor<CircleLink>())
                let existingLink = existingLinks.first { $0.syncId == apiSupported.id }

                if let link = existingLink {
                    // Update existing link
                    link.checkerServerId = apiSupported.checkerId  // Store checker's server user ID for pokes
                    link.canSeeMood = apiSupported.permissions.canSeeMood
                    link.canSeeLocation = apiSupported.permissions.canSeeLocation
                    link.canSeeSelfie = apiSupported.permissions.canSeeSelfie
                    link.canPoke = apiSupported.permissions.canPoke
                    link.syncStatus = .synced
                    link.syncedAt = Date()
                    syncedCount += 1
                } else {
                    // Create new local link - we're the supporter watching this checker
                    let newLink = CircleLink(
                        supporter: currentUser,  // Current user is the supporter
                        supporterName: apiSupported.name,
                        canSeeMood: apiSupported.permissions.canSeeMood,
                        canSeeLocation: apiSupported.permissions.canSeeLocation,
                        canSeeSelfie: apiSupported.permissions.canSeeSelfie,
                        canPoke: apiSupported.permissions.canPoke,
                        syncId: apiSupported.id,
                        checkerServerId: apiSupported.checkerId,  // Store checker's server user ID for pokes
                        syncStatus: .synced,
                        syncedAt: Date()
                    )
                    modelContext.insert(newLink)
                    syncedCount += 1
                }
            }

            try modelContext.save()
            lastSyncedAt = Date()

            if AppConfig.shared.isLoggingEnabled {
                print("Synced \(syncedCount) supported users from server")
            }

            return syncedCount
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("Failed to fetch supporting: \(error)")
            }
            syncError = error.localizedDescription
            return 0
        }
    }

    // MARK: - Create Member

    /// Create a new circle member on the server
    /// - Parameters:
    ///   - link: The CircleLink to create
    ///   - modelContext: SwiftData context
    /// - Returns: True if successful
    func createMember(_ link: CircleLink, modelContext: ModelContext) async -> Bool {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return false
        }

        link.syncStatus = .syncing

        do {
            let body = AddCircleMemberBody(
                name: link.supporterName,
                phone: link.supporterPhone,
                email: link.supporterEmail,
                canSeeMood: link.canSeeMood,
                canSeeLocation: link.canSeeLocation,
                canSeeSelfie: link.canSeeSelfie,
                canPoke: link.canPoke,
                alertViaSms: link.alertViaSMS,
                alertViaEmail: link.alertViaEmail
            )

            // Backend returns {member: ...} not {circle: [...]}
            let response: AddCircleMemberResponse = try await apiClient.post("/circle/members", body: body)

            link.syncId = response.member.id
            link.syncStatus = .synced
            link.syncedAt = Date()

            try modelContext.save()

            if AppConfig.shared.isLoggingEnabled {
                print("Circle member created successfully")
            }

            return true
        } catch {
            link.syncStatus = .failed
            try? modelContext.save()

            if AppConfig.shared.isLoggingEnabled {
                print("Failed to create circle member: \(error)")
            }
            syncError = error.localizedDescription
            return false
        }
    }

    // MARK: - Update Member

    /// Update a circle member on the server
    /// - Parameters:
    ///   - link: The CircleLink to update
    ///   - modelContext: SwiftData context
    /// - Returns: True if successful
    func updateMember(_ link: CircleLink, modelContext: ModelContext) async -> Bool {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return false
        }

        guard let syncId = link.syncId else {
            syncError = "Member not synced to server"
            return false
        }

        link.syncStatus = .syncing

        do {
            let body = AddCircleMemberBody(
                name: link.supporterName,
                phone: link.supporterPhone,
                email: link.supporterEmail,
                canSeeMood: link.canSeeMood,
                canSeeLocation: link.canSeeLocation,
                canSeeSelfie: link.canSeeSelfie,
                canPoke: link.canPoke,
                alertViaSms: link.alertViaSMS,
                alertViaEmail: link.alertViaEmail
            )

            let _: SuccessResponse = try await apiClient.patch("/circle/members/\(syncId)", body: body)

            link.syncStatus = .synced
            link.syncedAt = Date()

            try modelContext.save()

            if AppConfig.shared.isLoggingEnabled {
                print("Circle member updated successfully")
            }

            return true
        } catch {
            link.syncStatus = .failed
            try? modelContext.save()

            if AppConfig.shared.isLoggingEnabled {
                print("Failed to update circle member: \(error)")
            }
            syncError = error.localizedDescription
            return false
        }
    }

    // MARK: - Delete Member

    /// Delete a circle member from the server
    /// - Parameters:
    ///   - link: The CircleLink to delete
    ///   - modelContext: SwiftData context
    /// - Returns: True if successful
    func deleteMember(_ link: CircleLink, modelContext: ModelContext) async -> Bool {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return false
        }

        // If not synced to server, just delete locally
        guard let syncId = link.syncId else {
            modelContext.delete(link)
            try? modelContext.save()
            return true
        }

        do {
            try await apiClient.delete("/circle/members/\(syncId)")

            // Delete locally
            modelContext.delete(link)
            try modelContext.save()

            if AppConfig.shared.isLoggingEnabled {
                print("Circle member deleted successfully")
            }

            return true
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("Failed to delete circle member: \(error)")
            }
            syncError = error.localizedDescription
            return false
        }
    }

    // MARK: - Sync Pending

    /// Sync all pending circle members to server
    /// - Parameter modelContext: SwiftData context
    /// - Returns: Number of successfully synced members
    func syncPendingMembers(modelContext: ModelContext) async -> Int {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return 0
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            // Find all links that need syncing
            let fetchDescriptor = FetchDescriptor<CircleLink>(
                predicate: #Predicate<CircleLink> { link in
                    link.syncStatusRaw == "new" ||
                    link.syncStatusRaw == "modified" ||
                    link.syncStatusRaw == "failed"
                }
            )

            let pendingLinks = try modelContext.fetch(fetchDescriptor)

            if AppConfig.shared.isLoggingEnabled {
                print("Found \(pendingLinks.count) pending circle members to sync")
            }

            var successCount = 0

            for link in pendingLinks {
                let success: Bool
                if link.syncId == nil {
                    success = await createMember(link, modelContext: modelContext)
                } else {
                    success = await updateMember(link, modelContext: modelContext)
                }

                if success {
                    successCount += 1
                }
            }

            lastSyncedAt = Date()
            return successCount
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("Failed to fetch pending circle members: \(error)")
            }
            syncError = error.localizedDescription
            return 0
        }
    }
}
