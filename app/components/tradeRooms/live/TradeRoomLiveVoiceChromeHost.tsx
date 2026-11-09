"use client"

import { useEffect, useState } from "react"
import { supabase } from "@/lib/supabaseClient.ts"
import TradeRoomLiveVoiceSessionGuard from "./TradeRoomLiveVoiceSessionGuard.tsx"
import TradeRoomLiveVoiceBar from "./TradeRoomLiveVoiceBar.tsx"

/** Global web shell: session guard + floating voice UI (same pattern as broadcast chrome). */
export default function TradeRoomLiveVoiceChromeHost() {
  const [userId, setUserId] = useState<string | null>(null)

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => {
      setUserId(data.session?.user?.id ?? null)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      setUserId(session?.user?.id ?? null)
    })
    return () => sub.subscription.unsubscribe()
  }, [])

  return (
    <>
      <TradeRoomLiveVoiceSessionGuard userId={userId} />
      <TradeRoomLiveVoiceBar />
    </>
  )
}
