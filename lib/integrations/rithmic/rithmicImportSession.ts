import type { RithmicServerConfig } from "@/lib/integrations/rithmic/rithmicEnv"
import { loadRithmicServerConfigFromEnv } from "@/lib/integrations/rithmic/rithmicEnv"
import {
  isLoginSuccess,
  RithmicProtocolClient,
} from "@/lib/integrations/rithmic/rithmicProtocolClient"

async function resolveRithmicSystemNameForImport(
  config: RithmicServerConfig
): Promise<string> {
  if (config.systemNameOverride) return config.systemNameOverride

  const probe = new RithmicProtocolClient(config)
  try {
    await probe.connect("rithmic_socket_connecting")
    const info = await probe.requestSystemInfo()
    if (info.rpCode[0] !== "0") throw new Error("rithmic_system_info_failed")
    if (info.systemNames.length === 1) return info.systemNames[0]!
    throw new Error("rithmic_system_name_required")
  } finally {
    await probe.close().catch(() => undefined)
  }
}

/**
 * Short-lived ORDER_PLANT session for manual import (login → callback → logout).
 */
export async function withRithmicOrderPlantSession<T>(
  fn: (client: RithmicProtocolClient, ctx: { systemName: string }) => Promise<T>,
  config?: RithmicServerConfig
): Promise<T> {
  const sessionConfig = config ?? loadRithmicServerConfigFromEnv()
  const systemName = await resolveRithmicSystemNameForImport(sessionConfig)

  const client = new RithmicProtocolClient(sessionConfig)
  try {
    await client.connect("login_socket_connecting")
    const login = await client.loginOrderPlant(systemName)
    if (!isLoginSuccess(login.rpCode)) {
      throw new Error(`rithmic_login_failed:${login.rpCode.join(",")}`)
    }
    const loginInfo = await client.requestLoginInfo()
    if (!isLoginSuccess(loginInfo.rpCode)) {
      throw new Error(`rithmic_login_info_failed:${loginInfo.rpCode.join(",")}`)
    }
    return await fn(client, { systemName })
  } finally {
    await client.logout().catch(() => undefined)
    await client.close().catch(() => undefined)
  }
}
