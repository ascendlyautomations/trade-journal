"use client"

import { useEffect, useRef, useState } from "react"
import { usePathname } from "next/navigation"
import { supabase } from "@/lib/supabaseClient.ts"
import { minimizeTradeRoomBroadcastStudioForBrowsing } from "@/lib/livekit/client/tradeRoomBroadcastStudioNavigation.ts"
import { useTradeRoomBroadcast } from "./useTradeRoomBroadcast.ts"
import { useTradeRoomLiveVoice } from "./useTradeRoomLiveVoice.ts"
import TradeRoomBroadcastGlobalChrome from "./TradeRoomBroadcastGlobalChrome.tsx"

export default function TradeRoomBroadcastGlobalChromeHost() {
  const [accessToken, setAccessToken] = useState<string | null>(null)
  const pathname = usePathname()
  const pathnameRef = useRef(pathname)
  const broadcast = useTradeRoomBroadcast()
  const voice = useTradeRoomLiveVoice()

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => {
      setAccessToken(data.session?.access_token ?? null)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      setAccessToken(session?.access_token ?? null)
    })
    return () => sub.subscription.unsubscribe()
  }, [])

  /** Full studio → mini on route change so LiveKit/audio persist like General Voice. */
  useEffect(() => {
    const pathChanged = pathnameRef.current !== pathname
    pathnameRef.current = pathname
    if (!pathChanged) return

    const watchingAsViewer =
      broadcast.isWatching &&
      (broadcast.role === "viewer" || broadcast.role === "conversation")
    const hostingAsBroadcaster =
      broadcast.isPublishing && broadcast.role === "broadcaster"

    if (!watchingAsViewer && !hostingAsBroadcaster) return
    if (broadcast.studioPresentation !== "studio") return

    minimizeTradeRoomBroadcastStudioForBrowsing()
  }, [
    pathname,
    broadcast.isWatching,
    broadcast.isPublishing,
    broadcast.role,
    broadcast.studioPresentation,
  ])

  return (
    <TradeRoomBroadcastGlobalChrome
      accessToken={accessToken}
      voiceSessionActive={Boolean(voice.session)}
    />
  )
}
