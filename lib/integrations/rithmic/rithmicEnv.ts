import path from "path"

export type RithmicApiEnvironment = "test"

export type RithmicServerConfig = {
  apiEnvironment: RithmicApiEnvironment
  wssUrl: string
  user: string
  password: string
  appName: string
  appVersion: string
  templateVersion: string
  systemNameOverride: string | null
  sslCaPath: string
}

const DEFAULT_TEST_WSS = "wss://rituz00100.rithmic.com:443"

export function rithmicSslCaPath(): string {
  return path.join(process.cwd(), "lib/integrations/rithmic/rithmic_ssl_cert_auth_params")
}

export function loadRithmicServerConfigFromEnv(): RithmicServerConfig {
  const apiEnvironment = (process.env.RITHMIC_API_ENV?.trim() || "test") as RithmicApiEnvironment
  if (apiEnvironment !== "test") {
    throw new Error("rithmic_api_env_must_be_test")
  }

  const user = process.env.RITHMIC_API_USER?.trim()
  const password = process.env.RITHMIC_API_PASSWORD?.trim()
  if (!user || !password) {
    throw new Error("rithmic_api_credentials_missing")
  }

  const wssUrl = process.env.RITHMIC_WSS_URL?.trim() || DEFAULT_TEST_WSS
  if (!wssUrl.startsWith("wss://")) {
    throw new Error("rithmic_wss_url_must_use_wss")
  }

  return {
    apiEnvironment,
    wssUrl,
    user,
    password,
    appName: process.env.RITHMIC_APP_NAME?.trim() || "TradeTraxs",
    appVersion: process.env.RITHMIC_APP_VERSION?.trim() || "1.0.0",
    templateVersion: process.env.RITHMIC_TEMPLATE_VERSION?.trim() || "3.9",
    systemNameOverride: process.env.RITHMIC_SYSTEM_NAME?.trim() || null,
    sslCaPath: process.env.RITHMIC_SSL_CA_PATH?.trim() || rithmicSslCaPath(),
  }
}

export function isRithmicPhase1ApiEnabled(): boolean {
  return process.env.RITHMIC_PHASE1_API_ENABLED === "1"
}
