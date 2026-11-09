import { resolveBroadcastGlobalStudioChromeVisible } from "./broadcastGlobalStudioVisibility.ts"
import type { BroadcastStoreSnapshot } from "./tradeRoomBroadcastStore.ts"

export type TradeRoomBroadcastGlobalChromeSnapshotSlice = Pick<
  BroadcastStoreSnapshot,
  | "isPublishing"
  | "isWatching"
  | "role"
  | "studioPresentation"
  | "status"
  | "publisherSessionId"
  | "obsHostUiPhase"
  | "obsBroadcastBootstrapping"
>

/** Same predicate as `TradeRoomBroadcastGlobalChrome` render gate (for tests / tooling). */
export function tradeRoomBroadcastGlobalChromeVisible(
  snapshot: TradeRoomBroadcastGlobalChromeSnapshotSlice
): boolean {
  return resolveBroadcastGlobalStudioChromeVisible({
    isPublishing: snapshot.isPublishing,
    isWatching: snapshot.isWatching,
    role: snapshot.role,
    studioPresentation: snapshot.studioPresentation,
    status: snapshot.status,
    publisherSessionId: snapshot.publisherSessionId,
    obsHostUiPhase: snapshot.obsHostUiPhase,
    obsBroadcastBootstrapping: snapshot.obsBroadcastBootstrapping,
  })
}
