"use client"

import { useEffect, useRef, useSyncExternalStore } from "react"
import { usePathname } from "next/navigation"
import { useSupabaseApiAccessToken } from "@/lib/useSupabaseApiAccessToken"
import { minimizeTradeRoomBroadcastStudioForBrowsing } from "@/lib/livekit/client/tradeRoomBroadcastStudioNavigation.ts"
import {
  getTradeRoomMobileSessionChromeEmbeddedRoomId,
  subscribeTradeRoomMobileSessionChrome,
} from "@/lib/tradeRoomMobileSessionChrome.ts"
import { tradeRoomBroadcastGlobalChromeVisible } from "@/lib/livekit/client/tradeRoomBroadcastGlobalChromeVisibility.ts"
import { useIsNativeIos } from "@/lib/useIsNativeIos"
import { useMaxMdViewport } from "@/lib/useMaxMdViewport"
import { useTradeRoomBroadcast } from "./useTradeRoomBroadcast.ts"
import { useTradeRoomLiveVoice } from "./useTradeRoomLiveVoice.ts"
import TradeRoomBroadcastGlobalChrome from "./TradeRoomBroadcastGlobalChrome.tsx"

export default function TradeRoomBroadcastGlobalChromeHost() {
  const accessToken = useSupabaseApiAccessToken()
  const pathname = usePathname()
  const pathnameRef = useRef(pathname)
  const broadcast = useTradeRoomBroadcast()
  const voice = useTradeRoomLiveVoice()
  const maxMd = useMaxMdViewport()
  const nativeIos = useIsNativeIos()
  const embeddedRoomId = useSyncExternalStore(
    subscribeTradeRoomMobileSessionChrome,
    getTradeRoomMobileSessionChromeEmbeddedRoomId,
    () => null
  )
  const chromeActive = tradeRoomBroadcastGlobalChromeVisible(broadcast)
  const suppressForEmbeddedBar =
    Boolean(embeddedRoomId) && broadcast.studioPresentation !== "studio"
  const mobileUsesPersistentBar =
    maxMd && !nativeIos && chromeActive && broadcast.studioPresentation !== "studio"

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

  if (suppressForEmbeddedBar || mobileUsesPersistentBar) {
    return null
  }

  return (
    <TradeRoomBroadcastGlobalChrome
      accessToken={accessToken}
      voiceSessionActive={Boolean(voice.session)}
    />
  )
}
