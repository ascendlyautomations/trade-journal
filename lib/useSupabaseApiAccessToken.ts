"use client"

import { useEffect, useState } from "react"
import { getSupabaseApiAccessToken } from "@/lib/supabaseBearerFetch"
import { supabase } from "@/lib/supabaseClient"

/**
 * Member-authenticated API access token, or null for signed-out / guest explore.
 * Refreshes when auth state changes; validates via `getUser` (not cache-only `getSession`).
 */
export function useSupabaseApiAccessToken(): string | null {
  const [token, setToken] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false

    const sync = async () => {
      const next = await getSupabaseApiAccessToken()
      if (!cancelled) setToken(next)
    }

    void sync()

    const { data: sub } = supabase.auth.onAuthStateChange(() => {
      void sync()
    })

    return () => {
      cancelled = true
      sub.subscription.unsubscribe()
    }
  }, [])

  return token
}
