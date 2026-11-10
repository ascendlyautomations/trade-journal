"use client"

import { useEffect, useRef, useState, useSyncExternalStore } from "react"
import { useSupabaseApiAccessToken } from "@/lib/useSupabaseApiAccessToken"
import { useIsNativeIos } from "@/lib/useIsNativeIos"
import { useMaxMdViewport } from "@/lib/useMaxMdViewport"
import {
  getTradeRoomMobileSessionChromeEmbeddedRoomId,
  setTradeRoomMobileSessionChromeBottomInset,
  subscribeTradeRoomMobileSessionChrome,
} from "@/lib/tradeRoomMobileSessionChrome"
import { useTradeRoomBroadcast } from "@/app/components/tradeRooms/live/useTradeRoomBroadcast"
import { useTradeRoomLiveVoice } from "@/app/components/tradeRooms/live/useTradeRoomLiveVoice"
import { tradeRoomBroadcastGlobalChromeVisible } from "@/lib/livekit/client/tradeRoomBroadcastGlobalChromeVisibility"
import TradeRoomMobileSessionChromeStack from "./TradeRoomMobileSessionChromeStack"

/**
 * Fixed session chrome flush above the phone tab bar (mobile web only).
 */
export default function TradeRoomMobileTabShellSessionChromeHost() {
  const nativeIos = useIsNativeIos()
  const maxMd = useMaxMdViewport()
  const embeddedRoomId = useSyncExternalStore(
    subscribeTradeRoomMobileSessionChrome,
    getTradeRoomMobileSessionChromeEmbeddedRoomId,
    () => null
  )
  const voice = useTradeRoomLiveVoice()
  const broadcast = useTradeRoomBroadcast()
  const accessToken = useSupabaseApiAccessToken()
  const shellRef = useRef<HTMLDivElement>(null)

  const broadcastChrome =
    tradeRoomBroadcastGlobalChromeVisible(broadcast) &&
    broadcast.studioPresentation !== "studio"

  const showVoiceShell = Boolean(voice.session?.roomId)
  const showBroadcastShell = broadcastChrome
  /** iOS: tab-shell accessory hidden while room conversation embeds session chrome. */
  const showShell =
    maxMd &&
    !nativeIos &&
    !embeddedRoomId &&
    (showVoiceShell || showBroadcastShell)

  useEffect(() => {
    if (!showShell) {
      setTradeRoomMobileSessionChromeBottomInset(0)
      return
    }
    const el = shellRef.current
    if (!el) return

    const measure = () => {
      setTradeRoomMobileSessionChromeBottomInset(el.offsetHeight)
    }
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(el)
    return () => {
      ro.disconnect()
      setTradeRoomMobileSessionChromeBottomInset(0)
    }
  }, [showShell])

  if (!showShell) return null

  return (
    <div
      ref={shellRef}
      className="pointer-events-auto fixed inset-x-0 z-[9985] max-md:bottom-[var(--app-tab-bar-offset,env(safe-area-inset-bottom,0px))] md:hidden"
      data-tt-mobile-tab-shell-session-chrome
    >
      <TradeRoomMobileSessionChromeStack
        placement="shell"
        accessToken={accessToken}
      />
    </div>
  )
}
