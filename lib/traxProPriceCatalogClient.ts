"use client"

import { useCallback, useSyncExternalStore } from "react"
import type { TraxProBillingIntervalId } from "@/lib/traxProBillingPlans"
import {
  traxProPostTrialFootnote,
  traxProTrialPresentation,
  type TraxProDisplayedPlan,
  type TraxProPriceCatalog,
} from "@/lib/traxProPriceCatalog"

export type TraxProPriceCatalogStatus = "idle" | "loading" | "ready" | "error"

type ClientState = {
  status: TraxProPriceCatalogStatus
  catalog: TraxProPriceCatalog | null
  errorMessage: string | null
}

let state: ClientState = {
  status: "idle",
  catalog: null,
  errorMessage: null,
}
let inflight: Promise<void> | null = null
const listeners = new Set<() => void>()

function emit() {
  for (const listener of listeners) listener()
}

function setState(next: ClientState) {
  state = next
  emit()
}

export function getTraxProPriceCatalogState(): ClientState {
  return state
}

export function subscribeTraxProPriceCatalog(listener: () => void) {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export function loadTraxProPriceCatalog() {
  if (inflight) return inflight
  if (state.status === "ready" && state.catalog) return Promise.resolve()
  setState({
    status: "loading",
    catalog: state.catalog,
    errorMessage: null,
  })
  const request = fetchCatalog().finally(() => {
    if (inflight === request) inflight = null
  })
  inflight = request
  return request
}

async function fetchCatalog() {
  try {
    const response = await fetch("/api/billing/prices")
    const body = (await response.json()) as {
      ok?: boolean
      trialDays?: number | null
      plans?: TraxProDisplayedPlan[]
      unavailable?: TraxProPriceCatalog["unavailable"]
      error?: string
    }
    if (!response.ok || body.ok !== true || !Array.isArray(body.plans)) {
      setState({
        status: "error",
        catalog: null,
        errorMessage: body.error ?? "Couldn't load Stripe plans right now.",
      })
      return
    }
    setState({
      status: "ready",
      catalog: {
        trialDays: typeof body.trialDays === "number" ? body.trialDays : null,
        plans: body.plans,
        unavailable: Array.isArray(body.unavailable) ? body.unavailable : [],
      },
      errorMessage: null,
    })
  } catch {
    setState({
      status: "error",
      catalog: null,
      errorMessage: "Couldn't load Stripe plans right now.",
    })
  }
}

export function useTraxProPriceCatalog() {
  const snapshot = useSyncExternalStore(
    subscribeTraxProPriceCatalog,
    getTraxProPriceCatalogState,
    getTraxProPriceCatalogState
  )
  const refresh = useCallback(() => {
    state = { status: "idle", catalog: null, errorMessage: null }
    return loadTraxProPriceCatalog()
  }, [])
  const plan = useCallback(
    (interval: TraxProBillingIntervalId) => {
      if (interval === "test") return null
      return snapshot.catalog?.plans.find((item) => item.interval === interval) ?? null
    },
    [snapshot.catalog]
  )
  return {
    status: snapshot.status,
    catalog: snapshot.catalog,
    errorMessage: snapshot.errorMessage,
    plan,
    refresh,
    pricesReady: snapshot.status === "ready" && (snapshot.catalog?.plans.length ?? 0) > 0,
  }
}

export function useTraxProPurchaseCopy(trialEligible: boolean) {
  const catalog = useTraxProPriceCatalog()
  const trialDays = trialEligible ? (catalog.catalog?.trialDays ?? null) : null
  const presentation =
    catalog.status === "ready"
      ? traxProTrialPresentation(trialDays)
      : null
  return {
    ...catalog,
    trialDays: catalog.status === "ready" ? trialDays : null,
    buttonTitle:
      catalog.status === "error"
        ? "Couldn't load plans"
        : presentation?.buttonTitle ?? "Loading plans…",
    headline: presentation?.headline ?? null,
    heroLine: presentation?.heroLine ?? null,
    finePrint: presentation?.finePrint ?? null,
    offerSummary: presentation?.offerSummary ?? null,
    postTrialFootnote: (interval: TraxProBillingIntervalId) =>
      traxProPostTrialFootnote(catalog.plan(interval), trialDays),
    purchaseDisabled: catalog.status !== "ready",
  }
}
