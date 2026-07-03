"use client"

import { useEffect, type ReactNode } from "react"
import { usePathname, useRouter } from "next/navigation"
import { isMarketingRoute } from "@/lib/authRoutes"
import { isInAppEntryFlow } from "@/lib/marketingAccess"
import { profileNeedsOnboarding } from "@/lib/profileOnboardingGate"
import {
  isSubscriptionGateSuspended,
  needsSubscriptionCheckout,
  resolvePostAuthAppPath,
} from "@/lib/subscriptionAccess"
import { useUserProfile } from "@/lib/useUserProfile"

/**
 * Keeps authenticated signup-flow users off marketing pages (/ , /faq, /pricing).
 */
export default function MarketingGateShell({ children }: { children: ReactNode }) {
  const pathname = usePathname()
  const router = useRouter()
  const { user, profile, loading, membershipReconciling } = useUserProfile()

  const gateSuspended = isSubscriptionGateSuspended(user?.id, {
    membershipReconciling,
  })
  const onMarketingRoute = isMarketingRoute(pathname)
  const inEntryFlow =
    onMarketingRoute &&
    !gateSuspended &&
    isInAppEntryFlow(user, profile, loading)

  useEffect(() => {
    if (!onMarketingRoute || loading || !user) return
    if (gateSuspended) return

    if (profileNeedsOnboarding(profile ?? {})) {
      router.replace("/onboarding")
      return
    }

    if (needsSubscriptionCheckout(profile)) {
      router.replace("/finish-trial")
      return
    }

    if (isInAppEntryFlow(user, profile, false)) {
      router.replace(resolvePostAuthAppPath(profile))
    }
  }, [onMarketingRoute, loading, user, profile, router, gateSuspended])

  if (inEntryFlow) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-[#0b1f3a] text-gray-300">
        Setting up your account…
      </div>
    )
  }

  return <>{children}</>
}
