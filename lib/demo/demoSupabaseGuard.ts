import { isGuestExploreActive } from "../guestExplore"
import { isDemoModeActive } from "./demoMode"

/** When true, no Supabase reads, writes, RPCs, or realtime should run. */
export function isDemoSupabaseBlocked(): boolean {
  if (isGuestExploreActive()) return false
  return isDemoModeActive()
}
