"use client"

import { useEffect, useState } from "react"
import { supabase } from "./supabaseClient"

export function useUserProfile() {
  const [user, setUser] = useState<any>(null)
  const [profile, setProfile] = useState<any>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let mounted = true
    let channel: any = null

    async function init() {
      setLoading(true)

      // ✅ FIX: use getSession instead of getUser (prevents lock error)
      const { data } = await supabase.auth.getSession()
      const sessionUser = data?.session?.user

      if (!mounted) return

      setUser(sessionUser || null)

      if (sessionUser) {
        const { data: profileData } = await supabase
          .from("profiles")
          .select("*")
          .eq("id", sessionUser.id)
          .single()

        if (mounted) setProfile(profileData || null)

        // ✅ REALTIME SUBSCRIPTION (ONLY ONCE, AFTER USER LOADS)
        channel = supabase
          .channel(`profile-${sessionUser.id}`)
          .on(
            "postgres_changes",
            {
              event: "UPDATE",
              schema: "public",
              table: "profiles",
              filter: `id=eq.${sessionUser.id}`
            },
            (payload) => {
              setProfile(payload.new)
            }
          )
          .subscribe()
      }

      setLoading(false)
    }

    init()

    return () => {
      mounted = false
      if (channel) {
        supabase.removeChannel(channel)
      }
    }
  }, []) // ✅ FIX: no more dependency on user

  return { user, profile, loading, setProfile }
}