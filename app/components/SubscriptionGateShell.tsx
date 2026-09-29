"use client"

import { useEffect } from "react"
import { usePathname, useRouter } from "next/navigation"
import { useUserProfile } from "@/lib/useUserProfile"
import { shouldOfferStripeCheckout } from "@/lib/monetizationConfig"
import {
  isAllowedPathWithoutSubscription,
  isSubscriptionGateSuspended,
  needsSubscriptionCheckout,
} from "@/lib/subscriptionAccess"
import { fetchServerTraxProActive } from "@/lib/fetchServerTraxProActive"
import {
  buildCreatorRedeemPath,
  getPendingCreatorCode,
} from "@/lib/creatorAccess"

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

    let cancelled = false
    void (async () => {
      const serverTraxProActive = await fetchServerTraxProActive()
      if (cancelled) return
      if (
        !shouldOfferStripeCheckout({
          profileNeedsCheckout: true,
          serverTraxProActive,
        })
      ) {
        return
      }

      const pendingCreatorCode = getPendingCreatorCode()
      if (pendingCreatorCode) {
        router.replace(buildCreatorRedeemPath(pendingCreatorCode))
        return
      }

      router.replace("/finish-trial")
    })()

    return () => {
      cancelled = true
    }
  }, [loading, user, profile, pathname, router, membershipReconciling])

  return <>{children}</>
}
