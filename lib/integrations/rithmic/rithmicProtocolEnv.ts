import { defaultRithmicSslCaPath } from "@/lib/integrations/rithmic/rithmicPaths"
import type { RithmicApiEnvironment } from "@/lib/integrations/rithmic/rithmicEnv"

const DEFAULT_TEST_WSS = "wss://rituz00100.rithmic.com:443"

/** TradeTraxs-controlled protocol settings (not end-user credentials). */
export type RithmicProtocolEnv = {
  apiEnvironment: RithmicApiEnvironment
  wssUrl: string
  appName: string
  appVersion: string
  templateVersion: string
  sslCaPath: string
}

export function loadRithmicProtocolEnv(): RithmicProtocolEnv {
  const apiEnvironment = (process.env.RITHMIC_API_ENV?.trim() || "test") as RithmicApiEnvironment
  if (apiEnvironment !== "test") {
    throw new Error("rithmic_api_env_must_be_test")
  }

  const wssUrl = process.env.RITHMIC_WSS_URL?.trim() || DEFAULT_TEST_WSS
  if (!wssUrl.startsWith("wss://")) {
    throw new Error("rithmic_wss_url_must_use_wss")
  }

  return {
    apiEnvironment,
    wssUrl,
    appName: process.env.RITHMIC_APP_NAME?.trim() || "TradeTraxs",
    appVersion: process.env.RITHMIC_APP_VERSION?.trim() || "1.0.0",
    templateVersion: process.env.RITHMIC_TEMPLATE_VERSION?.trim() || "3.9",
    sslCaPath: process.env.RITHMIC_SSL_CA_PATH?.trim() || defaultRithmicSslCaPath(),
  }
}

export function isRithmicUserConnectEnabled(): boolean {
  return process.env.RITHMIC_USER_CONNECT_ENABLED === "1"
}

/** Production end-user login on live Rithmic — not confirmed with vendor yet. */
export function isRithmicProductionUserAuthConfirmed(): boolean {
  return process.env.RITHMIC_PRODUCTION_USER_AUTH_CONFIRMED === "1"
}
