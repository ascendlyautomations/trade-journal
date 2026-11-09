"use client"

import { useEffect, useRef, useState } from "react"
import { usePathname } from "next/navigation"
import { supabase } from "@/lib/supabaseClient.ts"
import { isAppCommunityPath } from "@/lib/communityPath.ts"
import {
  setTradeRoomBroadcastStudioPresentation,
} from "@/lib/livekit/client/tradeRoomBroadcastStore.ts"
import { useTradeRoomBroadcast } from "./useTradeRoomBroadcast.ts"
import TradeRoomBroadcastGlobalChrome from "./TradeRoomBroadcastGlobalChrome.tsx"

export default function TradeRoomBroadcastGlobalChromeHost() {
  const [accessToken, setAccessToken] = useState<string | null>(null)
  const pathname = usePathname()
  const broadcast = useTradeRoomBroadcast()
  const viewerTheaterBeforeNavigateRef = useRef(false)

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => {
      setAccessToken(data.session?.access_token ?? null)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      setAccessToken(session?.access_token ?? null)
    })
    return () => sub.subscription.unsubscribe()
  }, [])

  useEffect(() => {
    const watchingAsViewer =
      broadcast.isWatching &&
      (broadcast.role === "viewer" || broadcast.role === "conversation")

    if (!broadcast.isPublishing && !watchingAsViewer) {
      viewerTheaterBeforeNavigateRef.current = false
    }

    if (isAppCommunityPath(pathname)) {
      if (
        watchingAsViewer &&
        viewerTheaterBeforeNavigateRef.current &&
        broadcast.studioPresentation === "mini"
      ) {
        viewerTheaterBeforeNavigateRef.current = false
        setTradeRoomBroadcastStudioPresentation("studio")
      }
      return
    }

    if (broadcast.studioPresentation !== "studio") return

    if (broadcast.isPublishing && broadcast.role === "broadcaster") {
      setTradeRoomBroadcastStudioPresentation("mini")
      return
    }

    if (watchingAsViewer) {
      viewerTheaterBeforeNavigateRef.current = true
      setTradeRoomBroadcastStudioPresentation("mini")
    }
  }, [
    pathname,
    broadcast.isPublishing,
    broadcast.isWatching,
    broadcast.role,
    broadcast.studioPresentation,
  ])

  return <TradeRoomBroadcastGlobalChrome accessToken={accessToken} />
}
