import Foundation
import UIKit

/// Stable install identity for `device_push_tokens.installation_id` (shared by push + local reminder sync).
enum DevicePushInstallationID {
  private static let defaultsKey = "tt.ios.push.installation_id"

  static var current: String {
    if let existing = UserDefaults.standard.string(forKey: defaultsKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !existing.isEmpty,
      existing != "unknown"
    {
      return existing
    }
    let generated =
      UIDevice.current.identifierForVendor?.uuidString
      ?? UUID().uuidString
    UserDefaults.standard.set(generated, forKey: defaultsKey)
    return generated
  }
}