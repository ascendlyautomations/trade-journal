"use client"

import { useEffect, useId, useRef, useState } from "react"
import { supabase } from "./supabaseClient"

export function useUserProfile() {
  const [user, setUser] = useState<any>(null)
  const [profile, setProfile] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  /** Unique per hook instance so Navbar + BannedAccountShell never share one subscribed channel. */
  const realtimeTopicSuffix = useId().replace(/:/g, "")
  const channelRef = useRef<ReturnType<typeof supabase.channel> | null>(null)

  useEffect(() => {
    let mounted = true

    async function init() {
      setLoading(true)

      if (channelRef.current) {
        void supabase.removeChannel(channelRef.current)
        channelRef.current = null
      }

      // ✅ FIX: use getSession instead of getUser (prevents lock error)
      const { data } = await supabase.auth.getSession()
      const sessionUser = data?.session?.user

      if (!mounted) return

      setUser(sessionUser || null)

      if (!sessionUser) {
        if (mounted) setLoading(false)
        return
      }

      const { data: profileData } = await supabase
        .from("profiles")
        .select("*")
        .eq("id", sessionUser.id)
        .single()

      if (!mounted) return

      setProfile(profileData || null)

      // Realtime: create channel → register .on handlers → subscribe() last (required by supabase-js).
      const topic = `profile:${sessionUser.id}:${realtimeTopicSuffix}`
      const ch = supabase.channel(topic)
      channelRef.current = ch

      ch.on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "profiles",
          filter: `id=eq.${sessionUser.id}`,
        },
        (payload) => {
          if (!mounted) return
          setProfile(payload.new)
        }
      )

      if (!mounted) {
        void supabase.removeChannel(ch)
        channelRef.current = null
        return
      }

      ch.subscribe()

      if (mounted) setLoading(false)
    }

    void init()

    return () => {
      mounted = false
      const ch = channelRef.current
      channelRef.current = null
      if (ch) {
        void supabase.removeChannel(ch)
      }
    }
  }, [realtimeTopicSuffix])

  return { user, profile, loading, setProfile }
}