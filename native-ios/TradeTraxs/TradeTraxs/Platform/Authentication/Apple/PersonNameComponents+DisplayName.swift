import Foundation

extension PersonNameComponents {
    /// Web-parity display name from Apple's first-authorization name components.
    func formattedDisplayName() -> String? {
        let formatter = PersonNameComponentsFormatter()
        let formatted = formatter.string(from: self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return formatted.isEmpty ? nil : formatted
    }
}
