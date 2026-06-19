import type { SupabaseClient } from "@supabase/supabase-js"
import Stripe from "stripe"

export class AdminUserDeletionError extends Error {
  readonly code: "SELF_DELETE" | "ADMIN_TARGET" | "NOT_FOUND" | "DELETE_FAILED"

  constructor(
    code: AdminUserDeletionError["code"],
    message: string
  ) {
    super(message)
    this.code = code
    this.name = "AdminUserDeletionError"
  }
}

export type DeleteUserAdminInput = {
  adminUserId: string
  targetUserId: string
  stripe?: Stripe | null
}

export type DeleteUserAdminResult = {
  ok: true
  targetUserId: string
  username: string | null
  email: string | null
}

async function deleteOr(
  supabase: SupabaseClient,
  table: string,
  orFilter: string
) {
  const { error } = await supabase.from(table).delete().or(orFilter)
  if (error) {
    console.error(`[deleteUserAdmin] ${table} or:`, error.message)
    throw new Error(`Failed to delete ${table}: ${error.message}`)
  }
}

async function deleteWhere(
  supabase: SupabaseClient,
  table: string,
  column: string,
  value: string
) {
  const { error } = await supabase.from(table).delete().eq(column, value)
  if (error) {
    console.error(`[deleteUserAdmin] ${table}.${column}:`, error.message)
    throw new Error(`Failed to delete ${table}: ${error.message}`)
  }
}

async function tryDeleteWhere(
  supabase: SupabaseClient,
  table: string,
  column: string,
  value: string
) {
  const { error } = await supabase.from(table).delete().eq(column, value)
  if (error) {
    console.error(`[deleteUserAdmin] optional ${table}.${column}:`, error.message)
  }
}

async function tryDeleteWhereIn(
  supabase: SupabaseClient,
  table: string,
  column: string,
  values: string[]
) {
  if (values.length === 0) return
  const { error } = await supabase.from(table).delete().in(column, values)
  if (error) {
    console.error(`[deleteUserAdmin] optional ${table}.${column} in:`, error.message)
  }
}

async function deleteWhereIn(
  supabase: SupabaseClient,
  table: string,
  column: string,
  values: string[]
) {
  if (values.length === 0) return
  const { error } = await supabase.from(table).delete().in(column, values)
  if (error) {
    console.error(`[deleteUserAdmin] ${table}.${column} in:`, error.message)
    throw new Error(`Failed to delete ${table}: ${error.message}`)
  }
}

async function cancelStripeSubscriptions(
  stripe: Stripe | null | undefined,
  stripeCustomerId: string | null | undefined
) {
  if (!stripe || !stripeCustomerId?.trim()) return

  try {
    const subs = await stripe.subscriptions.list({
      customer: stripeCustomerId,
      status: "all",
      limit: 20,
    })

    for (const sub of subs.data) {
      if (sub.status === "canceled" || sub.status === "incomplete_expired") continue
      try {
        await stripe.subscriptions.cancel(sub.id)
      } catch (err) {
        console.error("[deleteUserAdmin] Stripe cancel:", err)
      }
    }
  } catch (err) {
    console.error("[deleteUserAdmin] Stripe list subscriptions:", err)
  }
}

export async function assertAdminCanDeleteTarget(
  supabase: SupabaseClient,
  adminUserId: string,
  targetUserId: string
) {
  if (adminUserId === targetUserId) {
    throw new AdminUserDeletionError(
      "SELF_DELETE",
      "You cannot delete your own account from the admin panel."
    )
  }

  const { data: targetAdmin } = await supabase
    .from("admin_users")
    .select("user_id")
    .eq("user_id", targetUserId)
    .maybeSingle()

  if (targetAdmin?.user_id) {
    throw new AdminUserDeletionError(
      "ADMIN_TARGET",
      "Admin accounts cannot be deleted from this tool."
    )
  }
}

/**
 * Permanently deletes a user and related application data.
 * Server-side only — caller must verify admin access first.
 */
export async function deleteUserAdmin(
  supabase: SupabaseClient,
  input: DeleteUserAdminInput
): Promise<DeleteUserAdminResult> {
  const { adminUserId, targetUserId, stripe } = input

  await assertAdminCanDeleteTarget(supabase, adminUserId, targetUserId)

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("id, username, stripe_customer_id")
    .eq("id", targetUserId)
    .maybeSingle()

  const { data: authData, error: authError } =
    await supabase.auth.admin.getUserById(targetUserId)

  if (profileError) {
    throw new AdminUserDeletionError("DELETE_FAILED", profileError.message)
  }

  const authUser = authData.user
  if (!profile?.id && !authUser?.id) {
    throw new AdminUserDeletionError("NOT_FOUND", "User not found")
  }

  const email = authUser?.email ?? null
  const username = profile?.username ?? null

  await cancelStripeSubscriptions(stripe, profile?.stripe_customer_id)

  const { data: ownedRooms } = await supabase
    .from("rooms")
    .select("id")
    .eq("owner_user_id", targetUserId)
  const ownedRoomIds = (ownedRooms ?? []).map((r) => String(r.id))

  if (ownedRoomIds.length > 0) {
    await deleteWhereIn(supabase, "room_messages", "room_id", ownedRoomIds)
    await deleteWhereIn(supabase, "room_members", "room_id", ownedRoomIds)
    await deleteWhereIn(supabase, "room_bans", "room_id", ownedRoomIds)
    await tryDeleteWhereIn(supabase, "room_presence", "room_id", ownedRoomIds)
    await deleteWhereIn(supabase, "room_sections", "room_id", ownedRoomIds)
    await deleteWhere(supabase, "rooms", "owner_user_id", targetUserId)
  }

  await deleteWhere(supabase, "room_members", "user_id", targetUserId)
  await deleteWhere(supabase, "room_bans", "user_id", targetUserId)

  await deleteOr(
    supabase,
    "followers",
    `follower_id.eq.${targetUserId},following_id.eq.${targetUserId}`
  )
  await deleteOr(
    supabase,
    "follow_requests",
    `requester_id.eq.${targetUserId},target_id.eq.${targetUserId}`
  )

  await deleteOr(
    supabase,
    "notifications",
    `user_id.eq.${targetUserId},sender_id.eq.${targetUserId}`
  )

  await deleteWhere(supabase, "message_likes", "user_id", targetUserId)
  await deleteWhere(supabase, "message_comments", "user_id", targetUserId)
  await deleteWhere(supabase, "message_deletions", "user_id", targetUserId)
  await deleteOr(
    supabase,
    "messages",
    `sender_id.eq.${targetUserId},user_id.eq.${targetUserId}`
  )
  await deleteWhere(supabase, "conversation_participants", "user_id", targetUserId)

  await deleteWhere(supabase, "trade_likes", "user_id", targetUserId)
  await deleteWhere(supabase, "trade_comments", "user_id", targetUserId)
  await deleteWhere(supabase, "comments", "user_id", targetUserId)
  await deleteWhere(supabase, "posts", "user_id", targetUserId)
  await deleteWhere(supabase, "trades", "user_id", targetUserId)

  await deleteWhere(supabase, "profile_posts", "user_id", targetUserId)
  await deleteWhere(supabase, "stories", "user_id", targetUserId)
  await deleteWhere(supabase, "saved_posts", "user_id", targetUserId)
  await deleteWhere(supabase, "saved_trades", "user_id", targetUserId)

  await deleteWhere(supabase, "affiliate_payout_requests", "user_id", targetUserId)
  await deleteWhere(supabase, "affiliate_applications", "user_id", targetUserId)
  await deleteWhere(supabase, "affiliates", "user_id", targetUserId)

  await deleteWhere(supabase, "achievements", "user_id", targetUserId)
  await deleteWhere(supabase, "feedback_submissions", "user_id", targetUserId)
  await deleteWhere(supabase, "support_tickets", "user_id", targetUserId)
  await deleteWhere(supabase, "bug_reports", "user_id", targetUserId)
  await deleteWhere(supabase, "feature_requests", "user_id", targetUserId)
  await deleteWhere(supabase, "presets", "user_id", targetUserId)
  await deleteWhere(supabase, "accounts", "user_id", targetUserId)
  await deleteWhere(supabase, "csv_support_requests", "user_id", targetUserId)
  await tryDeleteWhere(supabase, "account_settings", "id", targetUserId)
  await tryDeleteWhere(supabase, "billing_accounts", "id", targetUserId)

  await deleteOr(
    supabase,
    "referrals_ledger",
    `referrer_user_id.eq.${targetUserId},referred_user_id.eq.${targetUserId}`
  )

  await supabase
    .from("profiles")
    .update({ banned_by: null })
    .eq("banned_by", targetUserId)

  if (profile?.id) {
    const { error: profileDeleteError } = await supabase
      .from("profiles")
      .delete()
      .eq("id", targetUserId)
    if (profileDeleteError) {
      throw new AdminUserDeletionError("DELETE_FAILED", profileDeleteError.message)
    }
  }

  if (authUser?.id) {
    const { error: authDeleteError } = await supabase.auth.admin.deleteUser(
      targetUserId
    )
    if (authDeleteError) {
      throw new AdminUserDeletionError("DELETE_FAILED", authDeleteError.message)
    }
  } else if (authError && authError.message !== "User not found") {
    throw new AdminUserDeletionError("DELETE_FAILED", authError.message)
  }

  const { error: auditError } = await supabase.from("admin_audit_log").insert({
    admin_user_id: adminUserId,
    target_user_id: targetUserId,
    action: "delete_user",
    target_type: "user",
    target_id: targetUserId,
    details: {
      username,
      email,
      deleted_at: new Date().toISOString(),
    },
  })

  if (auditError) {
    console.error("[deleteUserAdmin] audit log:", auditError.message)
  }

  return {
    ok: true,
    targetUserId,
    username,
    email,
  }
}
