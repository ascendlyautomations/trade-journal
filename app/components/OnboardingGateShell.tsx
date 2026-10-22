"use client"

import { useEffect } from "react"
import { usePathname, useRouter } from "next/navigation"
import { useUserProfile } from "@/lib/useUserProfile"
import {
  isAllowedPathDuringOnboarding,
  profileNeedsOnboarding,
} from "@/lib/profileOnboardingGate"
import { resolveSignupProfileSetupPath } from "@/lib/signupFlow"

/**
 * Redirects users with incomplete profiles to /onboarding.
 * Mirrors BannedAccountShell — one global gate instead of per-page modals.
 */
export default function OnboardingGateShell({
  children,
}: {
  children: React.ReactNode
}) {
  const pathname = usePathname()
  const router = useRouter()
  const { user, profile, loading } = useUserProfile()

  useEffect(() => {
    if (loading) return
    if (!user) return
    if (profile?.is_banned) return
    // Missing profile = still hydrating or a fetch failure — never treat a valid
    // session as "needs onboarding" (that bounced users off /dashboard after login).
    if (!profile) return

    const needsOnboarding = profileNeedsOnboarding(profile)

    if (needsOnboarding) {
      if (isAllowedPathDuringOnboarding(pathname)) return
      router.replace(resolveSignupProfileSetupPath())
      return
    }

    if (pathname === "/onboarding" || pathname.startsWith("/onboarding/")) {
      router.replace("/dashboard")
    }
  }, [loading, user, profile, pathname, router])

  return <>{children}</>
}
