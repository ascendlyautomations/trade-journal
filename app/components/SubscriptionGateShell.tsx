"use client"

import { useEffect } from "react"
import { usePathname, useRouter } from "next/navigation"
import { useUserProfile } from "@/lib/useUserProfile"
import {
  isAllowedPathWithoutSubscription,
  isSubscriptionGateSuspended,
  needsSubscriptionCheckout,
} from "@/lib/subscriptionAccess"

/**
 * Blocks app access until standard users complete Stripe checkout.
 * Beta, paid, and trialing users pass through unchanged.
 */
export default function SubscriptionGateShell({
  children,
}: {
  children: React.ReactNode
}) {
  const pathname = usePathname()
  const router = useRouter()
  const { user, profile, loading, membershipReconciling } = useUserProfile()

  useEffect(() => {
    if (loading) return
    if (!user) return
    if (profile?.is_banned) return
    if (isSubscriptionGateSuspended(user.id, { membershipReconciling })) return
    if (!needsSubscriptionCheckout(profile)) return
    if (isAllowedPathWithoutSubscription(pathname)) return
    router.replace("/finish-trial")
  }, [loading, user, profile, pathname, router, membershipReconciling])

  return <>{children}</>
}
