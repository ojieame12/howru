import Foundation
import SwiftData
import UIKit

/// Service for managing snapshot storage, compression, and cleanup
@MainActor
@Observable
final class SnapshotService {
    private let modelContext: ModelContext

    // Compression settings
    private let maxImageDimension: CGFloat = 1024
    private let jpegQuality: CGFloat = 0.7

    // Expiry duration (24 hours)
    static let expiryDuration: TimeInterval = 24 * 60 * 60

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Save Snapshot

    /// Process and save a snapshot to a check-in
    func saveSnapshot(imageData: Data, to checkIn: CheckIn) -> Bool {
        guard let processedData = processImage(imageData) else {
            return false
        }

        checkIn.selfieData = processedData
        checkIn.selfieExpiresAt = Date().addingTimeInterval(Self.expiryDuration)

        return true
    }

    /// Process raw image data: resize and compress
    private func processImage(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        // Resize if necessary
        let resizedImage = resizeImage(image, maxDimension: maxImageDimension)

        // Compress to JPEG
        return resizedImage.jpegData(compressionQuality: jpegQuality)
    }

    /// Resize image maintaining aspect ratio
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size

        // Check if resize is needed
        guard size.width > maxDimension || size.height > maxDimension else {
            return image
        }

        // Calculate new size
        let aspectRatio = size.width / size.height
        let newSize: CGSize

        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        // Render at new size
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Delete Snapshot

    /// Remove snapshot from a check-in
    func deleteSnapshot(from checkIn: CheckIn) {
        checkIn.selfieData = nil
        checkIn.selfieExpiresAt = nil
    }

    // MARK: - Cleanup Expired

    /// Clean up all expired snapshots
    func cleanupExpiredSnapshots() {
        let now = Date()

        let descriptor = FetchDescriptor<CheckIn>(
            predicate: #Predicate { checkIn in
                checkIn.selfieData != nil
            }
        )

        guard let checkIns = try? modelContext.fetch(descriptor) else { return }

        var cleanedCount = 0
        for checkIn in checkIns {
            if let expiresAt = checkIn.selfieExpiresAt, expiresAt < now {
                checkIn.selfieData = nil
                checkIn.selfieExpiresAt = nil
                cleanedCount += 1
            }
        }

        if cleanedCount > 0 {
            print("Cleaned up \(cleanedCount) expired snapshot(s)")
        }
    }

    // MARK: - Helpers

    /// Check if a check-in has a valid (non-expired) snapshot
    func hasValidSnapshot(_ checkIn: CheckIn) -> Bool {
        guard let data = checkIn.selfieData,
              let expiresAt = checkIn.selfieExpiresAt else {
            return false
        }

        return !data.isEmpty && expiresAt > Date()
    }

    /// Get remaining time until snapshot expires
    func timeUntilExpiry(_ checkIn: CheckIn) -> TimeInterval? {
        guard let expiresAt = checkIn.selfieExpiresAt else { return nil }
        let remaining = expiresAt.timeIntervalSince(Date())
        return remaining > 0 ? remaining : nil
    }

    /// Format expiry time for display
    func formattedExpiryTime(_ checkIn: CheckIn) -> String? {
        guard let remaining = timeUntilExpiry(checkIn) else { return nil }

        let hours = Int(remaining / 3600)
        if hours > 0 {
            return "\(hours)h remaining"
        } else {
            let minutes = max(1, Int(remaining / 60))
            return "\(minutes)m remaining"
        }
    }

    // MARK: - Statistics

    /// Get total size of all stored snapshots
    func totalSnapshotStorageSize() -> Int {
        let descriptor = FetchDescriptor<CheckIn>(
            predicate: #Predicate { checkIn in
                checkIn.selfieData != nil
            }
        )

        guard let checkIns = try? modelContext.fetch(descriptor) else { return 0 }

        return checkIns.compactMap { $0.selfieData?.count }.reduce(0, +)
    }

    /// Format storage size for display
    func formattedStorageSize() -> String {
        let bytes = totalSnapshotStorageSize()

        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            let kb = Double(bytes) / 1024
            return String(format: "%.1f KB", kb)
        } else {
            let mb = Double(bytes) / (1024 * 1024)
            return String(format: "%.1f MB", mb)
        }
    }
}

// MARK: - CheckIn Extensions for Snapshots

extension CheckIn {
    /// Formatted expiry text for display
    var selfieExpiryText: String? {
        guard let expires = selfieExpiresAt, expires > Date() else { return nil }

        let remaining = expires.timeIntervalSince(Date())
        let hours = Int(remaining / 3600)

        if hours > 0 {
            return "Expires in \(hours)h"
        } else {
            let minutes = max(1, Int(remaining / 60))
            return "Expires in \(minutes)m"
        }
    }

    /// Check if selfie is about to expire (less than 1 hour)
    var selfieExpiringsSoon: Bool {
        guard let expires = selfieExpiresAt else { return false }
        let remaining = expires.timeIntervalSince(Date())
        return remaining > 0 && remaining < 3600
    }
}
