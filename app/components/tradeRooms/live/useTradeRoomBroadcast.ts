"use client"

import { useSyncExternalStore } from "react"
import {
  getTradeRoomBroadcastSnapshot,
  subscribeTradeRoomBroadcast,
  type BroadcastStoreSnapshot,
} from "@/lib/livekit/client/tradeRoomBroadcastStore.ts"

export function useTradeRoomBroadcast(): BroadcastStoreSnapshot {
  return useSyncExternalStore(
    subscribeTradeRoomBroadcast,
    getTradeRoomBroadcastSnapshot,
    getTradeRoomBroadcastSnapshot
  )
}
