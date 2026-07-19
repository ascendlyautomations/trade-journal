"use client"

import { supabase } from "@/lib/supabaseClient"
import type {
  EarlyAccessProgress,
  ProForLifeClaimResult,
} from "@/lib/earlyAccess"

async function authenticatedEarlyAccessFetch(
  input: string,
  init?: RequestInit
): Promise<Response> {
  const {
    data: { session },
  } = await supabase.auth.getSession()
  if (!session?.access_token) {
    throw new Error("Your session has expired. Please sign in again.")
  }
  return fetch(input, {
    ...init,
    headers: {
      ...init?.headers,
      Authorization: `Bearer ${session.access_token}`,
    },
  })
}

export async function enrollCurrentUserEarlyAccess(
  source: "standard_email" | "standard_oauth"
): Promise<
  "enrolled" | "already_enrolled" | "disabled" | "ineligible"
> {
  const response = await authenticatedEarlyAccessFetch(
    "/api/early-access/enroll",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ source }),
    }
  )
  const body = (await response.json()) as {
    result?: string
    error?: string
  }
  if (!response.ok) {
    throw new Error(body.error || "Could not enroll in Early Access.")
  }
  if (
    body.result === "enrolled" ||
    body.result === "already_enrolled" ||
    body.result === "disabled"
  ) {
    return body.result
  }
  return "ineligible"
}

export async function fetchCurrentEarlyAccessProgress(): Promise<EarlyAccessProgress | null> {
  const response = await authenticatedEarlyAccessFetch(
    "/api/early-access/status",
    { cache: "no-store" }
  )
  const body = (await response.json()) as {
    progress?: EarlyAccessProgress | null
    error?: string
  }
  if (!response.ok) {
    throw new Error(body.error || "Could not load Early Access progress.")
  }
  return body.progress ?? null
}

export async function claimCurrentUserProForLife(): Promise<{
  result: ProForLifeClaimResult
  awardedAt: string | null
  spotsRemaining: number
}> {
  const response = await authenticatedEarlyAccessFetch(
    "/api/early-access/claim",
    { method: "POST" }
  )
  const body = (await response.json()) as {
    result?: ProForLifeClaimResult
    awardedAt?: string | null
    spotsRemaining?: number
    error?: string
  }
  if (!response.ok || !body.result) {
    throw new Error(body.error || "Could not claim Pro For Life.")
  }
  return {
    result: body.result,
    awardedAt: body.awardedAt ?? null,
    spotsRemaining: Number(body.spotsRemaining ?? 0),
  }
}
