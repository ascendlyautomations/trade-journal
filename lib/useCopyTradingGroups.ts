"use client"

import { useEffect, useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import {
  fetchCopyTradingGroups,
  type CopyTradingGroup,
} from "@/lib/copyTradingGroups"

export function useCopyTradingGroups(
  userId: string | null | undefined,
  enabled: boolean
): { copyGroups: CopyTradingGroup[]; loading: boolean } {
  const [copyGroups, setCopyGroups] = useState<CopyTradingGroup[]>([])
  const [loading, setLoading] = useState(Boolean(userId && enabled))

  useEffect(() => {
    if (!userId || !enabled) {
      setCopyGroups([])
      setLoading(false)
      return
    }

    let cancelled = false
    setLoading(true)

    void fetchCopyTradingGroups(supabase, userId).then(({ groups, error }) => {
      if (cancelled) return
      if (error) {
        console.error("[useCopyTradingGroups] load failed", error)
        setCopyGroups([])
      } else {
        setCopyGroups(groups)
      }
      setLoading(false)
    })

    return () => {
      cancelled = true
    }
  }, [userId, enabled])

  return { copyGroups, loading }
}
