import Foundation

/// Reversible switch to use system keyboard behavior only (no custom accessories, hide-sync probing, or story strip).
///
/// Set to `false` to restore Done toolbars, sign keyboard toggles, focus sync on hide, and story accessory suppression.
enum ExperienceKeyboardNativeIsolation {
    /// When `true`, custom keyboard accessories and transition probing are disabled app-wide.
    static let isEnabled = true
}