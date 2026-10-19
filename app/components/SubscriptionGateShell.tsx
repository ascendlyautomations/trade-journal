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
import { useBillingEntitlement } from "@/app/components/monetization/BillingEntitlementProvider"
import EntitlementStatusNotice from "@/app/components/monetization/EntitlementStatusNotice"
import {
  buildCreatorRedeemPath,
  getPendingCreatorCode,
} from "@/lib/creatorAccess"

/**
 * Blocks app access until standard users complete Stripe checkout.
 * An indeterminate entitlement snapshot does not redirect to finish-trial.
 */
export default function SubscriptionGateShell({
  children,
}: {
  children: React.ReactNode
}) {
  const pathname = usePathname()
  const router = useRouter()
  const { user, profile, loading, membershipReconciling } = useUserProfile()
  const billing = useBillingEntitlement()
  const suspended = user
    ? isSubscriptionGateSuspended(user.id, { membershipReconciling })
    : false
  const consultEntitlement =
    !loading &&
    Boolean(user) &&
    !profile?.is_banned &&
    !suspended &&
    needsSubscriptionCheckout(profile) &&
    !isAllowedPathWithoutSubscription(pathname)

  useEffect(() => {
    if (!consultEntitlement) return
    if (billing.status !== "ready") return
    if (
      !shouldOfferStripeCheckout({
        profileNeedsCheckout: true,
        serverTraxProActive: billing.snapshot?.traxProActive ?? null,
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
  }, [
    consultEntitlement,
    billing.status,
    billing.snapshot?.traxProActive,
    router,
  ])

  if (consultEntitlement && billing.status === "error") {
    return (
      <div className="flex min-h-screen items-center justify-center bg-[#0b1f3a] px-4">
        <EntitlementStatusNotice
          status="error"
          onRetry={() => void billing.refresh()}
          className="max-w-md"
        />
      </div>
    )
  }

  return <>{children}</>
}
