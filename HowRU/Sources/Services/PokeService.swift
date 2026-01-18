import Foundation
import SwiftData

/// Service for managing poke operations
@MainActor
@Observable
final class PokeService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Send Poke

    /// Send a poke from a supporter to a checker
    func sendPoke(
        from supporter: User,
        to checker: User,
        message: String? = nil
    ) -> Poke {
        let poke = Poke(
            fromSupporterId: supporter.id,
            fromName: supporter.name,
            toCheckerId: checker.id,
            message: message
        )

        modelContext.insert(poke)

        // Trigger haptic
        HowRUHaptics.success()

        return poke
    }

    // MARK: - Fetch Pokes

    /// Get all pending (unseen) pokes for a checker
    func pendingPokes(for checkerId: UUID) -> [Poke] {
        let descriptor = FetchDescriptor<Poke>(
            predicate: #Predicate { poke in
                poke.toCheckerId == checkerId && poke.seenAt == nil
            },
            sortBy: [SortDescriptor(\.sentAt, order: .reverse)]
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Get all pokes for a checker (seen and unseen)
    func allPokes(for checkerId: UUID) -> [Poke] {
        let descriptor = FetchDescriptor<Poke>(
            predicate: #Predicate { poke in
                poke.toCheckerId == checkerId
            },
            sortBy: [SortDescriptor(\.sentAt, order: .reverse)]
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Get pokes sent by a supporter
    func pokesSent(by supporterId: UUID) -> [Poke] {
        let descriptor = FetchDescriptor<Poke>(
            predicate: #Predicate { poke in
                poke.fromSupporterId == supporterId
            },
            sortBy: [SortDescriptor(\.sentAt, order: .reverse)]
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Poke Actions

    /// Mark a poke as seen
    func markAsSeen(_ poke: Poke) {
        poke.seenAt = Date()
    }

    /// Mark a poke as responded (checker checked in)
    func markAsResponded(_ poke: Poke) {
        poke.respondedAt = Date()
        if poke.seenAt == nil {
            poke.seenAt = Date()
        }
    }

    /// Mark all pending pokes for a checker as responded
    func markAllAsResponded(for checkerId: UUID) {
        let pendingPokes = pendingPokes(for: checkerId)
        for poke in pendingPokes {
            markAsResponded(poke)
        }
    }

    // MARK: - Poke Statistics

    /// Get poke count for today
    func todaysPokeCount(for checkerId: UUID) -> Int {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())

        let descriptor = FetchDescriptor<Poke>(
            predicate: #Predicate { poke in
                poke.toCheckerId == checkerId && poke.sentAt >= startOfDay
            }
        )

        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    /// Check if checker has been poked today
    func hasBeenPokedToday(checkerId: UUID) -> Bool {
        todaysPokeCount(for: checkerId) > 0
    }

    /// Get the most recent pending poke for a checker
    func mostRecentPendingPoke(for checkerId: UUID) -> Poke? {
        pendingPokes(for: checkerId).first
    }

    // MARK: - Cleanup

    /// Delete old pokes (older than specified days)
    func deleteOldPokes(olderThan days: Int = 30) {
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return }

        let descriptor = FetchDescriptor<Poke>(
            predicate: #Predicate { poke in
                poke.sentAt < cutoffDate
            }
        )

        if let oldPokes = try? modelContext.fetch(descriptor) {
            for poke in oldPokes {
                modelContext.delete(poke)
            }
        }
    }
}

// MARK: - Poke Extensions

extension Poke {
    /// Time since poke was sent, formatted for display
    var timeSinceSent: String {
        let interval = Date().timeIntervalSince(sentAt)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }

    /// Whether the poke was responded to within a reasonable time (e.g., 1 hour)
    var wasQuickResponse: Bool {
        guard let responded = respondedAt else { return false }
        return responded.timeIntervalSince(sentAt) < 3600
    }
}
