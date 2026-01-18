import Foundation

/// Represents the synchronization status of a local record
enum SyncStatus: String, Codable {
    /// Record is new and has not been synced to server
    case new

    /// Record is currently being synced
    case syncing

    /// Record has been synced successfully
    case synced

    /// Record was modified locally after last sync
    case modified

    /// Sync failed - will retry on next sync cycle
    case failed

    /// Whether the record needs to be synced
    var needsSync: Bool {
        switch self {
        case .new, .modified, .failed:
            return true
        case .syncing, .synced:
            return false
        }
    }

    /// Whether the record is currently being synced
    var isInProgress: Bool {
        self == .syncing
    }

    /// Human-readable description of the status
    var displayText: String {
        switch self {
        case .new:
            return "Not synced"
        case .syncing:
            return "Syncing..."
        case .synced:
            return "Synced"
        case .modified:
            return "Modified"
        case .failed:
            return "Sync failed"
        }
    }
}
