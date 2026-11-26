import Foundation
import OSLog

/// Per-installation mirror of verified local Performance Report reminders (`device_push_tokens`).
enum PerformanceReportReminderServerSync {
  private static var transport: SupabaseTransport?

  static func configure(transport: SupabaseTransport) {
    self.transport = transport
  }

  static func reportActive(_ active: Bool) async {
    guard let transport else { return }
    struct Body: Encodable {
      var active: Bool
      var installationId: String
    }
    let body = Body(active: active, installationId: DevicePushInstallationID.current)
    do {
      let data = try transport.encodeJSON(body)
      let response = try await transport.send(
        host: .bff,
        path: "/api/push/performance-report-local-reminders",
        method: .post,
        body: data,
        requiresAuthentication: true
      )
      guard (200 ... 299).contains(response.statusCode) else {
        AppLog.notifications.error(
          "Performance report local reminder sync failed: HTTP \(response.statusCode, privacy: .public)"
        )
        return
      }
    } catch {
      AppLog.notifications.error(
        "Performance report local reminder sync failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }
}