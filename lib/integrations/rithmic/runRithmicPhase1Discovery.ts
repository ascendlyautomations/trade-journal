import type { SupabaseClient } from "@supabase/supabase-js"
import {
  normalizeRithmicDiscoveredAccount,
  toSafeRithmicDiscoveredAccountView,
  type RithmicDiscoveredAccount,
} from "@/lib/integrations/rithmic/rithmicAccountModels"
import { loadRithmicServerConfigFromEnv } from "@/lib/integrations/rithmic/rithmicEnv"
import {
  isAccountListSuccess,
  isLoginSuccess,
  RithmicProtocolClient,
} from "@/lib/integrations/rithmic/rithmicProtocolClient"
import {
  RithmicPhase1Stage,
  RithmicPhase1StageTracker,
  type RithmicPhase1StageId,
} from "@/lib/integrations/rithmic/rithmicPhase1Stages"
import { buildRithmicPhase1UserMessage } from "@/lib/integrations/rithmic/rithmicPhase1UserMessage"
import {
  verifyRithmicRuntimeAssets,
  type RithmicRuntimeAssetsStatus,
} from "@/lib/integrations/rithmic/rithmicPaths"
import { safeRpCodeForClient } from "@/lib/integrations/rithmic/rithmicSafeRpCode"
import { RithmicProtoEncodeError } from "@/lib/integrations/rithmic/rithmicProtoLoader"
import { logRithmicDiagnostic } from "@/lib/integrations/rithmic/rithmicSyncLogger"
import { RithmicInfraType } from "@/lib/integrations/rithmic/rithmicTemplates"
import { upsertDiscoveredRithmicAccounts } from "@/lib/integrations/rithmic/upsertDiscoveredRithmicAccounts"
import { persistRithmicPhase1TestConnection } from "@/lib/integrations/rithmic/persistRithmicPhase1TestConnection"

export type RithmicPhase1DiscoveryResult = {
  ok: boolean
  userMessage: string
  lastSuccessfulStage: RithmicPhase1StageId
  failureStage: RithmicPhase1StageId | null
  loginAttempted: boolean
  accountListAttempted: boolean
  runtimeAssets: RithmicRuntimeAssetsStatus
  apiEnvironment: "test"
  wssUrl: string
  systemNames: string[]
  selectedSystemName: string | null
  infraType: number
  infraTypeLabel: string
  loginSuccess: boolean
  loginRpCode: string[]
  agreementRequired: boolean
  uniqueUserIdMasked: string | null
  accountListRpCode: string[]
  accounts: ReturnType<typeof toSafeRithmicDiscoveredAccountView>[]
  accountCount: number
  connectionId: string | null
  diagnostics: string[]
  stagesCompleted: RithmicPhase1StageId[]
}

function pushErr(
  diagnostics: string[],
  tracker: RithmicPhase1StageTracker,
  stage: RithmicPhase1StageId,
  message: string
): void {
  diagnostics.push(message)
  tracker.fail(stage)
}

export async function runRithmicPhase1Discovery(options?: {
  persistForUserId?: string | null
  supabase?: SupabaseClient | null
}): Promise<RithmicPhase1DiscoveryResult> {
  const tracker = new RithmicPhase1StageTracker()
  const diagnostics: string[] = []

  tracker.mark(RithmicPhase1Stage.envPreflight)
  const config = loadRithmicServerConfigFromEnv()
  const runtimeAssets = verifyRithmicRuntimeAssets(config.sslCaPath)

  if (!runtimeAssets.protoBundlePresent || !runtimeAssets.sslCaPresent) {
    pushErr(
      diagnostics,
      tracker,
      RithmicPhase1Stage.runtimeAssetsVerified,
      runtimeAssets.protoBundlePresent
        ? "runtime_ssl_ca_missing"
        : "runtime_proto_bundle_missing"
    )
    return finalizeResult({
      tracker,
      diagnostics,
      config,
      runtimeAssets,
      systemNames: [],
      selectedSystemName: null,
      loginAttempted: false,
      accountListAttempted: false,
      loginSuccess: false,
      loginRpCode: [],
      agreementRequired: false,
      uniqueUserId: null,
      accountListRpCode: [],
      normalizedAccounts: [],
      connectionId: null,
    })
  }

  tracker.mark(RithmicPhase1Stage.runtimeAssetsVerified)

  const infraType = RithmicInfraType.ORDER_PLANT
  const infraTypeLabel = "ORDER_PLANT"

  let systemNames: string[] = []
  let selectedSystemName: string | null = null
  let systemInfoSucceeded = false

  {
    const client = new RithmicProtocolClient(config)
    try {
      tracker.mark(RithmicPhase1Stage.systemInfoConnecting)
      await client.connect("rithmic_socket_connecting")
      tracker.mark(RithmicPhase1Stage.systemInfoConnected)

      tracker.mark(RithmicPhase1Stage.systemInfoRequested)
      const info = await client.requestSystemInfo()
      tracker.mark(RithmicPhase1Stage.systemInfoEncoded)
      tracker.mark(RithmicPhase1Stage.systemInfoSent)
      tracker.mark(RithmicPhase1Stage.systemInfoReceived)
      systemInfoSucceeded = true

      systemNames = info.systemNames
      if (info.rpCode[0] !== "0") {
        diagnostics.push(`system_info_rp_code:${info.rpCode.join(",")}`)
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : "unknown_error"
      logRithmicDiagnostic("rithmic_error", { message: msg })
      if (err instanceof RithmicProtoEncodeError) {
        diagnostics.push("rithmic_proto_encode_failed")
        diagnostics.push(msg.slice(0, 160))
        tracker.fail(RithmicPhase1Stage.systemInfoEncoded)
      } else if (msg.startsWith("runtime_proto_load_failed")) {
        diagnostics.push("runtime_proto_load_failed")
        tracker.fail(RithmicPhase1Stage.runtimeAssetsVerified)
      } else {
        diagnostics.push(msg)
        if (msg === "system_info_timeout") {
          tracker.fail(RithmicPhase1Stage.systemInfoSent)
        } else if (msg.includes("ENOENT")) {
          tracker.fail(RithmicPhase1Stage.runtimeAssetsVerified)
          diagnostics.push("runtime_ssl_or_proto_missing")
        } else {
          tracker.fail(RithmicPhase1Stage.systemInfoConnecting)
        }
      }
    } finally {
      await client.close().catch(() => undefined)
    }
  }

  if (!systemInfoSucceeded) {
    return finalizeResult({
      tracker,
      diagnostics,
      config,
      runtimeAssets,
      systemNames,
      selectedSystemName: null,
      loginAttempted: false,
      accountListAttempted: false,
      loginSuccess: false,
      loginRpCode: [],
      agreementRequired: false,
      uniqueUserId: null,
      accountListRpCode: [],
      normalizedAccounts: [],
      connectionId: null,
    })
  }

  if (systemNames.length === 0 && !config.systemNameOverride) {
    diagnostics.push("no_system_names_available")
    tracker.fail(RithmicPhase1Stage.systemNameSelected)
    return finalizeResult({
      tracker,
      diagnostics,
      config,
      runtimeAssets,
      systemNames,
      selectedSystemName: null,
      loginAttempted: false,
      accountListAttempted: false,
      loginSuccess: false,
      loginRpCode: [],
      agreementRequired: false,
      uniqueUserId: null,
      accountListRpCode: [],
      normalizedAccounts: [],
      connectionId: null,
    })
  }

  if (systemNames.length > 1 && !config.systemNameOverride) {
    diagnostics.push("multiple_systems_set_RITHMIC_SYSTEM_NAME")
    tracker.fail(RithmicPhase1Stage.systemNameSelected)
    return finalizeResult({
      tracker,
      diagnostics,
      config,
      runtimeAssets,
      systemNames,
      selectedSystemName: null,
      loginAttempted: false,
      accountListAttempted: false,
      loginSuccess: false,
      loginRpCode: [],
      agreementRequired: false,
      uniqueUserId: null,
      accountListRpCode: [],
      normalizedAccounts: [],
      connectionId: null,
    })
  }

  if (config.systemNameOverride) {
    selectedSystemName = config.systemNameOverride
    if (systemNames.length > 0 && !systemNames.includes(selectedSystemName)) {
      diagnostics.push("RITHMIC_SYSTEM_NAME_not_in_discovered_list")
    }
  } else {
    selectedSystemName = systemNames[0] ?? null
  }

  if (!selectedSystemName) {
    diagnostics.push("system_name_not_selected_set_RITHMIC_SYSTEM_NAME")
    tracker.fail(RithmicPhase1Stage.systemNameSelected)
    return finalizeResult({
      tracker,
      diagnostics,
      config,
      runtimeAssets,
      systemNames,
      selectedSystemName: null,
      loginAttempted: false,
      accountListAttempted: false,
      loginSuccess: false,
      loginRpCode: [],
      agreementRequired: false,
      uniqueUserId: null,
      accountListRpCode: [],
      normalizedAccounts: [],
      connectionId: null,
    })
  }

  tracker.mark(RithmicPhase1Stage.systemNameSelected)

  let loginAttempted = false
  let loginSuccess = false
  let loginRpCode: string[] = []
  let agreementRequired = false
  let uniqueUserId: string | null = null
  let accountListAttempted = false
  let normalizedAccounts: RithmicDiscoveredAccount[] = []
  let accountListRpCode: string[] = []
  let connectionId: string | null = null

  const sessionClient = new RithmicProtocolClient(config)
  try {
    tracker.mark(RithmicPhase1Stage.loginConnecting)
    await sessionClient.connect("login_socket_connecting")
    tracker.mark(RithmicPhase1Stage.loginConnected)

    loginAttempted = true
    tracker.mark(RithmicPhase1Stage.loginStarted)
    const login = await sessionClient.loginOrderPlant(selectedSystemName)
    tracker.mark(RithmicPhase1Stage.loginResponse)

    loginSuccess = login.success
    loginRpCode = login.rpCode
    agreementRequired = login.agreementLikely
    uniqueUserId = login.uniqueUserId

    if (!isLoginSuccess(login.rpCode)) {
      diagnostics.push("login_not_successful")
      if (login.agreementLikely) {
        diagnostics.push("sign_agreements_in_rtrader_test")
      }
      tracker.fail(RithmicPhase1Stage.loginSuccess)
    } else {
      tracker.mark(RithmicPhase1Stage.loginSuccess)

      const loginInfo = await sessionClient.requestLoginInfo()
      tracker.mark(RithmicPhase1Stage.loginInfoReceived)

      if (!isLoginSuccess(loginInfo.rpCode)) {
        diagnostics.push(`login_info_rp_code:${loginInfo.rpCode.join(",")}`)
        tracker.fail(RithmicPhase1Stage.loginInfoReceived)
      } else if (
        loginInfo.fcmId &&
        loginInfo.ibId &&
        loginInfo.userType !== null &&
        loginInfo.userType !== undefined
      ) {
        accountListAttempted = true
        tracker.mark(RithmicPhase1Stage.accountListRequested)

        const list = await sessionClient.requestAccountList({
          fcmId: loginInfo.fcmId,
          ibId: loginInfo.ibId,
          userType: loginInfo.userType,
        })
        tracker.mark(RithmicPhase1Stage.accountListResponse)

        accountListRpCode = list.rpCode
        if (!isAccountListSuccess(list.rpCode)) {
          diagnostics.push(`account_list_rp_code:${list.rpCode.join(",")}`)
        }
        normalizedAccounts = list.accounts.map(normalizeRithmicDiscoveredAccount)
      } else {
        diagnostics.push("login_info_missing_fcm_ib_or_user_type")
        tracker.fail(RithmicPhase1Stage.loginInfoReceived)
      }

      await sessionClient.logout()
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : "unknown_error"
    logRithmicDiagnostic("rithmic_error", { message: msg })
    diagnostics.push(msg)
    if (msg === "login_timeout") {
      tracker.fail(RithmicPhase1Stage.loginResponse)
    } else if (msg === "login_info_timeout") {
      tracker.fail(RithmicPhase1Stage.loginInfoReceived)
    } else if (msg === "account_list_timeout") {
      tracker.fail(RithmicPhase1Stage.accountListResponse)
    } else if (!loginAttempted) {
      tracker.fail(RithmicPhase1Stage.loginConnecting)
    } else if (loginAttempted && !loginSuccess) {
      tracker.fail(RithmicPhase1Stage.loginResponse)
    } else {
      tracker.fail(RithmicPhase1Stage.accountListRequested)
    }
  } finally {
    await sessionClient.close().catch(() => undefined)
  }

  const accountListSuccess = isAccountListSuccess(accountListRpCode)
  const ok =
    loginSuccess &&
    accountListAttempted &&
    accountListSuccess

  if (ok) {
    tracker.mark(RithmicPhase1Stage.complete)
  }

  if (
    ok &&
    options?.persistForUserId &&
    options.supabase &&
    uniqueUserId &&
    normalizedAccounts.length > 0
  ) {
    const persisted = await persistRithmicPhase1TestConnection(options.supabase, {
      userId: options.persistForUserId,
      uniqueUserId,
      systemName: selectedSystemName,
    })
    connectionId = persisted.connectionId
    await upsertDiscoveredRithmicAccounts(options.supabase, {
      userId: options.persistForUserId,
      connectionId: persisted.connectionId,
      discovered: normalizedAccounts,
    })
  }

  return finalizeResult({
    tracker,
    diagnostics,
    config,
    runtimeAssets,
    systemNames,
    selectedSystemName,
    loginAttempted,
    accountListAttempted,
    loginSuccess,
    loginRpCode,
    agreementRequired,
    uniqueUserId,
    accountListRpCode,
    normalizedAccounts,
    connectionId,
    okOverride: ok,
  })
}

function finalizeResult(params: {
  tracker: RithmicPhase1StageTracker
  diagnostics: string[]
  config: ReturnType<typeof loadRithmicServerConfigFromEnv>
  runtimeAssets: RithmicRuntimeAssetsStatus
  systemNames: string[]
  selectedSystemName: string | null
  loginAttempted: boolean
  accountListAttempted: boolean
  loginSuccess: boolean
  loginRpCode: string[]
  agreementRequired: boolean
  uniqueUserId: string | null
  accountListRpCode: string[]
  normalizedAccounts: RithmicDiscoveredAccount[]
  connectionId: string | null
  okOverride?: boolean
}): RithmicPhase1DiscoveryResult {
  const accountListSuccess = isAccountListSuccess(params.accountListRpCode)
  const ok =
    params.okOverride ??
    (params.loginSuccess && params.accountListAttempted && accountListSuccess)

  const safeAccounts = params.normalizedAccounts.map(toSafeRithmicDiscoveredAccountView)
  const safeLoginRp = safeRpCodeForClient(params.loginRpCode)

  const userMessage = buildRithmicPhase1UserMessage({
    ok,
    loginAttempted: params.loginAttempted,
    loginSuccess: params.loginSuccess,
    agreementRequired: params.agreementRequired,
    systemNames: params.systemNames,
    selectedSystemName: params.selectedSystemName,
    loginRpCode: params.loginRpCode,
    accountListAttempted: params.accountListAttempted,
    accountListSuccess,
    accountCount: params.normalizedAccounts.length,
    runtimeAssets: params.runtimeAssets,
    lastSuccessfulStage: params.tracker.lastSuccessful,
    failureStage: params.tracker.failure,
    diagnostics: params.diagnostics,
  })

  return {
    ok,
    userMessage,
    lastSuccessfulStage: params.tracker.lastSuccessful,
    failureStage: params.tracker.failure,
    loginAttempted: params.loginAttempted,
    accountListAttempted: params.accountListAttempted,
    runtimeAssets: params.runtimeAssets,
    apiEnvironment: "test",
    wssUrl: params.config.wssUrl,
    systemNames: params.systemNames,
    selectedSystemName: params.selectedSystemName,
    infraType: RithmicInfraType.ORDER_PLANT,
    infraTypeLabel: "ORDER_PLANT",
    loginSuccess: params.loginSuccess,
    loginRpCode: safeLoginRp,
    agreementRequired: params.agreementRequired,
    uniqueUserIdMasked: params.uniqueUserId ? maskTail(params.uniqueUserId) : null,
    accountListRpCode: safeRpCodeForClient(params.accountListRpCode),
    accounts: safeAccounts,
    accountCount: params.normalizedAccounts.length,
    connectionId: params.connectionId,
    diagnostics: params.diagnostics,
    stagesCompleted: params.tracker.completed,
  }
}

function maskTail(value: string): string {
  if (value.length <= 4) return "****"
  return `****${value.slice(-4)}`
}
