"use client"

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react"
import { useRouter } from "next/navigation"
import Modal from "@/app/components/ui/Modal"
import { buttonVariants, cn } from "@/app/components/ui"
import TraxProBillingIntervalPicker, {
  TRAXPRO_DEFAULT_BILLING_INTERVAL,
} from "@/app/components/TraxProBillingIntervalPicker"
import { useUserProfile } from "@/lib/useUserProfile"
import {
  MONETIZATION_FLAGS_FAIL_CLOSED,
  type EffectiveMonetizationFlags,
} from "@/lib/monetizationConfig"
import {
  fetchMonetizationFlags,
  readCachedMonetizationFlags,
} from "@/lib/monetizationClient"
import {
  canPresentProPaywall,
  shouldGateProFeature,
} from "@/lib/proMonetizationPolicy"
import {
  TRADETRAXS_PRO_DISPLAY_NAME,
  type ProGateReason,
  parseProLimitPayload,
  proGateSubtitle,
} from "@/lib/proGateReason"
import {
  isSafeAutomaticRetry,
  safeRetryForProGateReason,
  type ProUpgradeRetryAction,
} from "@/lib/proUpgradeContinuation"
import {
  markStripeReconciliationPending,
  subscribeStripeReconciliationComplete,
} from "@/lib/stripeReconciliation"
import { supabase } from "@/lib/supabaseClient"
import { syncMembershipAfterStripeCheckout } from "@/lib/syncMembershipAfterStripeCheckout"
import { isProActive } from "@/lib/subscription"
import { pickUserProfileFields } from "@/lib/UserProfileProvider"
import { logMonetizationFunnel } from "@/lib/monetizationTelemetry"
import { startTraxProCheckout } from "@/lib/startTraxProCheckout"
import { profileHasUsedCheckoutTrial } from "@/lib/checkoutTrial"
import { TRAXPRO_TRIAL_HEADLINE } from "@/lib/traxProPricing"

type PresentInput = {
  reason: ProGateReason
  retry?: ProUpgradeRetryAction
}

type ProUpgradeContextValue = {
  flags: EffectiveMonetizationFlags
  refreshFlags: () => Promise<void>
  shouldGateProFeature: (isPro: boolean) => boolean
  canPresentPaywall: boolean
  presentProUpgrade: (input: PresentInput) => boolean
  handleSupabaseLimitError: (error: unknown) => boolean
}

const ProUpgradeContext = createContext<ProUpgradeContextValue | null>(null)

export function ProUpgradeProvider({ children }: { children: ReactNode }) {
  const router = useRouter()
  const { user, profile, refreshProfile } = useUserProfile()
  const reasonRef = useRef<ProGateReason | null>(null)
  const retryRef = useRef<ProUpgradeRetryAction | null>(null)
  const [flags, setFlags] = useState<EffectiveMonetizationFlags>(() => ({
    ...MONETIZATION_FLAGS_FAIL_CLOSED,
  }))
  const [open, setOpen] = useState(false)
  const [reason, setReason] = useState<ProGateReason | null>(null)
  const [retry, setRetry] = useState<ProUpgradeRetryAction | null>(null)
  const [billingInterval, setBillingInterval] = useState(
    TRAXPRO_DEFAULT_BILLING_INTERVAL
  )
  const [checkoutLoading, setCheckoutLoading] = useState(false)
  const [checkoutError, setCheckoutError] = useState<string | null>(null)

  const refreshFlags = useCallback(async () => {
    if (!user?.id) {
      setFlags({ ...MONETIZATION_FLAGS_FAIL_CLOSED })
      return
    }
    const next = await fetchMonetizationFlags(user.id)
    setFlags(next)
  }, [user?.id])

  useEffect(() => {
    if (!user?.id) {
      setFlags({ ...MONETIZATION_FLAGS_FAIL_CLOSED })
      return
    }
    const cached = readCachedMonetizationFlags(user.id)
    if (cached) setFlags(cached)
    void refreshFlags()
  }, [user?.id, refreshFlags])

  const canPresentPaywall = canPresentProPaywall("web", flags)

  const gateProFeature = useCallback(
    (isPro: boolean) => shouldGateProFeature(isPro, flags),
    [flags]
  )

  useEffect(() => {
    reasonRef.current = reason
  }, [reason])

  useEffect(() => {
    retryRef.current = retry
  }, [retry])

  useEffect(() => {
    const userId = user?.id
    if (!userId) return
    return subscribeStripeReconciliationComplete(() => {
      void (async () => {
        const synced = await syncMembershipAfterStripeCheckout(
          supabase,
          userId,
          { pickProfile: pickUserProfileFields }
        )
        if (!synced.reconciled || !isProActive(synced.profile)) return
        await refreshProfile()
        logMonetizationFunnel({
          event: "entitlement_confirmed",
          platform: "web",
          reason: reasonRef.current ?? undefined,
          trialEligible: !profileHasUsedCheckoutTrial(synced.profile),
        })
        const pendingReason = reasonRef.current
        const pendingRetry =
          retryRef.current ??
          (pendingReason ? safeRetryForProGateReason(pendingReason) : null)
        setOpen(false)
        setReason(null)
        setRetry(null)
        if (pendingRetry && isSafeAutomaticRetry(pendingRetry)) {
          if (pendingRetry.kind === "open_route") {
            router.push(pendingRetry.path)
          }
        }
      })()
    })
  }, [user?.id, refreshProfile, router])

  const presentProUpgrade = useCallback(
    (input: PresentInput): boolean => {
      if (!canPresentPaywall) return false
      const autoRetry =
        input.retry ?? safeRetryForProGateReason(input.reason)
      setReason(input.reason)
      setRetry(autoRetry.kind === "none" ? null : autoRetry)
      setCheckoutError(null)
      setOpen(true)
      logMonetizationFunnel({
        event: "pro_gate_presented",
        platform: "web",
        reason: input.reason,
        trialEligible: !profileHasUsedCheckoutTrial(profile),
      })
      if (!profileHasUsedCheckoutTrial(profile)) {
        logMonetizationFunnel({
          event: "trial_eligible",
          platform: "web",
          reason: input.reason,
          trialEligible: true,
        })
      }
      return true
    },
    [canPresentPaywall, profile]
  )

  const handleSupabaseLimitError = useCallback(
    (error: unknown): boolean => {
      const payload = parseProLimitPayload(error)
      if (!payload) return false
      return presentProUpgrade({
        reason: { type: "limit", limit: payload.limit },
      })
    },
    [presentProUpgrade]
  )

  const trialEligible = !profileHasUsedCheckoutTrial(profile)
  const primaryCta = trialEligible
    ? TRAXPRO_TRIAL_HEADLINE
    : `Subscribe to ${TRADETRAXS_PRO_DISPLAY_NAME}`

  const startCheckout = async () => {
    if (!canPresentPaywall) return
    setCheckoutLoading(true)
    setCheckoutError(null)
    logMonetizationFunnel({
      event: "purchase_started",
      platform: "web",
      reason: reason ?? undefined,
      trialEligible,
    })
    try {
      if (user?.id) {
        markStripeReconciliationPending(user.id)
      }
      const url = await startTraxProCheckout({ billingInterval })
      logMonetizationFunnel({
        event: "purchase_verified",
        platform: "web",
        detail: "checkout_redirect",
      })
      window.location.assign(url)
    } catch (err) {
      setCheckoutError(
        err instanceof Error ? err.message : "Checkout could not be started."
      )
      logMonetizationFunnel({
        event: "purchase_failed",
        platform: "web",
        detail: err instanceof Error ? err.message : "unknown",
      })
    } finally {
      setCheckoutLoading(false)
    }
  }

  const value = useMemo<ProUpgradeContextValue>(
    () => ({
      flags,
      refreshFlags,
      shouldGateProFeature: gateProFeature,
      canPresentPaywall,
      presentProUpgrade,
      handleSupabaseLimitError,
    }),
    [
      flags,
      refreshFlags,
      gateProFeature,
      canPresentPaywall,
      presentProUpgrade,
      handleSupabaseLimitError,
    ]
  )

  return (
    <ProUpgradeContext.Provider value={value}>
      {children}
      <Modal
        open={open}
        onClose={() => setOpen(false)}
        size="md"
        panelClassName="border border-white/10 bg-[#0b1f3a] p-6 text-gray-100"
      >
        <h2 className="text-xl font-semibold text-white">
          Upgrade to {TRADETRAXS_PRO_DISPLAY_NAME}
        </h2>
        {reason ? (
          <p className="mt-2 text-sm text-gray-300">{proGateSubtitle(reason)}</p>
        ) : null}
        <div className="mt-5">
          <TraxProBillingIntervalPicker
            value={billingInterval}
            onChange={setBillingInterval}
          />
        </div>
        {checkoutError ? (
          <p className="mt-3 text-sm text-red-300">{checkoutError}</p>
        ) : null}
        <div className="mt-6 flex flex-col gap-2">
          <button
            type="button"
            disabled={checkoutLoading || !canPresentPaywall}
            className={cn(
              buttonVariants({ variant: "primary", size: "md" }),
              "w-full justify-center"
            )}
            onClick={() => void startCheckout()}
          >
            {checkoutLoading ? "Starting checkout…" : primaryCta}
          </button>
          <button
            type="button"
            className={cn(
              buttonVariants({ variant: "secondary", size: "md" }),
              "w-full justify-center"
            )}
            onClick={() => setOpen(false)}
          >
            Not now
          </button>
        </div>
      </Modal>
    </ProUpgradeContext.Provider>
  )
}

export function useProUpgrade(): ProUpgradeContextValue {
  const ctx = useContext(ProUpgradeContext)
  if (!ctx) {
    throw new Error("useProUpgrade must be used within ProUpgradeProvider")
  }
  return ctx
}

/** Safe when provider is optional (marketing pages). */
export function useProUpgradeOptional(): ProUpgradeContextValue | null {
  return useContext(ProUpgradeContext)
}
