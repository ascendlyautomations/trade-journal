export const RithmicPhase1Stage = {
  envPreflight: "env_preflight",
  runtimeAssetsVerified: "runtime_assets_verified",
  systemInfoConnecting: "rithmic_socket_connecting",
  systemInfoConnected: "rithmic_socket_connected",
  systemInfoEncoded: "system_info_encoded",
  systemInfoSent: "system_info_sent",
  systemInfoRequested: "system_info_requested",
  systemInfoReceived: "rithmic_system_info_received",
  systemNameSelected: "system_name_selected",
  loginConnecting: "login_socket_connecting",
  loginConnected: "login_socket_connected",
  loginStarted: "rithmic_login_started",
  loginResponse: "rithmic_login_response",
  loginSuccess: "rithmic_login_success",
  loginInfoReceived: "rithmic_login_info_received",
  accountListRequested: "account_list_requested",
  accountListResponse: "account_list_response",
  complete: "complete",
} as const

export type RithmicPhase1StageId =
  (typeof RithmicPhase1Stage)[keyof typeof RithmicPhase1Stage]

export class RithmicPhase1StageTracker {
  lastSuccessful: RithmicPhase1StageId = RithmicPhase1Stage.envPreflight
  failure: RithmicPhase1StageId | null = null
  readonly completed: RithmicPhase1StageId[] = []

  mark(stage: RithmicPhase1StageId): void {
    this.lastSuccessful = stage
    this.completed.push(stage)
  }

  fail(stage: RithmicPhase1StageId): void {
    this.failure = stage
  }
}
