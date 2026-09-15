export type RithmicPhase1ApiErrorCode =
  | "tradetraxs_auth_required"
  | "rithmic_phase1_disabled"
  | "rithmic_env_missing"
  | "rithmic_env_invalid"
  | "rithmic_discovery_failed"
  | "rithmic_wss_connect_failed"

export function rithmicPhase1ErrorMessage(code: RithmicPhase1ApiErrorCode): string {
  switch (code) {
    case "tradetraxs_auth_required":
      return "Your TradeTraxs session expired. Please sign in again."
    case "rithmic_phase1_disabled":
      return "Rithmic Test integration is disabled."
    case "rithmic_env_missing":
      return "Rithmic Test credentials are not configured."
    case "rithmic_env_invalid":
      return "Rithmic Test server configuration is invalid."
    case "rithmic_wss_connect_failed":
      return "Could not connect to Rithmic Test."
    case "rithmic_discovery_failed":
      return "Rithmic discovery failed."
    default:
      return "Rithmic discovery failed."
  }
}

/** Map discovery result diagnostics to user-facing hints (no secrets). */
export function rithmicDiscoveryDiagnosticHint(diagnostics: string[]): string | null {
  for (const d of diagnostics) {
    if (d.includes("sign_agreements") || d === "sign_agreements_in_rtrader_test") {
      return "Sign the required Rithmic Test agreements in R | Trader."
    }
    if (
      d === "system_name_not_selected_set_RITHMIC_SYSTEM_NAME" ||
      d === "multiple_systems_set_RITHMIC_SYSTEM_NAME"
    ) {
      return "Rithmic system selection required. Set RITHMIC_SYSTEM_NAME on the server."
    }
    if (d === "runtime_proto_bundle_missing" || d === "runtime_proto_load_failed") {
      return "Rithmic protocol files are missing on the server (deployment packaging)."
    }
    if (d === "runtime_ssl_ca_missing") {
      return "Rithmic Test TLS certificate bundle is missing on the server."
    }
    if (d === "system_info_timeout") {
      return "Rithmic system discovery timed out."
    }
    if (d === "login_timeout") {
      return "Rithmic Test login timed out."
    }
    if (d === "account_list_timeout") {
      return "Rithmic account discovery timed out."
    }
    if (d === "login_not_successful") {
      return "Rithmic Test login was rejected."
    }
    if (d.includes("rithmic_recv_timeout") || d.includes("ECONNREFUSED") || d.includes("socket")) {
      return "Could not connect to Rithmic Test."
    }
  }
  return null
}
