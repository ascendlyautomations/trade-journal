/**
 * Backend V2 RPC naming + contract version metadata.
 * No SQL is created in Phase 1 — names are reserved for future migrations.
 */

export const BACKEND_V2_CONTRACT_VERSION = "v1" as const

export type BackendV2ContractVersion = typeof BACKEND_V2_CONTRACT_VERSION

/** Future public Postgres function names (not created yet). */
export const BackendV2RpcNames = {
  session: "rpc_v1_session_bootstrap",
  dashboard: "rpc_v1_dashboard_bootstrap",
  feed: "rpc_v1_feed_bootstrap",
  profile: "rpc_v1_profile_bootstrap",
  profileTabTrades: "rpc_v1_profile_tab_trades",
  profileTabPosts: "rpc_v1_profile_tab_posts",
  profileTabReels: "rpc_v1_profile_tab_reels",
  profileTabAchievements: "rpc_v1_profile_tab_achievements",
  messagingHome: "rpc_v2_messaging_bootstrap",
  messaging: "rpc_v2_messaging_bootstrap",
  /** Legacy inbox RPC — web fallback only; native-ios continues to reference V1. */
  messagingV1: "rpc_v1_messaging_bootstrap",
  conversation: "rpc_v1_conversation_bootstrap",
  conversationThread: "rpc_v1_conversation_thread_bootstrap",
  room: "rpc_v1_room_bootstrap",
  activity: "rpc_v1_activity_bootstrap",
  explore: "rpc_v1_explore_bootstrap",
  leaderboard: "rpc_v1_leaderboard_bootstrap",
  calendar: "rpc_v1_calendar_bootstrap",
  tradesList: "rpc_v1_trades_list_bootstrap",
  tradeDetail: "rpc_v1_trade_detail_bootstrap",
  postDetail: "rpc_v1_post_detail_bootstrap",
  settings: "rpc_v1_settings_bootstrap",
  gettingStarted: "rpc_v1_getting_started_signals",
  propFirm: "rpc_v1_prop_firm_bootstrap",
} as const

export type BackendV2RpcName =
  (typeof BackendV2RpcNames)[keyof typeof BackendV2RpcNames]

export function isBackendV2RpcName(name: string): name is BackendV2RpcName {
  return (Object.values(BackendV2RpcNames) as string[]).includes(name)
}

export function backendV2RpcName(
  screen: keyof typeof BackendV2RpcNames
): BackendV2RpcName {
  return BackendV2RpcNames[screen]
}

/** Envelope metadata every bootstrap payload must include. */
export type BootstrapMetaV1 = {
  contract_version: BackendV2ContractVersion
  server_time: string
  viewer_id: string | null
}

export function assertContractVersion(
  meta: { contract_version?: string } | null | undefined,
  expected: BackendV2ContractVersion = BACKEND_V2_CONTRACT_VERSION
): void {
  if (!meta || meta.contract_version !== expected) {
    throw new Error(
      `Backend V2 contract version mismatch: expected ${expected}, got ${meta?.contract_version ?? "missing"}`
    )
  }
}
