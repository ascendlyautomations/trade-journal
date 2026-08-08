import Foundation

/// Marker documenting Domain layer invariants.
///
/// Domain may import Foundation only.
/// Domain must not import: SwiftUI, UIKit, URLSession usage, Supabase, DTOs, Data, Features.
enum DomainLayer {
    static let moduleName = "Domain"
}
