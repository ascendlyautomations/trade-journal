"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import {
  MESSAGING_IN_APP_BANNER_EVENT,
  type MessagingInAppBannerDetail,
} from "@/lib/messagingActiveContext"

const AUTO_DISMISS_MS = 4500

/**
 * Lightweight foreground messaging banner (Instagram/Discord-style).
 * Shown when a messaging push arrives while the app is open but the user
 * is not viewing that conversation/room.
 */
export default function MessagingInAppBanner() {
  const router = useRouter()
  const [banner, setBanner] = useState<MessagingInAppBannerDetail | null>(null)

  useEffect(() => {
    function onBanner(event: Event) {
      const custom = event as CustomEvent<MessagingInAppBannerDetail>
      const detail = custom.detail
      if (!detail?.href || !detail.title) return
      setBanner(detail)
    }

    window.addEventListener(MESSAGING_IN_APP_BANNER_EVENT, onBanner)
    return () => {
      window.removeEventListener(MESSAGING_IN_APP_BANNER_EVENT, onBanner)
    }
  }, [])

  useEffect(() => {
    if (!banner) return
    const timer = window.setTimeout(() => setBanner(null), AUTO_DISMISS_MS)
    return () => window.clearTimeout(timer)
  }, [banner])

  if (!banner) return null

  return (
    <button
      type="button"
      onClick={() => {
        const href = banner.href
        setBanner(null)
        if (href.startsWith("/")) router.push(href)
      }}
      className="fixed left-1/2 top-[max(0.75rem,var(--safe-area-top))] z-[10050] w-[min(28rem,calc(100%-1.5rem))] -translate-x-1/2 rounded-2xl border border-white/15 bg-[#12141a]/95 px-4 py-3 text-left shadow-[0_12px_40px_rgba(0,0,0,0.45)] backdrop-blur-md transition hover:bg-[#181b22]"
      aria-label="Open conversation"
    >
      <div className="text-sm font-semibold text-white">{banner.title}</div>
      <div className="mt-0.5 line-clamp-2 text-xs text-white/70">{banner.body}</div>
    </button>
  )
}
