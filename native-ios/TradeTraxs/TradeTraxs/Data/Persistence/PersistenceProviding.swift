import Foundation

/// Local persistence seam (SwiftData later). No schema yet.
nonisolated protocol PersistenceProviding: Sendable {
    var isAvailable: Bool { get }
}

nonisolated struct PlaceholderPersistenceProvider: PersistenceProviding {
    var isAvailable: Bool { false }
}
