"use client"

import { useEffect } from "react"
import { usePathname, useRouter } from "next/navigation"
import { useUserProfile } from "@/lib/useUserProfile"

const ALLOWED_WHEN_BANNED_PREFIXES = ["/banned", "/login", "/admin"]

function isAllowedPathWhenBanned(pathname: string) {
  if (ALLOWED_WHEN_BANNED_PREFIXES.some((p) => pathname === p || pathname.startsWith(`${p}/`))) {
    return true
  }
  return false
}

/**
 * Redirects banned accounts away from normal app routes (TradeTrax shell).
 * Admins can still open /admin while banned (edge case).
 */
export default function BannedAccountShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname()
  const router = useRouter()
  const { user, profile, loading } = useUserProfile()

  useEffect(() => {
    if (loading) return
    if (!user || !profile?.is_banned) return
    if (isAllowedPathWhenBanned(pathname)) return
    router.replace("/banned")
  }, [loading, user, profile?.is_banned, pathname, router])

  return <>{children}</>
}
