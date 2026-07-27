"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { useIsNativeIos } from "@/lib/useIsNativeIos"
import {
  clearNativeIosOAuthStash,
  completeNativeIosOAuthFromUrl,
  NATIVE_IOS_OAUTH_FLOW_ACTIVE_KEY,
} from "@/lib/nativeIosOAuth"

/**
 * Capacitor iOS only: listen for OAuth deep-link return
 * (`com.tradetraxs.ios://auth/callback`) and finish the Supabase session.
 * No-ops on web / Android.
 */
export default function NativeIosOAuthListener() {
  const enabled = useIsNativeIos()
  const router = useRouter()

  useEffect(() => {
    if (!enabled) return

    let cancelled = false
    let removeAppUrl: (() => void) | undefined
    let removeBrowserFinished: (() => void) | undefined

    void (async () => {
      try {
        const { App } = await import("@capacitor/app")
        const { Browser } = await import("@capacitor/browser")

        const handleUrl = async (url: string) => {
          if (cancelled) return
          try {
            const next = await completeNativeIosOAuthFromUrl(url)
            if (!next || cancelled) return
            router.replace(next)
          } catch (err) {
            console.error("[native-ios-oauth] callback failed", err)
            clearNativeIosOAuthStash()
            try {
              await Browser.close()
            } catch {
              /* ignore */
            }
          }
        }

        const appSub = await App.addListener("appUrlOpen", (event) => {
          void handleUrl(event.url)
        })
        removeAppUrl = () => {
          void appSub.remove()
        }

        // User dismissed the auth sheet without completing OAuth.
        // Delay so a successful custom-scheme redirect can claim the stash first.
        const browserSub = await Browser.addListener("browserFinished", () => {
          window.setTimeout(() => {
            try {
              if (
                sessionStorage.getItem(NATIVE_IOS_OAUTH_FLOW_ACTIVE_KEY) === "1"
              ) {
                clearNativeIosOAuthStash()
              }
            } catch {
              /* ignore */
            }
          }, 800)
        })
        removeBrowserFinished = () => {
          void browserSub.remove()
        }

        // Cold start: app may launch directly from the OAuth redirect URL.
        const launch = await App.getLaunchUrl()
        if (launch?.url) {
          void handleUrl(launch.url)
        }
      } catch {
        // Plugins unavailable — leave web OAuth untouched.
      }
    })()

    return () => {
      cancelled = true
      removeAppUrl?.()
      removeBrowserFinished?.()
    }
  }, [enabled, router])

  return null
}
