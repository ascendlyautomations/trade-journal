import type { SupabaseClient } from "@supabase/supabase-js"

export type AdminAffiliateApplicationCounts = {
  pending: number
  approved: number
  rejected: number
  total: number
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

/** Requires `admin_users` row; RPC is security definer with admin gate. */
export async function fetchAdminAffiliateApplicationCounts(
  supabase: SupabaseClient
): Promise<{ counts: AdminAffiliateApplicationCounts | null; error: Error | null }> {
  const { data, error } = await supabase.rpc("admin_affiliate_application_counts")
  if (error) return { counts: null, error: new Error(error.message) }
  return { counts: parseAffiliateApplicationCounts(data), error: null }
}

export async function adminApproveAffiliateApplication(
  supabase: SupabaseClient,
  input: {
    applicationId: string
    finalCode: string
    stripePromoCodeId?: string | null
    adminNotes?: string | null
  }
): Promise<{ error: Error | null }> {
  const { error } = await supabase.rpc("admin_affiliate_application_approve", {
    p_application_id: input.applicationId,
    p_final_code: input.finalCode.trim(),
    p_stripe_promo_code_id: input.stripePromoCodeId?.trim() || null,
    p_admin_notes: input.adminNotes?.trim() || null,
  })
  return { error: error ? new Error(error.message) : null }
}

export async function adminRejectAffiliateApplication(
  supabase: SupabaseClient,
  input: { applicationId: string; adminNotes?: string | null }
): Promise<{ error: Error | null }> {
  const { error } = await supabase.rpc("admin_affiliate_application_reject", {
    p_application_id: input.applicationId,
    p_admin_notes: input.adminNotes?.trim() || null,
  })
  return { error: error ? new Error(error.message) : null }
}
