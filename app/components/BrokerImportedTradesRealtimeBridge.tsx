"use client"

import { useUserProfile } from "@/lib/UserProfileProvider"
import { useBrokerImportedTradesRealtime } from "@/lib/useBrokerImportedTradesRealtime"

/** Subscribes to server-created Tradovate trades and refreshes app trade cache. */
export default function BrokerImportedTradesRealtimeBridge() {
  const { user } = useUserProfile()
  useBrokerImportedTradesRealtime(user?.id)
  return null
}
