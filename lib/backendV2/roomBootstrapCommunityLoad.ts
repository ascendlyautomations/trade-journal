import { isBackendV2Enabled } from "./flags.ts"

/** When true, Community room/section data is owned by room bootstrap (RPC or controlled fallback). */
export function shouldSkipLegacyRoomDataEffects(): boolean {
  return isBackendV2Enabled("rooms")
}
