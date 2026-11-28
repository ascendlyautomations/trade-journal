import { isRithmicDevelopmentIntegrationEnabled } from "@/lib/integrations/rithmic/rithmicDevIntegration"
import {
  isRithmicProductionUserAuthConfirmed,
  isRithmicUserConnectEnabled,
  loadRithmicProtocolEnv,
} from "@/lib/integrations/rithmic/rithmicProtocolEnv"

export type RithmicConnectCapabilities = {
  userConnectEnabled: boolean
  productionUserAuthConfirmed: boolean
  apiEnvironment: string
  showConnectUi: boolean
  developmentIntegrationEnabled: boolean
  credentialModelStatus: "confirmed_with_vendor" | "not_yet_confirmed"
}

/**
 * Authoritative mobile/BFF contract for whether Connect Rithmic should be interactive.
 *
 * - `RITHMIC_USER_CONNECT_ENABLED=1` is required for any user connect UI.
 * - Test environment: show UI when protocol env loads (R|Protocol test WSS configured).
 * - Production environment: only when vendor has confirmed end-user auth
 *   (`RITHMIC_PRODUCTION_USER_AUTH_CONFIRMED=1`) — do not imply approval otherwise.
 */
export function resolveRithmicConnectCapabilities(): RithmicConnectCapabilities {
  const developmentIntegrationEnabled = isRithmicDevelopmentIntegrationEnabled()
  const userConnectEnabled = isRithmicUserConnectEnabled()
  const productionUserAuthConfirmed = isRithmicProductionUserAuthConfirmed()
  const apiEnvironmentLabel =
    process.env.RITHMIC_API_ENV?.trim() || "test"

  let showConnectUi = false
  if (developmentIntegrationEnabled && userConnectEnabled) {
    if (apiEnvironmentLabel === "test") {
      try {
        loadRithmicProtocolEnv()
        showConnectUi = true
      } catch {
        showConnectUi = false
      }
    } else if (
      apiEnvironmentLabel === "production" &&
      productionUserAuthConfirmed
    ) {
      showConnectUi = true
    }
  }

  let apiEnvironment = apiEnvironmentLabel
  try {
    apiEnvironment = loadRithmicProtocolEnv().apiEnvironment
  } catch {
    // Keep label from env for client messaging.
  }

  return {
    userConnectEnabled,
    productionUserAuthConfirmed,
    apiEnvironment,
    showConnectUi,
    developmentIntegrationEnabled,
    credentialModelStatus: productionUserAuthConfirmed
      ? "confirmed_with_vendor"
      : "not_yet_confirmed",
  }
}
