import type { RithmicRuntimeAssetsStatus } from "@/lib/integrations/rithmic/rithmicPaths"
import type { RithmicPhase1StageId } from "@/lib/integrations/rithmic/rithmicPhase1Stages"
import { safeRpCodeForClient } from "@/lib/integrations/rithmic/rithmicSafeRpCode"

export function buildRithmicPhase1UserMessage(params: {
  ok: boolean
  loginAttempted: boolean
  loginSuccess: boolean
  agreementRequired: boolean
  systemNames: string[]
  selectedSystemName: string | null
  loginRpCode: string[]
  accountListAttempted: boolean
  accountListSuccess: boolean
  accountCount: number
  runtimeAssets: RithmicRuntimeAssetsStatus
  lastSuccessfulStage: RithmicPhase1StageId
  failureStage: RithmicPhase1StageId | null
  diagnostics: string[]
}): string {
  if (!params.runtimeAssets.protoBundlePresent) {
    return "Rithmic protocol files are missing on the server. Redeploy with third_party Rithmic assets included."
  }
  if (!params.runtimeAssets.sslCaPresent) {
    return "Rithmic Test TLS certificate bundle is missing on the server."
  }

  for (const d of params.diagnostics) {
    if (d === "system_info_timeout") {
      return "Rithmic system discovery timed out."
    }
    if (d === "login_timeout") {
      return "Rithmic Test login timed out."
    }
    if (d === "login_info_timeout") {
      return "Rithmic login info request timed out."
    }
    if (d === "account_list_timeout") {
      return "Rithmic account discovery timed out."
    }
    if (d === "multiple_systems_set_RITHMIC_SYSTEM_NAME") {
      const names = params.systemNames.join(", ")
      return `Multiple Rithmic systems were returned. Configure RITHMIC_SYSTEM_NAME on the server. Available: ${names}`
    }
    if (d === "no_system_names_available") {
      return "Rithmic Test returned no system names."
    }
    if (d.startsWith("system_info_rp_code:")) {
      const codes = d.replace("system_info_rp_code:", "")
      return `Rithmic system discovery failed (${codes}).`
    }
  }

  if (params.agreementRequired) {
    return "Rithmic Test agreements must be accepted in R | Trader."
  }

  if (params.loginAttempted && !params.loginSuccess) {
    const codes = safeRpCodeForClient(params.loginRpCode)
    if (codes.length > 0) {
      return `Rithmic Test login was rejected: ${codes.join(" · ")}`
    }
    return "Rithmic Test login was rejected."
  }

  if (!params.loginAttempted) {
    if (params.failureStage === "login_socket_connecting") {
      return "Could not connect to Rithmic Test for login."
    }
    if (
      params.lastSuccessfulStage === "rithmic_system_info_received" &&
      !params.selectedSystemName
    ) {
      return "Rithmic system selection required."
    }
    if (params.diagnostics.some((x) => x.includes("ENOENT") || x.includes("WebSocket"))) {
      return "Could not connect to Rithmic Test."
    }
  }

  if (params.loginSuccess && params.accountListAttempted && params.accountListSuccess) {
    if (params.accountCount === 0) {
      return "Connected successfully — no Rithmic Test accounts were returned."
    }
    if (params.ok) {
      return `Connected successfully — ${params.accountCount} Rithmic Test account(s) discovered.`
    }
  }

  if (params.diagnostics.includes("login_info_missing_fcm_ib_or_user_type")) {
    return "Rithmic login succeeded but login info was incomplete."
  }

  const accountRp = params.diagnostics.find((d) => d.startsWith("account_list_rp_code:"))
  if (accountRp) {
    return `Rithmic account list failed (${accountRp.replace("account_list_rp_code:", "")}).`
  }

  if (params.failureStage) {
    return `Rithmic discovery stopped at stage ${params.failureStage}.`
  }

  return params.ok ? "Rithmic Test discovery completed." : "Rithmic discovery did not complete."
}
