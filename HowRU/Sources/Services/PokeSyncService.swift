import Foundation
import SwiftData

/// Service for syncing pokes with the server
@MainActor
@Observable
final class PokeSyncService {
    // MARK: - Properties

    private let apiClient: APIClient
    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    var syncError: String?

    // MARK: - Initialization

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    // MARK: - Send Poke

    /// Send a poke to a user via the API
    /// - Parameters:
    ///   - toUserId: The server user ID to send the poke to
    ///   - message: Optional message to include
    ///   - poke: Optional local Poke object to update with server response
    ///   - modelContext: SwiftData context
    /// - Returns: True if successful
    func sendPoke(toUserId: String, message: String?, poke: Poke? = nil, modelContext: ModelContext) async -> Bool {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return false
        }

        poke?.syncStatus = .syncing

        do {
            let body = CreatePokeBody(toUserId: toUserId, message: message)
            let response: PokeResponse = try await apiClient.post("/pokes", body: body)

            // Update local poke with server data
            if let poke = poke {
                poke.syncId = response.poke.id
                poke.syncStatus = .synced
                poke.syncedAt = Date()
                try modelContext.save()
            }

            if AppConfig.shared.isLoggingEnabled {
                print("Poke sent successfully: \(response.poke.id)")
            }

            return true
        } catch {
            poke?.syncStatus = .failed
            try? modelContext.save()

            if AppConfig.shared.isLoggingEnabled {
                print("Failed to send poke: \(error)")
            }
            syncError = error.localizedDescription
            return false
        }
    }

    // MARK: - Fetch Pokes

    /// Fetch pokes from server (pokes sent to current user)
    /// - Parameter modelContext: SwiftData context
    /// - Returns: Number of pokes fetched/updated
    func fetchPokes(modelContext: ModelContext) async -> Int {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return 0
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            let response: PokesResponse = try await apiClient.get("/pokes")

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

            for apiPoke in response.pokes {
                // Check if we already have this poke locally
                let existingPokes = try modelContext.fetch(FetchDescriptor<Poke>())
                let existingPoke = existingPokes.first { $0.syncId == apiPoke.id }

                if existingPoke == nil {
                    // Create new local poke from server data
                    let newPoke = Poke(
                        fromSupporterId: UUID(), // We'd need to map server ID to local UUID
                        fromName: apiPoke.fromName ?? "Someone",
                        toCheckerId: currentUser.id,
                        sentAt: apiPoke.sentAt,
                        seenAt: apiPoke.seenAt,
                        respondedAt: apiPoke.respondedAt,
                        message: apiPoke.message,
                        syncId: apiPoke.id,
                        syncStatus: .synced,
                        syncedAt: Date()
                    )
                    modelContext.insert(newPoke)
                    syncedCount += 1
                }
            }

            try modelContext.save()
            lastSyncedAt = Date()

            if AppConfig.shared.isLoggingEnabled {
                print("Synced \(syncedCount) pokes from server")
            }

            return syncedCount
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("Failed to fetch pokes: \(error)")
            }
            syncError = error.localizedDescription
            return 0
        }
    }

    // MARK: - Mark Seen

    /// Mark a poke as seen on the server
    /// - Parameters:
    ///   - poke: The poke to mark as seen
    ///   - modelContext: SwiftData context
    /// - Returns: True if successful
    func markSeen(_ poke: Poke, modelContext: ModelContext) async -> Bool {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return false
        }

        guard let syncId = poke.syncId else {
            // Not synced to server, just update locally
            poke.seenAt = Date()
            try? modelContext.save()
            return true
        }

        do {
            let _: SuccessResponse = try await apiClient.post("/pokes/\(syncId)/seen")

            poke.seenAt = Date()
            try modelContext.save()

            if AppConfig.shared.isLoggingEnabled {
                print("Poke marked as seen: \(syncId)")
            }

            return true
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("Failed to mark poke as seen: \(error)")
            }
            syncError = error.localizedDescription
            return false
        }
    }

    // MARK: - Mark Responded

    /// Mark a poke as responded (user checked in)
    /// - Parameters:
    ///   - poke: The poke to mark as responded
    ///   - modelContext: SwiftData context
    /// - Returns: True if successful
    func markResponded(_ poke: Poke, modelContext: ModelContext) async -> Bool {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return false
        }

        guard let syncId = poke.syncId else {
            // Not synced to server, just update locally
            poke.respondedAt = Date()
            try? modelContext.save()
            return true
        }

        do {
            let _: SuccessResponse = try await apiClient.post("/pokes/\(syncId)/responded")

            poke.respondedAt = Date()
            try modelContext.save()

            if AppConfig.shared.isLoggingEnabled {
                print("Poke marked as responded: \(syncId)")
            }

            return true
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("Failed to mark poke as responded: \(error)")
            }
            syncError = error.localizedDescription
            return false
        }
    }

    // MARK: - Get Unseen Count

    /// Get the count of unseen pokes from server
    /// - Returns: Number of unseen pokes, or nil if failed
    func getUnseenCount() async -> Int? {
        guard AuthManager.shared.isAuthenticated else {
            syncError = "Not authenticated"
            return nil
        }

        do {
            let response: UnseenPokesResponse = try await apiClient.get("/pokes/unseen/count")
            return response.count
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("Failed to get unseen pokes count: \(error)")
            }
            syncError = error.localizedDescription
            return nil
        }
    }
}
