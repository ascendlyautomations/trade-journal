"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { useUserProfile } from "@/lib/useUserProfile"
import { useIsNativeIos } from "@/lib/useIsNativeIos"
import { registerNativeIosPush } from "@/lib/nativeIosPush"

/**
 * Capacitor iOS only: request push permission once, register APNs token,
 * and deep-link on notification tap. No-ops on web/Android.
 */
export default function NativeIosPushRegistration() {
  const enabled = useIsNativeIos()
  const { user, loading } = useUserProfile()
  const router = useRouter()

  useEffect(() => {
    if (!enabled) return
    ;(
      window as unknown as { __ttPushNavigate?: (href: string) => void }
    ).__ttPushNavigate = (href: string) => {
      router.push(href)
    }
    return () => {
      delete (window as unknown as { __ttPushNavigate?: (href: string) => void })
        .__ttPushNavigate
    }
  }, [enabled, router])

  useEffect(() => {
    if (!enabled || loading || !user?.id) return
    void registerNativeIosPush()
  }, [enabled, loading, user?.id])

  return null
}
