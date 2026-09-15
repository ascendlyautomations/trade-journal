export type RithmicDiagnosticEvent =
  | "rithmic_socket_connecting"
  | "rithmic_socket_connected"
  | "login_socket_connecting"
  | "login_socket_connected"
  | "system_info_encoded"
  | "system_info_sent"
  | "system_info_requested"
  | "rithmic_system_info_received"
  | "rithmic_login_started"
  | "rithmic_login_response"
  | "rithmic_login_success"
  | "rithmic_login_failed"
  | "rithmic_login_info_received"
  | "rithmic_account_list_requested"
  | "rithmic_account_discovered"
  | "account_list_response"
  | "rithmic_logout"
  | "rithmic_socket_closed"
  | "rithmic_agreement_required"
  | "rithmic_error"

export function maskBrokerIdentifier(value: string | null | undefined): string {
  if (!value) return "—"
  const v = value.trim()
  if (v.length <= 4) return "****"
  return `${"*".repeat(Math.min(v.length - 4, 8))}${v.slice(-4)}`
}

export function logRithmicDiagnostic(
  event: RithmicDiagnosticEvent,
  details?: Record<string, string | number | boolean | null | undefined>
): void {
  const safe: Record<string, string | number | boolean> = { event }
  if (details) {
    for (const [key, val] of Object.entries(details)) {
      if (val === undefined || val === null) continue
      if (
        key.includes("password") ||
        key.includes("credential") ||
        key === "user" ||
        key === "raw"
      ) {
        continue
      }
      if (
        typeof val === "string" &&
        (key.includes("account") ||
          key.includes("fcm") ||
          key.includes("ib_id") ||
          key.includes("user_id") ||
          key === "unique_user_id")
      ) {
        safe[key] = maskBrokerIdentifier(val)
        continue
      }
      safe[key] = val
    }
  }
  console.info("[rithmic]", JSON.stringify(safe))
}
