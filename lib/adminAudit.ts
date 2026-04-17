import type { SupabaseClient } from "@supabase/supabase-js"

export type AdminAuditAction = "ban_user" | "unban_user" | string

/**
 * Inserts a row into `admin_audit_log`. RLS requires `admin_user_id = auth.uid()`.
 */
export async function logAdminAction(
  supabase: SupabaseClient,
  input: {
    adminUserId: string
    targetUserId: string
    action: AdminAuditAction
    targetType?: string | null
    targetId?: string | null
    details?: Record<string, unknown> | null
  }
) {
  const { error } = await supabase.from("admin_audit_log").insert({
    admin_user_id: input.adminUserId,
    target_user_id: input.targetUserId,
    action: input.action,
    target_type: input.targetType ?? "user",
    target_id: (input.targetId ?? input.targetUserId) as string,
    details: input.details ?? null,
  })
  return { error }
}
