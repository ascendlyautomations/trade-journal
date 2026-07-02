import { isDemoModeActive } from "./demoMode"

/** When true, no Supabase reads, writes, RPCs, or realtime should run. */
export function isDemoSupabaseBlocked(): boolean {
  return isDemoModeActive()
}
