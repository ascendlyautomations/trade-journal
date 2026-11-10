"use client"

import { useEffect, useState } from "react"
import { supabase } from "@/lib/supabaseClient.ts"
import { useIsNativeIos } from "@/lib/useIsNativeIos"
import { useMaxMdViewport } from "@/lib/useMaxMdViewport"
import TradeRoomLiveVoiceSessionGuard from "./TradeRoomLiveVoiceSessionGuard.tsx"
import TradeRoomLiveVoiceBar from "./TradeRoomLiveVoiceBar.tsx"

/** Global web shell: session guard + floating voice UI (desktop / tablet). */
export default function TradeRoomLiveVoiceChromeHost() {
  const [userId, setUserId] = useState<string | null>(null)
  const maxMd = useMaxMdViewport()
  const nativeIos = useIsNativeIos()

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => {
      setUserId(data.session?.user?.id ?? null)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      setUserId(session?.user?.id ?? null)
    })
    return () => sub.subscription.unsubscribe()
  }, [])

  const useMobileShell = maxMd && !nativeIos

  return (
    <>
      <TradeRoomLiveVoiceSessionGuard userId={userId} />
      {useMobileShell ? null : <TradeRoomLiveVoiceBar placement="fixed" />}
    </>
  )
}
