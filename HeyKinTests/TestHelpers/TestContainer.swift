import Foundation
import SwiftData
@testable import HowRU

/// In-memory SwiftData container for testing
@MainActor
final class TestContainer {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        let schema = Schema([
            User.self,
            CheckIn.self,
            Schedule.self,
            CircleLink.self,
            AlertEvent.self,
            Poke.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        container = try ModelContainer(for: schema, configurations: [configuration])
        context = container.mainContext
    }

    /// Insert and return the object
    func insert<T: PersistentModel>(_ object: T) -> T {
        context.insert(object)
        return object
    }

    /// Fetch all objects of a type
    func fetchAll<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        let descriptor = FetchDescriptor<T>()
        return try context.fetch(descriptor)
    }

    /// Clear all data
    func reset() throws {
        try context.delete(model: User.self)
        try context.delete(model: CheckIn.self)
        try context.delete(model: Schedule.self)
        try context.delete(model: CircleLink.self)
        try context.delete(model: AlertEvent.self)
        try context.delete(model: Poke.self)
    }
}
