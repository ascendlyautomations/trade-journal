import type { PostgrestError, SupabaseClient } from "@supabase/supabase-js"

import { formatPostgrestErrorMessage, logPostgrestErrorDev } from "@/lib/postgrestError"

export type AdminAffiliateApplicationCounts = {
  pending: number
  approved: number
  rejected: number
  total: number
}

export type AdminApproveWorkflowResult = {
  ok?: boolean
  code?: string
}

function parseAffiliateApplicationCounts(raw: unknown): AdminAffiliateApplicationCounts | null {
  if (raw == null || typeof raw !== "object") return null
  const o = raw as Record<string, unknown>
  const n = (v: unknown) => (typeof v === "number" ? v : Number(v ?? 0)) || 0
  return {
    pending: n(o.pending),
    approved: n(o.approved),
    rejected: n(o.rejected),
    total: n(o.total),
  }
}

/** Maps Postgres / PostgREST errors from affiliate admin RPCs to short UI copy (no console logging). */
function mapAffiliateAdminRpcError(error: PostgrestError): string {
  const raw = `${error.message ?? ""} ${error.details ?? ""} ${error.hint ?? ""}`.toLowerCase()

  if (error.code === "42501" || raw.includes("not authorized")) {
    return "You don't have permission to perform this action."
  }
  if (raw.includes("stripe promo code id is required") || raw.includes("stripe promo")) {
    return "Stripe promo code ID is required to approve."
  }
  if (
    error.code === "23505" ||
    raw.includes("already taken") ||
    raw.includes("duplicate key") ||
    raw.includes("affiliates_code_lower_idx")
  ) {
    return "This affiliate code is already in use. Try a different override or confirm the applicant's requested code is unique."
  }
  if (raw.includes("application not found")) {
    return "This application could not be found."
  }
  if (raw.includes("not pending")) {
    return "This application is no longer pending."
  }
  if (raw.includes("could not generate unique affiliate code")) {
    return "Could not generate a unique code. Try setting an override."
  }

  return formatPostgrestErrorMessage(error)
}

/** Requires `admin_users` row; RPC is security definer with admin gate. */
export async function fetchAdminAffiliateApplicationCounts(
  supabase: SupabaseClient
): Promise<{ counts: AdminAffiliateApplicationCounts | null; error: Error | null }> {
  const { data, error } = await supabase.rpc("admin_affiliate_application_counts")
  if (error) {
    logPostgrestErrorDev("fetchAdminAffiliateApplicationCounts RPC", error)
    return { counts: null, error: new Error(formatPostgrestErrorMessage(error)) }
  }
  return { counts: parseAffiliateApplicationCounts(data), error: null }
}

/**
 * Atomic approval via RPC: validate code → affiliates (with Stripe promo) → profile → application approved.
 */
export async function adminApproveAffiliateApplication(
  supabase: SupabaseClient,
  input: {
    applicationId: string
    adminCode: string | null
    stripePromo: string | null
  }
): Promise<{ result: AdminApproveWorkflowResult | null; error: Error | null }> {
  const { data, error } = await supabase.rpc("admin_affiliate_approve", {
    p_application_id: input.applicationId,
    p_admin_code: input.adminCode,
    p_stripe_promo: input.stripePromo,
  })

  if (error) {
    return { result: null, error: new Error(mapAffiliateAdminRpcError(error)) }
  }

  const parsed =
    data != null && typeof data === "object"
      ? (data as AdminApproveWorkflowResult)
      : null

  return { result: parsed, error: null }
}

export async function adminRejectAffiliateApplication(
  supabase: SupabaseClient,
  input: { applicationId: string; adminNotes: string | null }
): Promise<{ error: Error | null }> {
  const { error } = await supabase.rpc("admin_affiliate_reject", {
    p_application_id: input.applicationId,
    p_admin_notes: input.adminNotes,
  })

  if (error) {
    return { error: new Error(mapAffiliateAdminRpcError(error)) }
  }
  return { error: null }
}
