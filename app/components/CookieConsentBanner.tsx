"use client"

import Link from "next/link"
import { useEffect, useState } from "react"
import { usePathname } from "next/navigation"
import {
  hasCookieConsentChoice,
  saveCookieConsent,
  type CookieConsentChoice,
} from "@/lib/cookieConsent"
import { isNativeIos } from "@/lib/nativePlatform"
import { useIsNativeIos } from "@/lib/useIsNativeIos"

export default function CookieConsentBanner() {
  const pathname = usePathname()
  const nativeIos = useIsNativeIos()
  // Sync check avoids a one-frame flash before useIsNativeIos hydrates.
  const hideForNativeIos = nativeIos || isNativeIos()
  const [visible, setVisible] = useState(false)
  const isMarketingAdFrame =
    pathname === "/marketing" || Boolean(pathname?.startsWith("/marketing/"))

  useEffect(() => {
    if (hideForNativeIos || isMarketingAdFrame) {
      setVisible(false)
      return
    }
    setVisible(!hasCookieConsentChoice())
  }, [hideForNativeIos, isMarketingAdFrame])

  function handleChoice(choice: CookieConsentChoice) {
    saveCookieConsent(choice)
    setVisible(false)
  }

  if (hideForNativeIos || !visible || isMarketingAdFrame) return null

  return (
    <div
      className="fixed inset-x-0 bottom-0 z-[9990] border-t border-white/10 bg-[#0b1f3a]/95 px-4 py-4 pb-[max(1rem,calc(var(--safe-area-bottom)+var(--app-tab-bar-height)+0.75rem))] text-white shadow-[0_-8px_32px_rgba(0,0,0,0.35)] backdrop-blur-md sm:px-6 sm:pb-4"
      role="dialog"
      aria-labelledby="cookie-consent-title"
      aria-describedby="cookie-consent-description"
    >
      <div className="mx-auto flex w-full max-w-6xl flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div className="min-w-0 text-left">
          <p id="cookie-consent-title" className="text-sm font-semibold text-white">
            🍪 We use cookies
          </p>
          <p
            id="cookie-consent-description"
            className="mt-1 text-xs leading-relaxed text-gray-300 sm:text-sm"
          >
            TradeTraxs uses essential cookies to keep you securely signed in, process
            subscriptions, remember your preferences, and improve your experience.
          </p>
        </div>
        <div className="flex shrink-0 flex-wrap items-center gap-2 sm:justify-end">
          <button
            type="button"
            onClick={() => handleChoice("all")}
            className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600"
          >
            Accept All
          </button>
          <button
            type="button"
            onClick={() => handleChoice("essential")}
            className="rounded-lg border border-white/20 bg-white/10 px-4 py-2 text-sm font-medium text-white transition hover:bg-white/15"
          >
            Essential Only
          </button>
          <Link
            href="/cookie-policy"
            prefetch={false}
            className="rounded-lg px-3 py-2 text-sm font-medium text-blue-300 transition hover:text-blue-200"
          >
            Cookie Policy
          </Link>
        </div>
      </div>
    </div>
  )
}
