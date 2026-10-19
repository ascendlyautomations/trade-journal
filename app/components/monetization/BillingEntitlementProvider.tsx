"use client"

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react"
import { useUserProfile } from "@/lib/useUserProfile"
import {
  clearBillingEntitlementState,
  getBillingEntitlementState,
  loadBillingEntitlement,
  subscribeBillingEntitlement,
  type BillingEntitlementClientState,
} from "@/lib/billingEntitlementClient"
import {
  resolveBillingProvider,
  resolveClientProAccess,
  snapshotHasLiveAppleSubscription,
  type BillingProvider,
  type ClientProAccess,
} from "@/lib/billingEntitlement"
import { isProActive } from "@/lib/subscription"

type BillingEntitlementContextValue = BillingEntitlementClientState & {
  access: ClientProAccess
  billingProvider: BillingProvider
  appleSubscriptionLive: boolean
  refresh: () => Promise<void>
}

const BillingEntitlementContext =
  createContext<BillingEntitlementContextValue | null>(null)

export function BillingEntitlementProvider({ children }: { children: ReactNode }) {
  const { user, profile } = useUserProfile()
  const [clientState, setClientState] = useState<BillingEntitlementClientState>(
    getBillingEntitlementState
  )

  useEffect(() => subscribeBillingEntitlement(() => {
    setClientState(getBillingEntitlementState())
  }), [])

  useEffect(() => {
    if (!user?.id) {
      clearBillingEntitlementState()
      return
    }
    void loadBillingEntitlement(user.id)
  }, [user?.id])

  const refresh = useCallback(async () => {
    if (!user?.id) {
      clearBillingEntitlementState()
      return
    }
    await loadBillingEntitlement(user.id, { force: true })
  }, [user?.id])

  const profileIsPro = isProActive(profile)
  const access = resolveClientProAccess({
    signedIn: Boolean(user?.id),
    profileIsPro,
    status: clientState.userId === user?.id ? clientState.status : "idle",
    traxProActive:
      clientState.userId === user?.id
        ? (clientState.snapshot?.traxProActive ?? null)
        : null,
  })
  const snapshot =
    clientState.userId === user?.id ? clientState.snapshot : null
  const status = clientState.userId === user?.id ? clientState.status : "idle"

  const value = useMemo<BillingEntitlementContextValue>(
    () => ({
      userId: user?.id ?? null,
      status,
      snapshot,
      errorMessage: clientState.userId === user?.id ? clientState.errorMessage : null,
      access,
      billingProvider: resolveBillingProvider(snapshot),
      appleSubscriptionLive: snapshotHasLiveAppleSubscription(snapshot),
      refresh,
    }),
    [
      user?.id,
      status,
      snapshot,
      clientState.userId,
      clientState.errorMessage,
      access,
      refresh,
    ]
  )

  return (
    <BillingEntitlementContext.Provider value={value}>
      {children}
    </BillingEntitlementContext.Provider>
  )
}

export function useBillingEntitlement(): BillingEntitlementContextValue {
  const value = useContext(BillingEntitlementContext)
  if (!value) {
    throw new Error("useBillingEntitlement must be used within BillingEntitlementProvider")
  }
  return value
}

export function useBillingEntitlementOptional(): BillingEntitlementContextValue | null {
  return useContext(BillingEntitlementContext)
}
