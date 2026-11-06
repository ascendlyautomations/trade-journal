"use client"

import { useEffect, useState } from "react"
import { supabase } from "@/lib/supabaseClient.ts"
import TradeRoomBroadcastGlobalChrome from "./TradeRoomBroadcastGlobalChrome.tsx"

export default function TradeRoomBroadcastGlobalChromeHost() {
  const [accessToken, setAccessToken] = useState<string | null>(null)

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => {
      setAccessToken(data.session?.access_token ?? null)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      setAccessToken(session?.access_token ?? null)
    })
    return () => sub.subscription.unsubscribe()
  }, [])

  return <TradeRoomBroadcastGlobalChrome accessToken={accessToken} />
}
