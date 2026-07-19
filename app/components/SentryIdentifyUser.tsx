"use client"

import { useEffect, useRef } from "react"
import { useUserProfile } from "@/lib/useUserProfile"

/** Attach Supabase user id to Sentry events when a session exists. */
export default function SentryIdentifyUser() {
  const { user } = useUserProfile()
  const identifiedUserRef = useRef(false)

  useEffect(() => {
    const userId = user?.id
    if (typeof userId === "string" && userId.trim()) {
      identifiedUserRef.current = true
      void import("@sentry/nextjs").then((Sentry) => {
        Sentry.setUser({ id: userId })
      })
      return
    }
    if (!identifiedUserRef.current) return
    identifiedUserRef.current = false
    void import("@sentry/nextjs").then((Sentry) => {
      Sentry.setUser(null)
    })
  }, [user?.id])

  return null
}
