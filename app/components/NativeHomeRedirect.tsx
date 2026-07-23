"use client"

import { useEffect } from "react"
import { usePathname, useRouter } from "next/navigation"
import { isNativePlatform } from "@/lib/nativePlatform"
import { useUserProfile } from "@/lib/useUserProfile"

/**
 * On native only: never stay on the public marketing homepage.
 * Authenticated → /dashboard, otherwise → /login.
 * Web `/` is untouched.
 */
export default function NativeHomeRedirect() {
  const pathname = usePathname()
  const router = useRouter()
  const { user, loading } = useUserProfile()

  useEffect(() => {
    if (!isNativePlatform()) return
    if (pathname !== "/") return
    if (loading) return
    router.replace(user ? "/dashboard" : "/login")
  }, [pathname, user, loading, router])

  return null
}
