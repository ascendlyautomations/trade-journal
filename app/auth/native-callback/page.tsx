"use client"

import { useEffect, useMemo, useState } from "react"
import { useSearchParams } from "next/navigation"
import { Suspense } from "react"
import { NATIVE_IOS_OAUTH_SCHEME } from "@/lib/nativeIosOAuthUrls"

/**
 * HTTPS bridge for Capacitor iOS OAuth.
 *
 * Supabase (and SFSafariViewController) reliably land on HTTPS.
 * A direct redirect to a custom URL scheme from Supabase often fails,
 * leaving the user on tradetraxs.com inside the auth popup.
 *
 * This page immediately forwards query + hash to:
 *   com.tradetraxs.ios://auth/callback?...
 * so the Capacitor app receives appUrlOpen and can dismiss the sheet.
 *
 * Web browsers should not normally hit this route; if they do, show a
 * short message with a manual deep-link fallback.
 */
function NativeCallbackInner() {
  const searchParams = useSearchParams()
  const [deepLink, setDeepLink] = useState<string | null>(null)

  const queryString = useMemo(() => {
    const qs = searchParams?.toString() ?? ""
    return qs ? `?${qs}` : ""
  }, [searchParams])

  useEffect(() => {
    const hash =
      typeof window !== "undefined" && window.location.hash
        ? window.location.hash
        : ""
    const target = `${NATIVE_IOS_OAUTH_SCHEME}://auth/callback${queryString}${hash}`
    setDeepLink(target)

    const go = () => {
      try {
        window.location.replace(target)
      } catch {
        window.location.href = target
      }
    }
    go()
    const t1 = window.setTimeout(go, 250)
    const t2 = window.setTimeout(go, 800)
    return () => {
      window.clearTimeout(t1)
      window.clearTimeout(t2)
    }
  }, [queryString])

  return (
    <main className="flex min-h-screen flex-col items-center justify-center bg-[#0b1f3a] px-6 text-center text-white">
      <p className="text-sm text-gray-300">Returning to TradeTraxs…</p>
      {deepLink ? (
        <a
          href={deepLink}
          className="mt-4 text-sm font-medium text-blue-300 underline underline-offset-2"
        >
          Tap here if the app does not open
        </a>
      ) : null}
    </main>
  )
}

export default function NativeAuthCallbackPage() {
  return (
    <Suspense
      fallback={
        <main className="flex min-h-screen items-center justify-center bg-[#0b1f3a] text-sm text-gray-300">
          Returning to TradeTraxs…
        </main>
      }
    >
      <NativeCallbackInner />
    </Suspense>
  )
}
