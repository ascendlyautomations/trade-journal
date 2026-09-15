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
import { logRithmicDiagnostic } from "@/lib/integrations/rithmic/rithmicSyncLogger"
import { RithmicInfraType } from "@/lib/integrations/rithmic/rithmicTemplates"
import { upsertDiscoveredRithmicAccounts } from "@/lib/integrations/rithmic/upsertDiscoveredRithmicAccounts"
import { persistRithmicPhase1TestConnection } from "@/lib/integrations/rithmic/persistRithmicPhase1TestConnection"

export type RithmicPhase1DiscoveryResult = {
  ok: boolean
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
}

export async function runRithmicPhase1Discovery(options?: {
  persistForUserId?: string | null
  supabase?: SupabaseClient | null
}): Promise<RithmicPhase1DiscoveryResult> {
  const config = loadRithmicServerConfigFromEnv()
  const diagnostics: string[] = []

  const infraType = RithmicInfraType.ORDER_PLANT
  const infraTypeLabel = "ORDER_PLANT"

  let systemNames: string[] = []
  let selectedSystemName: string | null = null

  // Official sample: system info may close the socket — use a dedicated connection.
  {
    const client = new RithmicProtocolClient(config)
    try {
      await client.connect()
      const info = await client.requestSystemInfo()
      systemNames = info.systemNames
      if (info.rpCode[0] !== "0") {
        diagnostics.push(`system_info_rp_code:${info.rpCode.join(",")}`)
      }
    } finally {
      await client.close().catch(() => undefined)
    }
  }

  if (systemNames.length === 0 && !config.systemNameOverride) {
    return {
      ok: false,
      apiEnvironment: "test",
      wssUrl: config.wssUrl,
      systemNames,
      selectedSystemName: null,
      infraType,
      infraTypeLabel,
      loginSuccess: false,
      loginRpCode: [],
      agreementRequired: false,
      uniqueUserIdMasked: null,
      accountListRpCode: [],
      accounts: [],
      accountCount: 0,
      connectionId: null,
      diagnostics: [...diagnostics, "no_system_names_available"],
    }
  }

  selectedSystemName =
    config.systemNameOverride && systemNames.includes(config.systemNameOverride)
      ? config.systemNameOverride
      : config.systemNameOverride ??
        (systemNames.length === 1 ? systemNames[0]! : systemNames[0] ?? null)

  if (!selectedSystemName) {
    return {
      ok: false,
      apiEnvironment: "test",
      wssUrl: config.wssUrl,
      systemNames,
      selectedSystemName: null,
      infraType,
      infraTypeLabel,
      loginSuccess: false,
      loginRpCode: [],
      agreementRequired: false,
      uniqueUserIdMasked: null,
      accountListRpCode: [],
      accounts: [],
      accountCount: 0,
      connectionId: null,
      diagnostics: [...diagnostics, "system_name_not_selected_set_RITHMIC_SYSTEM_NAME"],
    }
  }

  let loginSuccess = false
  let loginRpCode: string[] = []
  let agreementRequired = false
  let uniqueUserId: string | null = null
  let normalizedAccounts: RithmicDiscoveredAccount[] = []
  let accountListRpCode: string[] = []
  let connectionId: string | null = null

  const sessionClient = new RithmicProtocolClient(config)
  try {
    await sessionClient.connect()
    const login = await sessionClient.loginOrderPlant(selectedSystemName)
    loginSuccess = login.success
    loginRpCode = login.rpCode
    agreementRequired = login.agreementLikely
    uniqueUserId = login.uniqueUserId

    if (!isLoginSuccess(login.rpCode)) {
      diagnostics.push("login_not_successful")
      if (login.agreementLikely) {
        diagnostics.push("sign_agreements_in_rtrader_test")
      }
    } else {
      const loginInfo = await sessionClient.requestLoginInfo()
      if (!isLoginSuccess(loginInfo.rpCode)) {
        diagnostics.push(`login_info_rp_code:${loginInfo.rpCode.join(",")}`)
      } else if (
        loginInfo.fcmId &&
        loginInfo.ibId &&
        loginInfo.userType !== null &&
        loginInfo.userType !== undefined
      ) {
        const list = await sessionClient.requestAccountList({
          fcmId: loginInfo.fcmId,
          ibId: loginInfo.ibId,
          userType: loginInfo.userType,
        })
        accountListRpCode = list.rpCode
        if (!isAccountListSuccess(list.rpCode)) {
          diagnostics.push(`account_list_rp_code:${list.rpCode.join(",")}`)
        }
        normalizedAccounts = list.accounts.map(normalizeRithmicDiscoveredAccount)
      } else {
        diagnostics.push("login_info_missing_fcm_ib_or_user_type")
      }

      await sessionClient.logout()
    }
  } catch (err) {
    logRithmicDiagnostic("rithmic_error", {
      message: err instanceof Error ? err.message : "unknown",
    })
    diagnostics.push(err instanceof Error ? err.message : "unknown_error")
  } finally {
    await sessionClient.close().catch(() => undefined)
  }

  const ok =
    loginSuccess &&
    isAccountListSuccess(accountListRpCode) &&
    normalizedAccounts.length >= 0

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

  const safeAccounts = normalizedAccounts.map(toSafeRithmicDiscoveredAccountView)

  return {
    ok: loginSuccess && isAccountListSuccess(accountListRpCode),
    apiEnvironment: "test",
    wssUrl: config.wssUrl,
    systemNames,
    selectedSystemName,
    infraType,
    infraTypeLabel,
    loginSuccess,
    loginRpCode: loginRpCode.map((c) => (c === "0" ? c : "non_zero")),
    agreementRequired,
    uniqueUserIdMasked: uniqueUserId ? maskTail(uniqueUserId) : null,
    accountListRpCode: accountListRpCode.map((c) => (c === "0" ? c : "non_zero")),
    accounts: safeAccounts,
    accountCount: normalizedAccounts.length,
    connectionId,
    diagnostics,
  }
}

function maskTail(value: string): string {
  if (value.length <= 4) return "****"
  return `****${value.slice(-4)}`
}
