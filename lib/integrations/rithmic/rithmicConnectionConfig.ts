import type { RithmicIntegrationCredentials } from "@/lib/integrations/credentialEncryption"
import type { RithmicServerConfig } from "@/lib/integrations/rithmic/rithmicEnv"
import { loadRithmicProtocolEnv } from "@/lib/integrations/rithmic/rithmicProtocolEnv"

export function buildRithmicServerConfigFromUserCredentials(
  credentials: RithmicIntegrationCredentials
): RithmicServerConfig {
  const protocol = loadRithmicProtocolEnv()
  return {
    apiEnvironment: protocol.apiEnvironment,
    wssUrl: protocol.wssUrl,
    user: credentials.username.trim(),
    password: credentials.password,
    appName: protocol.appName,
    appVersion: protocol.appVersion,
    templateVersion: protocol.templateVersion,
    systemNameOverride: credentials.systemName.trim(),
    sslCaPath: protocol.sslCaPath,
  }
}

/** Pre-save verification (system name may be chosen after system discovery). */
export function buildRithmicServerConfigForVerification(params: {
  username: string
  password: string
  systemName?: string | null
}): RithmicServerConfig {
  const protocol = loadRithmicProtocolEnv()
  const system = params.systemName?.trim()
  return {
    apiEnvironment: protocol.apiEnvironment,
    wssUrl: protocol.wssUrl,
    user: params.username.trim(),
    password: params.password,
    appName: protocol.appName,
    appVersion: protocol.appVersion,
    templateVersion: protocol.templateVersion,
    systemNameOverride: system || null,
    sslCaPath: protocol.sslCaPath,
  }
}
