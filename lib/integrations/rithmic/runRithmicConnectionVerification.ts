import {
  normalizeRithmicDiscoveredAccount,
  type RithmicDiscoveredAccount,
} from "@/lib/integrations/rithmic/rithmicAccountModels"
import type { RithmicServerConfig } from "@/lib/integrations/rithmic/rithmicEnv"
import {
  isAccountListSuccess,
  isLoginSuccess,
  RithmicProtocolClient,
} from "@/lib/integrations/rithmic/rithmicProtocolClient"
import { verifyRithmicRuntimeAssets } from "@/lib/integrations/rithmic/rithmicPaths"
import { RithmicProtoEncodeError } from "@/lib/integrations/rithmic/rithmicProtoLoader"
import { logRithmicDiagnostic } from "@/lib/integrations/rithmic/rithmicSyncLogger"
import { markRithmicConnectPhase } from "@/lib/integrations/rithmic/rithmicConnectTiming"

export type RithmicConnectionVerificationResult = {
  ok: boolean
  code:
    | "success"
    | "runtime_assets_missing"
    | "system_discovery_failed"
    | "system_selection_required"
    | "no_systems"
    | "login_failed"
    | "agreement_required"
    | "account_list_failed"
    | "error"
  userMessage: string
  systemNames: string[]
  selectedSystemName: string | null
  loginRpCode: string[]
  agreementRequired: boolean
  uniqueUserId: string | null
  accounts: RithmicDiscoveredAccount[]
  accountCount: number
}

function pickSystemName(
  systemNames: string[],
  config: RithmicServerConfig,
  requestedSystemName: string | null | undefined
): { selected: string | null; needsSelection: boolean } {
  const requested = requestedSystemName?.trim()
  if (requested) {
    return { selected: requested, needsSelection: false }
  }
  if (config.systemNameOverride) {
    return { selected: config.systemNameOverride, needsSelection: false }
  }
  if (systemNames.length === 1) {
    return { selected: systemNames[0]!, needsSelection: false }
  }
  if (systemNames.length > 1) {
    return { selected: null, needsSelection: true }
  }
  return { selected: null, needsSelection: false }
}

export async function runRithmicConnectionVerification(params: {
  config: RithmicServerConfig
  systemName?: string | null
}): Promise<RithmicConnectionVerificationResult> {
  const { config } = params
  const runtimeAssets = verifyRithmicRuntimeAssets(config.sslCaPath)
  if (!runtimeAssets.protoBundlePresent || !runtimeAssets.sslCaPresent) {
    return {
      ok: false,
      code: "runtime_assets_missing",
      userMessage: "Rithmic protocol files are missing on the server.",
      systemNames: [],
      selectedSystemName: null,
      loginRpCode: [],
      agreementRequired: false,
      uniqueUserId: null,
      accounts: [],
      accountCount: 0,
    }
  }

  const requestedSystem =
    params.systemName?.trim() || config.systemNameOverride?.trim() || null

  let systemNames: string[] = []

  if (!requestedSystem) {
    markRithmicConnectPhase("system_discovery_started")
    const probe = new RithmicProtocolClient(config)
    try {
      await probe.connect("rithmic_socket_connecting")
      markRithmicConnectPhase("system_discovery_socket_open")
      const info = await probe.requestSystemInfo()
      markRithmicConnectPhase("system_discovery_complete")
      if (info.rpCode[0] !== "0") {
        return {
          ok: false,
          code: "system_discovery_failed",
          userMessage: "Could not discover Rithmic systems for this environment.",
          systemNames: info.systemNames,
          selectedSystemName: null,
          loginRpCode: [],
          agreementRequired: false,
          uniqueUserId: null,
          accounts: [],
          accountCount: 0,
        }
      }
      systemNames = info.systemNames
    } catch (err) {
      const msg = err instanceof Error ? err.message : "unknown_error"
      logRithmicDiagnostic("rithmic_error", { message: msg.slice(0, 120) })
      if (err instanceof RithmicProtoEncodeError) {
        return {
          ok: false,
          code: "error",
          userMessage: "Rithmic protocol encoding failed.",
          systemNames: [],
          selectedSystemName: null,
          loginRpCode: [],
          agreementRequired: false,
          uniqueUserId: null,
          accounts: [],
          accountCount: 0,
        }
      }
      return {
        ok: false,
        code: "system_discovery_failed",
        userMessage: "Could not connect to Rithmic.",
        systemNames: [],
        selectedSystemName: null,
        loginRpCode: [],
        agreementRequired: false,
        uniqueUserId: null,
        accounts: [],
        accountCount: 0,
      }
    } finally {
      void probe.close().catch(() => undefined)
    }
  } else {
    systemNames = [requestedSystem]
    markRithmicConnectPhase("system_discovery_skipped")
  }

  if (systemNames.length === 0 && !config.systemNameOverride && !params.systemName?.trim()) {
    return {
      ok: false,
      code: "no_systems",
      userMessage: "No Rithmic systems were returned for this login.",
      systemNames: [],
      selectedSystemName: null,
      loginRpCode: [],
      agreementRequired: false,
      uniqueUserId: null,
      accounts: [],
      accountCount: 0,
    }
  }

  const { selected, needsSelection } = pickSystemName(
    systemNames,
    config,
    params.systemName
  )
  if (needsSelection) {
    return {
      ok: false,
      code: "system_selection_required",
      userMessage: "Select your Rithmic system to continue.",
      systemNames,
      selectedSystemName: null,
      loginRpCode: [],
      agreementRequired: false,
      uniqueUserId: null,
      accounts: [],
      accountCount: 0,
    }
  }

  if (!selected) {
    return {
      ok: false,
      code: "no_systems",
      userMessage: "Could not determine which Rithmic system to use.",
      systemNames,
      selectedSystemName: null,
      loginRpCode: [],
      agreementRequired: false,
      uniqueUserId: null,
      accounts: [],
      accountCount: 0,
    }
  }

  const session = new RithmicProtocolClient(config)
  try {
    markRithmicConnectPhase("login_socket_connecting")
    await session.connect("login_socket_connecting")
    markRithmicConnectPhase("login_socket_open")
    const login = await session.loginOrderPlant(selected)
    markRithmicConnectPhase("login_response_received")
    if (!isLoginSuccess(login.rpCode)) {
      if (login.agreementLikely) {
        return {
          ok: false,
          code: "agreement_required",
          userMessage:
            "Open R | Trader Pro and make sure any required Rithmic agreements have been accepted, then try again.",
          systemNames,
          selectedSystemName: selected,
          loginRpCode: login.rpCode,
          agreementRequired: true,
          uniqueUserId: login.uniqueUserId,
          accounts: [],
          accountCount: 0,
        }
      }
      return {
        ok: false,
        code: "login_failed",
        userMessage:
          "Rithmic did not accept this login. Check your username and password, and confirm any required agreements in R | Trader Pro, then try again.",
        systemNames,
        selectedSystemName: selected,
        loginRpCode: login.rpCode,
        agreementRequired: false,
        uniqueUserId: login.uniqueUserId,
        accounts: [],
        accountCount: 0,
      }
    }

    const loginInfo = await session.requestLoginInfo()
    markRithmicConnectPhase("login_info_received")
    if (!isLoginSuccess(loginInfo.rpCode)) {
      return {
        ok: false,
        code: "login_failed",
        userMessage: "Rithmic login could not be verified.",
        systemNames,
        selectedSystemName: selected,
        loginRpCode: loginInfo.rpCode,
        agreementRequired: false,
        uniqueUserId: login.uniqueUserId,
        accounts: [],
        accountCount: 0,
      }
    }

    if (
      !loginInfo.fcmId ||
      !loginInfo.ibId ||
      loginInfo.userType === null ||
      loginInfo.userType === undefined
    ) {
      return {
        ok: false,
        code: "login_failed",
        userMessage: "Rithmic login info was incomplete.",
        systemNames,
        selectedSystemName: selected,
        loginRpCode: loginInfo.rpCode,
        agreementRequired: false,
        uniqueUserId: login.uniqueUserId,
        accounts: [],
        accountCount: 0,
      }
    }

    markRithmicConnectPhase("account_discovery_started")
    const list = await session.requestAccountList({
      fcmId: loginInfo.fcmId,
      ibId: loginInfo.ibId,
      userType: loginInfo.userType,
    })
    markRithmicConnectPhase("account_discovery_complete")

    const normalized: RithmicDiscoveredAccount[] = []
    for (const row of list.accounts) {
      const account = normalizeRithmicDiscoveredAccount(row)
      if (account) normalized.push(account)
    }

    if (!isAccountListSuccess(list.rpCode) && normalized.length === 0) {
      return {
        ok: false,
        code: "account_list_failed",
        userMessage: "Could not load Rithmic accounts for this login.",
        systemNames,
        selectedSystemName: selected,
        loginRpCode: list.rpCode,
        agreementRequired: false,
        uniqueUserId: login.uniqueUserId,
        accounts: [],
        accountCount: 0,
      }
    }

    return {
      ok: true,
      code: "success",
      userMessage: "Rithmic connection verified.",
      systemNames,
      selectedSystemName: selected,
      loginRpCode: login.rpCode,
      agreementRequired: false,
      uniqueUserId: login.uniqueUserId,
      accounts: normalized,
      accountCount: normalized.length,
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : "unknown_error"
    logRithmicDiagnostic("rithmic_error", { message: msg.slice(0, 120) })
    return {
      ok: false,
      code: "error",
      userMessage: "Could not verify Rithmic connection.",
      systemNames,
      selectedSystemName: selected,
      loginRpCode: [],
      agreementRequired: false,
      uniqueUserId: null,
      accounts: [],
      accountCount: 0,
    }
  } finally {
    void session.logout().catch(() => undefined)
    void session.close().catch(() => undefined)
    markRithmicConnectPhase("session_cleanup_scheduled")
  }
}
