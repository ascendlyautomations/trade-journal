import type { SupabaseClient } from "@supabase/supabase-js"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { buildRithmicServerConfigForVerification } from "@/lib/integrations/rithmic/rithmicConnectionConfig"
import { persistVerifiedRithmicUserConnection } from "@/lib/integrations/rithmic/persistRithmicUserConnection"
import { runRithmicConnectionVerification } from "@/lib/integrations/rithmic/runRithmicConnectionVerification"
import {
  assertRithmicConnectResponseSafe,
  sanitizeConnectRequestBody,
} from "@/lib/integrations/rithmic/rithmicConnectSafeResponse"
import { resolveRithmicConnectCapabilities } from "@/lib/integrations/rithmic/rithmicConnectCapabilities"
import { isRithmicDevelopmentIntegrationEnabled } from "@/lib/integrations/rithmic/rithmicDevIntegration"
import { isRithmicUserConnectEnabled } from "@/lib/integrations/rithmic/rithmicProtocolEnv"
import { safeRpCodeForClient } from "@/lib/integrations/rithmic/rithmicSafeRpCode"
import { toSafeRithmicDiscoveredAccountView } from "@/lib/integrations/rithmic/rithmicAccountModels"
import { logRithmicConnectDebug } from "@/lib/integrations/rithmic/rithmicConnectDebug"
import {
  flushRithmicConnectTiming,
  logRithmicConnectTiming,
  markRithmicConnectPhase,
  resetRithmicConnectTiming,
} from "@/lib/integrations/rithmic/rithmicConnectTiming"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"
export const maxDuration = 120

const integrationDb = supabaseServiceRole as SupabaseClient

export async function GET(req: Request) {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const body = resolveRithmicConnectCapabilities()
  assertRithmicConnectResponseSafe(body)
  return Response.json(body)
}

type ConnectResponse =
  | {
      ok: true
      connectionId: string
      systemName: string
      accountCount: number
      reconnect?: boolean
    }
  | {
      ok: false
      code: string
      userMessage: string
      systemNames?: string[]
      loginRpCode?: string[]
    }

export async function POST(req: Request): Promise<Response> {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  if (!isRithmicDevelopmentIntegrationEnabled()) {
    return Response.json(
      {
        ok: false,
        code: "development_only",
        userMessage:
          "Rithmic broker integration is only available in development environments.",
      } satisfies ConnectResponse,
      { status: 403 }
    )
  }

  if (!isRithmicUserConnectEnabled()) {
    return Response.json(
      {
        ok: false,
        code: "feature_disabled",
        userMessage: "Rithmic user connection is not enabled on this server.",
      } satisfies ConnectResponse,
      { status: 403 }
    )
  }

  let rawBody: unknown
  try {
    rawBody = await req.json()
  } catch {
    return Response.json(
      {
        ok: false,
        code: "invalid_request",
        userMessage: "Invalid request.",
      } satisfies ConnectResponse,
      { status: 400 }
    )
  }

  const parsed = sanitizeConnectRequestBody(rawBody)
  if (!parsed) {
    return Response.json(
      {
        ok: false,
        code: "invalid_request",
        userMessage: "Enter your Rithmic username and password.",
      } satisfies ConnectResponse,
      { status: 400 }
    )
  }

  const { username, password, systemName, reconnectConnectionId } = parsed

  resetRithmicConnectTiming()
  markRithmicConnectPhase("request_parsed")

  const config = buildRithmicServerConfigForVerification({
    username,
    password,
    systemName,
  })

  logRithmicConnectDebug("api_request", {
    clientSystemName: systemName?.trim() || null,
    reconnect: Boolean(reconnectConnectionId),
    apiEnvironment: config.apiEnvironment,
    wssUrl: config.wssUrl,
    appName: config.appName,
    appVersion: config.appVersion,
  })

  markRithmicConnectPhase("config_built")
  const verification = await runRithmicConnectionVerification({
    config,
    systemName,
  })
  markRithmicConnectPhase("verification_complete")

  if (!verification.ok) {
    logRithmicConnectTiming(`failed:${verification.code}`)
    flushRithmicConnectTiming()
    const failBody: ConnectResponse = {
      ok: false,
      code: verification.code,
      userMessage: verification.userMessage,
      ...(verification.code === "system_selection_required"
        ? { systemNames: verification.systemNames }
        : {}),
      ...(verification.loginRpCode.length > 0
        ? { loginRpCode: safeRpCodeForClient(verification.loginRpCode) }
        : {}),
    }
    assertRithmicConnectResponseSafe(failBody)
    const status =
      verification.code === "system_selection_required" ? 409 : 400
    logRithmicConnectDebug("api_response_failure", {
      httpStatus: status,
      code: verification.code,
      selectedSystemName: verification.selectedSystemName,
      loginRpCode: verification.loginRpCode,
      systemDiscovery:
        systemName?.trim() || config.systemNameOverride ? "skipped" : "performed",
      apiEnvironment: config.apiEnvironment,
      wssUrl: config.wssUrl,
    })
    return Response.json(failBody, { status })
  }

  if (!verification.selectedSystemName) {
    const failBody: ConnectResponse = {
      ok: false,
      code: "error",
      userMessage: "Could not determine Rithmic system.",
    }
    assertRithmicConnectResponseSafe(failBody)
    return Response.json(failBody, { status: 400 })
  }

  try {
    markRithmicConnectPhase("persist_started")
    const { connectionId } = await persistVerifiedRithmicUserConnection(
      integrationDb,
      {
        userId: user.id,
        username,
        systemName: verification.selectedSystemName,
        apiEnvironment: "test",
        uniqueUserId: verification.uniqueUserId,
        discoveredAccounts: verification.accounts,
        reconnectConnectionId,
      }
    )

    const successBody: ConnectResponse = {
      ok: true,
      connectionId,
      systemName: verification.selectedSystemName,
      accountCount: verification.accountCount,
      reconnect: Boolean(reconnectConnectionId),
    }
    assertRithmicConnectResponseSafe(successBody)
    markRithmicConnectPhase("persist_complete")
    logRithmicConnectTiming("success")
    flushRithmicConnectTiming()
    logRithmicConnectDebug("api_response_success", {
      httpStatus: 200,
      code: "success",
      selectedSystemName: verification.selectedSystemName,
      loginRpCode: verification.loginRpCode,
      accountCount: verification.accountCount,
      apiEnvironment: config.apiEnvironment,
      wssUrl: config.wssUrl,
    })
    return Response.json({
      ...successBody,
      accounts: verification.accounts.map(toSafeRithmicDiscoveredAccountView),
    })
  } catch (err) {
    logRithmicConnectTiming("persist_failed")
    flushRithmicConnectTiming()
    const message = err instanceof Error ? err.message : "connect_failed"
    const userMessage =
      message === "rithmic_reconnect_identity_mismatch"
        ? "This login does not match the Rithmic connection you are reconnecting."
        : "Could not save Rithmic connection."
    const failBody: ConnectResponse = {
      ok: false,
      code: "persist_failed",
      userMessage,
    }
    assertRithmicConnectResponseSafe(failBody)
    return Response.json(failBody, { status: 500 })
  }
}
