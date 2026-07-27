"use client"

import { useEffect, useRef } from "react"
import { useRouter } from "next/navigation"
import { useIsNativeIos } from "@/lib/useIsNativeIos"
import { useUserProfile } from "@/lib/UserProfileProvider"
import {
  loginPathWithNext,
  resolveUniversalLinkPath,
} from "@/lib/universalLinks"

/**
 * Capacitor iOS only: handle HTTPS Universal Links
 * (`https://www.tradetraxs.com/...`) opened from Safari, Messages, Mail, etc.
 * OAuth custom-scheme URLs are ignored (NativeIosOAuthListener owns those).
 * Push notification deep links continue via NativeIosPushRegistration.
 */
export default function NativeUniversalLinksListener() {
  const enabled = useIsNativeIos()
  const router = useRouter()
  const { user, loading } = useUserProfile()
  const pendingPathRef = useRef<string | null>(null)
  const handledLaunchRef = useRef(false)

  useEffect(() => {
    if (!enabled) return

    let cancelled = false
    let removeAppUrl: (() => void) | undefined

    const navigateResolved = (rawUrl: string) => {
      if (cancelled) return
      const resolved = resolveUniversalLinkPath(rawUrl)
      if (!resolved || !resolved.supported) return

      // Capacitor already loads the HTTPS URL into the WebView on cold start.
      // Prefer client navigation so we can inject login?next when needed.
      const current =
        typeof window !== "undefined"
          ? `${window.location.pathname}${window.location.search}`
          : ""

      if (resolved.requiresAuth && !loading && !user) {
        const loginPath = loginPathWithNext(resolved.path)
        if (current !== loginPath) router.replace(loginPath)
        pendingPathRef.current = resolved.path
        return
      }

      if (loading && resolved.requiresAuth) {
        pendingPathRef.current = resolved.path
        return
      }

      pendingPathRef.current = null
      if (current === resolved.path) return
      router.replace(resolved.path)
    }

    void (async () => {
      try {
        const { App } = await import("@capacitor/app")

        const appSub = await App.addListener("appUrlOpen", (event) => {
          void navigateResolved(event.url)
        })
        removeAppUrl = () => {
          void appSub.remove()
        }

        if (!handledLaunchRef.current) {
          handledLaunchRef.current = true
          const launch = await App.getLaunchUrl()
          if (launch?.url) {
            void navigateResolved(launch.url)
          }
        }
      } catch {
        // Plugin unavailable — no-op.
      }
    })()

    return () => {
      cancelled = true
      removeAppUrl?.()
    }
  }, [enabled, router, user, loading])

  // Resume pending Universal Link destination after auth finishes.
  useEffect(() => {
    if (!enabled || loading || !user) return
    const pending = pendingPathRef.current
    if (!pending) return
    pendingPathRef.current = null
    const current = `${window.location.pathname}${window.location.search}`
    if (current === pending) return
    router.replace(pending)
  }, [enabled, user, loading, router])

  return null
}
