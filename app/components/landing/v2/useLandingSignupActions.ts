"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { useFeedbackPopup } from "@/app/components/ui/useFeedbackPopup"
import { isBetaReferralRef } from "@/lib/betaReferralCode"
import { isAuthenticatedAppUser } from "@/lib/marketingAccess"
import {
  isGuestExploreViewer,
  resumeGuestExploreNavigation,
} from "@/lib/guestExplore"
import { profileNeedsOnboarding } from "@/lib/profileOnboardingGate"
import {
  clearSignupFlow,
  enterSignupFlow,
  getCheckoutBillingInterval,
  resolveSignupProfileSetupPath,
  setCheckoutBillingInterval,
} from "@/lib/signupFlow"
import { startTraxProCheckout } from "@/lib/startTraxProCheckout"
import {
  hasActiveMembership,
  isSubscriptionGateSuspended,
  needsSubscriptionCheckout,
} from "@/lib/subscriptionAccess"
import type { TraxProBillingIntervalId } from "@/lib/traxProBillingPlans"
import { profileHasUsedCheckoutTrial } from "@/lib/checkoutTrial"
import { useTraxProPurchaseCopy } from "@/lib/traxProPriceCatalogClient"
import { useUserProfile } from "@/lib/useUserProfile"

export function useLandingSignupActions() {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const router = useRouter()
  const { user, profile, loading, membershipReconciling } = useUserProfile()
  const [checkoutLoading, setCheckoutLoading] = useState(false)
  const [loggedInDemoModalOpen, setLoggedInDemoModalOpen] = useState(false)
  const [loggedInTrialModalOpen, setLoggedInTrialModalOpen] = useState(false)

  const isAuthenticatedUser = isAuthenticatedAppUser(user)
  const hasActiveMembershipAccess =
    isAuthenticatedUser && !!profile && hasActiveMembership(profile)
  useTraxProPurchaseCopy(!profileHasUsedCheckoutTrial(profile))
  const trialCtaLabel = "Start Free"

  useEffect(() => {
    if (hasActiveMembershipAccess) clearSignupFlow()
  }, [hasActiveMembershipAccess])

  useEffect(() => {
    if (loading || !isAuthenticatedUser) return
    if (isSubscriptionGateSuspended(user.id, { membershipReconciling })) return
    if (profile && profileNeedsOnboarding(profile)) {
      router.replace(resolveSignupProfileSetupPath())
      return
    }
    if (profile && needsSubscriptionCheckout(profile)) {
      router.replace("/dashboard")
    }
  }, [loading, isAuthenticatedUser, user?.id, profile, router, membershipReconciling])

  useEffect(() => {
    if (typeof window === "undefined") return

    const runReferralCheckout = async () => {
      const params = new URLSearchParams(window.location.search)
      const ref = params.get("ref")
      if (!ref || isBetaReferralRef(ref)) return
      if (!user?.id || isGuestExploreViewer(user)) return

      void startTraxProCheckout()
        .then((url) => {
          window.location.href = url
        })
        .catch((err) => {
          console.error("Referral checkout error:", err)
          showPopup({
            type: "error",
            message: "Checkout failed. Please try again.",
          })
        })
    }

    void runReferralCheckout()
  }, [user?.id, showPopup])

  function handleExploreDemo() {
    if (isGuestExploreViewer(user)) {
      resumeGuestExploreNavigation()
      return
    }
    if (isAuthenticatedUser) {
      setLoggedInDemoModalOpen(true)
      return
    }
    router.push("/demo")
  }

  const handleStartTrial = () => {
    if (isAuthenticatedUser) {
      if (profile && hasActiveMembership(profile)) {
        setLoggedInTrialModalOpen(true)
        return
      }
      if (profile && profileNeedsOnboarding(profile)) {
        router.push(resolveSignupProfileSetupPath())
        return
      }
      router.push("/dashboard")
      return
    }

    const qs = new URLSearchParams(window.location.search)
    const ref = qs.get("ref")
    const next = new URLSearchParams({ tab: "signup" })
    if (ref) next.set("ref", ref)
    enterSignupFlow()
    router.push(`/login?${next.toString()}`)
  }

  const handleSubscribe = async (billingInterval?: TraxProBillingIntervalId) => {
    const interval = billingInterval ?? getCheckoutBillingInterval()
    setCheckoutBillingInterval(interval)
    setCheckoutLoading(true)
    try {
      if (!user?.id) {
        handleStartTrial()
        return
      }
      if (profile && hasActiveMembership(profile)) {
        setLoggedInTrialModalOpen(true)
        return
      }
      if (profile && profileNeedsOnboarding(profile)) {
        router.push(resolveSignupProfileSetupPath())
        return
      }
      const url = await startTraxProCheckout({ billingInterval: interval })
      window.location.href = url
    } catch (err) {
      console.error("Checkout error:", err)
      showPopup({
        type: "error",
        message: "Checkout failed. Please try again.",
      })
    } finally {
      setCheckoutLoading(false)
    }
  }

  function handleStartFreePlan() {
    enterSignupFlow()
    router.push("/login?tab=signup")
  }

  return {
    checkoutLoading,
    loading,
    trialCtaLabel,
    feedbackModalProps,
    loggedInDemoModalOpen,
    setLoggedInDemoModalOpen,
    loggedInTrialModalOpen,
    setLoggedInTrialModalOpen,
    handleStartTrial,
    handleExploreDemo,
    handleSubscribe,
    handleStartFreePlan,
    router,
  }
}
