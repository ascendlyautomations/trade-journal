"use client"

import { supabase } from "./supabaseClient"
import {
  parseBillingEntitlementResponse,
  type BillingEntitlementSnapshot,
  type BillingEntitlementStatus,
} from "./billingEntitlement"

export type BillingEntitlementClientState = {
  userId: string | null
  status: BillingEntitlementStatus
  snapshot: BillingEntitlementSnapshot | null
  errorMessage: string | null
}

type Listener = () => void

const listeners = new Set<Listener>()
let generation = 0
let inflight: { userId: string; promise: Promise<BillingEntitlementClientState> } | null =
  null
let state: BillingEntitlementClientState = {
  userId: null,
  status: "idle",
  snapshot: null,
  errorMessage: null,
}

function emit() {
  for (const listener of listeners) listener()
}

function setState(next: BillingEntitlementClientState) {
  state = next
  emit()
}

export function getBillingEntitlementState(): BillingEntitlementClientState {
  return state
}

export function subscribeBillingEntitlement(listener: Listener): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

export function clearBillingEntitlementState() {
  generation += 1
  inflight = null
  setState({
    userId: null,
    status: "idle",
    snapshot: null,
    errorMessage: null,
  })
}

async function requestSnapshot(): Promise<BillingEntitlementSnapshot> {
  const {
    data: { session },
  } = await supabase.auth.getSession()
  const token = session?.access_token
  if (!token) {
    throw new Error("Missing session")
  }
  const response = await fetch("/api/billing/entitlement", {
    method: "GET",
    headers: { Authorization: `Bearer ${token}` },
    cache: "no-store",
  })
  if (!response.ok) {
    throw new Error(`Entitlement request failed (${response.status})`)
  }
  const parsed = parseBillingEntitlementResponse(await response.json())
  if (!parsed) throw new Error("Entitlement response was incomplete")
  return parsed
}

export async function loadBillingEntitlement(
  userId: string,
  options?: { force?: boolean }
): Promise<BillingEntitlementClientState> {
  if (
    !options?.force &&
    state.userId === userId &&
    state.status === "ready" &&
    state.snapshot
  ) {
    return state
  }
  if (!options?.force && inflight?.userId === userId) {
    return inflight.promise
  }

  const requestGeneration = ++generation
  setState({
    userId,
    status: "loading",
    snapshot: state.userId === userId ? state.snapshot : null,
    errorMessage: null,
  })

  const promise = (async () => {
    try {
      const snapshot = await requestSnapshot()
      if (requestGeneration !== generation) return getBillingEntitlementState()
      setState({
        userId,
        status: "ready",
        snapshot,
        errorMessage: null,
      })
    } catch (error) {
      if (requestGeneration !== generation) return getBillingEntitlementState()
      setState({
        userId,
        status: "error",
        snapshot: null,
        errorMessage:
          error instanceof Error ? error.message : "Entitlement request failed",
      })
    } finally {
      if (inflight?.userId === userId && generation === requestGeneration) {
        inflight = null
      }
    }
    return getBillingEntitlementState()
  })()

  inflight = { userId, promise }
  return promise
}
