import type { SupabaseClient } from "@supabase/supabase-js"
import { logAdminAction } from "./adminAudit"

export async function banUser(
  supabase: SupabaseClient,
  input: { adminUserId: string; targetUserId: string; reason: string }
) {
  const trimmed = input.reason.trim()
  const now = new Date().toISOString()

  const { error: updateError } = await supabase
    .from("profiles")
    .update({
      is_banned: true,
      banned_reason: trimmed || null,
      banned_at: now,
      banned_by: input.adminUserId,
    })
    .eq("id", input.targetUserId)

  if (updateError) return { error: updateError }

  const { error: auditError } = await logAdminAction(supabase, {
    adminUserId: input.adminUserId,
    targetUserId: input.targetUserId,
    action: "ban_user",
    targetType: "user",
    targetId: input.targetUserId,
    details: { reason: trimmed || null },
  })

  return { error: auditError }
}

export async function unbanUser(supabase: SupabaseClient, input: { adminUserId: string; targetUserId: string }) {
  const { error: updateError } = await supabase
    .from("profiles")
    .update({
      is_banned: false,
      banned_reason: null,
      banned_at: null,
      banned_by: null,
    })
    .eq("id", input.targetUserId)

  if (updateError) return { error: updateError }

  const { error: auditError } = await logAdminAction(supabase, {
    adminUserId: input.adminUserId,
    targetUserId: input.targetUserId,
    action: "unban_user",
    targetType: "user",
    targetId: input.targetUserId,
    details: {},
  })

  return { error: auditError }
}
