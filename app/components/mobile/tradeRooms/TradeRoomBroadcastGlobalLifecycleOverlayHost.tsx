"use client"

import { useSupabaseApiAccessToken } from "@/lib/useSupabaseApiAccessToken"
import TradeRoomBroadcastGlobalLifecycleOverlay from "./TradeRoomBroadcastGlobalLifecycleOverlay.tsx"

export default function TradeRoomBroadcastGlobalLifecycleOverlayHost() {
  const accessToken = useSupabaseApiAccessToken()

  return <TradeRoomBroadcastGlobalLifecycleOverlay accessToken={accessToken} />
}
