import type { PostgrestError, SupabaseClient } from "@supabase/supabase-js"
import Stripe from "stripe"
import { deleteUserStorageFiles } from "@/lib/deleteUserStorage"

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

/** Structured failure from a specific deletion step (surfaced to admin UI). */
export class AdminUserDeletionStepError extends Error {
  readonly code = "DELETE_FAILED" as const
  readonly step: string
  readonly table: string | null

  constructor(step: string, table: string | null, message: string) {
    super(message)
    this.name = "AdminUserDeletionStepError"
    this.step = step
    this.table = table
  }
}

export type DeleteUserAdminInput = {
  adminUserId: string
  targetUserId: string
  stripe?: Stripe | null
  /** Self-service account deletion from settings (skips admin-only guards). */
  selfService?: boolean
}

export type DeleteUserAdminResult = {
  ok: true
  targetUserId: string
  username: string | null
  email: string | null
}

type StepContext = {
  targetUserId: string
  step: string
  table: string
}

function isMissingTableError(error: PostgrestError | null | undefined): boolean {
  if (!error) return false
  if (error.code === "PGRST205") return true
  return /schema cache/i.test(error.message ?? "")
}

function logStep(ctx: StepContext) {
  console.log(
    `[deleteUserAdmin] step="${ctx.step}" table="${ctx.table}" userId=${ctx.targetUserId}`
  )
}

function throwStepError(ctx: StepContext, error: PostgrestError | Error) {
  const message =
    "message" in error ? error.message : "Delete operation failed"
  throw new AdminUserDeletionStepError(ctx.step, ctx.table, message)
}

async function deleteOr(ctx: StepContext, supabase: SupabaseClient, orFilter: string) {
  logStep(ctx)
  const { error } = await supabase.from(ctx.table).delete().or(orFilter)
  if (error) {
    console.error(`[deleteUserAdmin] ${ctx.table} or:`, error.message)
    throwStepError(ctx, error)
  }
}

async function tryDeleteOr(
  ctx: StepContext,
  supabase: SupabaseClient,
  orFilter: string
) {
  logStep(ctx)
  const { error } = await supabase.from(ctx.table).delete().or(orFilter)
  if (!error) return
  if (isMissingTableError(error)) {
    console.warn(
      `[deleteUserAdmin] optional ${ctx.table} skipped (${error.code}): ${error.message}`
    )
    return
  }
  console.error(`[deleteUserAdmin] optional ${ctx.table} or:`, error.message)
}

async function deleteWhere(
  ctx: StepContext,
  supabase: SupabaseClient,
  column: string,
  value: string
) {
  logStep(ctx)
  const { error } = await supabase.from(ctx.table).delete().eq(column, value)
  if (error) {
    console.error(`[deleteUserAdmin] ${ctx.table}.${column}:`, error.message)
    throwStepError(ctx, error)
  }
}

async function tryDeleteWhere(
  ctx: StepContext,
  supabase: SupabaseClient,
  column: string,
  value: string
) {
  logStep(ctx)
  const { error } = await supabase.from(ctx.table).delete().eq(column, value)
  if (!error) return
  if (isMissingTableError(error)) {
    console.warn(
      `[deleteUserAdmin] optional ${ctx.table} skipped (${error.code}): ${error.message}`
    )
    return
  }
  console.error(`[deleteUserAdmin] optional ${ctx.table}.${column}:`, error.message)
}

async function tryDeleteWhereIn(
  ctx: StepContext,
  supabase: SupabaseClient,
  column: string,
  values: string[]
) {
  if (values.length === 0) return
  logStep(ctx)
  const { error } = await supabase.from(ctx.table).delete().in(column, values)
  if (!error) return
  if (isMissingTableError(error)) {
    console.warn(
      `[deleteUserAdmin] optional ${ctx.table} skipped (${error.code}): ${error.message}`
    )
    return
  }
  console.error(`[deleteUserAdmin] optional ${ctx.table}.${column} in:`, error.message)
}

async function deleteWhereIn(
  ctx: StepContext,
  supabase: SupabaseClient,
  column: string,
  values: string[]
) {
  if (values.length === 0) return
  logStep(ctx)
  const { error } = await supabase.from(ctx.table).delete().in(column, values)
  if (error) {
    console.error(`[deleteUserAdmin] ${ctx.table}.${column} in:`, error.message)
    throwStepError(ctx, error)
  }
}

async function cancelStripeSubscriptions(
  targetUserId: string,
  stripe: Stripe | null | undefined,
  stripeCustomerId: string | null | undefined
) {
  logStep({
    targetUserId,
    step: "Stripe subscription cleanup",
    table: "stripe.subscriptions",
  })
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

type UserContentIds = {
  postIds: string[]
  tradeIds: string[]
}

async function fetchUserContentIds(
  supabase: SupabaseClient,
  targetUserId: string
): Promise<UserContentIds> {
  const [{ data: posts, error: postError }, { data: trades, error: tradeError }] =
    await Promise.all([
      supabase.from("posts").select("id").eq("user_id", targetUserId),
      supabase.from("trades").select("id").eq("user_id", targetUserId),
    ])

  if (postError) {
    throw new AdminUserDeletionStepError(
      "Owned content lookup",
      "posts",
      postError.message
    )
  }
  if (tradeError) {
    throw new AdminUserDeletionStepError(
      "Owned content lookup",
      "trades",
      tradeError.message
    )
  }

  return {
    postIds: (posts ?? []).map((p) => String(p.id)),
    tradeIds: (trades ?? []).map((t) => String(t.id)),
  }
}

async function deleteNotificationsForIds(
  supabase: SupabaseClient,
  targetUserId: string,
  stepName: string,
  column: "post_id" | "trade_id",
  ids: string[]
) {
  if (ids.length === 0) return

  logStep({
    targetUserId,
    step: stepName,
    table: "notifications",
  })

  const { error } = await supabase.from("notifications").delete().in(column, ids)

  if (error) {
    console.error(`[deleteUserAdmin] notifications.${column} in:`, error.message)
    throw new AdminUserDeletionStepError(stepName, "notifications", error.message)
  }
}

async function deleteEngagementOnOwnedPosts(
  supabase: SupabaseClient,
  targetUserId: string,
  postIds: string[]
) {
  if (postIds.length === 0) return

  await deleteWhereIn(
    step(targetUserId, "Post likes cleanup", "likes"),
    supabase,
    "post_id",
    postIds
  )
  await tryDeleteWhereIn(
    step(targetUserId, "Saved posts on owned content cleanup", "saved_posts"),
    supabase,
    "post_id",
    postIds
  )
  await deleteWhereIn(
    step(targetUserId, "Comments on owned posts cleanup", "comments"),
    supabase,
    "post_id",
    postIds
  )
  await deleteNotificationsForIds(
    supabase,
    targetUserId,
    "Post-linked notification cleanup",
    "post_id",
    postIds
  )
}

async function deleteEngagementOnOwnedTrades(
  supabase: SupabaseClient,
  targetUserId: string,
  tradeIds: string[]
) {
  if (tradeIds.length === 0) return

  await deleteWhereIn(
    step(targetUserId, "Trade likes on owned trades cleanup", "trade_likes"),
    supabase,
    "trade_id",
    tradeIds
  )
  await deleteWhereIn(
    step(
      targetUserId,
      "Trade comments on owned trades cleanup",
      "trade_comments"
    ),
    supabase,
    "trade_id",
    tradeIds
  )
  await tryDeleteWhereIn(
    step(targetUserId, "Saved trades on owned content cleanup", "saved_trades"),
    supabase,
    "trade_id",
    tradeIds
  )
  await deleteNotificationsForIds(
    supabase,
    targetUserId,
    "Trade-linked notification cleanup",
    "trade_id",
    tradeIds
  )
  await deleteWhereIn(
    step(targetUserId, "Room trade message cleanup", "room_messages"),
    supabase,
    "trade_id",
    tradeIds
  )
  await tryDeleteWhereIn(
    step(targetUserId, "Room pinned trade cleanup", "room_messages"),
    supabase,
    "pinned_trade_id",
    tradeIds
  )
}

async function deleteEngagementOnUserMessages(
  supabase: SupabaseClient,
  targetUserId: string
) {
  const { data: messages, error } = await supabase
    .from("messages")
    .select("id")
    .eq("sender_id", targetUserId)

  if (error) {
    throw new AdminUserDeletionStepError(
      "Message engagement lookup",
      "messages",
      error.message
    )
  }

  const messageIds = (messages ?? []).map((m) => String(m.id))
  if (messageIds.length === 0) return

  await deleteWhereIn(
    step(targetUserId, "Likes on user messages cleanup", "message_likes"),
    supabase,
    "message_id",
    messageIds
  )
  await deleteWhereIn(
    step(targetUserId, "Comments on user messages cleanup", "message_comments"),
    supabase,
    "message_id",
    messageIds
  )
}

async function clearReviewerReferences(
  supabase: SupabaseClient,
  targetUserId: string
) {
  logStep({
    targetUserId,
    step: "Affiliate reviewer reference cleanup",
    table: "affiliate_applications",
  })
  await supabase
    .from("affiliate_applications")
    .update({ reviewed_by: null })
    .eq("reviewed_by", targetUserId)

  logStep({
    targetUserId,
    step: "Payout reviewer reference cleanup",
    table: "affiliate_payout_requests",
  })
  await supabase
    .from("affiliate_payout_requests")
    .update({ reviewed_by: null })
    .eq("reviewed_by", targetUserId)
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

async function assertCanDeleteTarget(
  supabase: SupabaseClient,
  input: DeleteUserAdminInput
) {
  if (input.selfService) {
    if (input.adminUserId !== input.targetUserId) {
      throw new AdminUserDeletionError(
        "DELETE_FAILED",
        "Account deletion must be performed by the signed-in user."
      )
    }

    const { data: targetAdmin } = await supabase
      .from("admin_users")
      .select("user_id")
      .eq("user_id", input.targetUserId)
      .maybeSingle()

    if (targetAdmin?.user_id) {
      throw new AdminUserDeletionError(
        "ADMIN_TARGET",
        "Admin accounts cannot be deleted from settings."
      )
    }
    return
  }

  await assertAdminCanDeleteTarget(
    supabase,
    input.adminUserId,
    input.targetUserId
  )
}

async function anonymizeUserDirectMessages(
  supabase: SupabaseClient,
  targetUserId: string
) {
  logStep({
    targetUserId,
    step: "DM sender anonymization",
    table: "messages",
  })

  const { error } = await supabase
    .from("messages")
    .update({ sender_anonymized: true, sender_id: null, user_id: null })
    .eq("sender_id", targetUserId)
    .not("conversation_id", "is", null)

  if (error) {
    throw new AdminUserDeletionStepError(
      "DM sender anonymization",
      "messages",
      error.message
    )
  }
}

function step(
  targetUserId: string,
  stepName: string,
  table: string
): StepContext {
  return { targetUserId, step: stepName, table }
}

/**
 * Permanently deletes a user and related application data.
 * Server-side only — caller must verify admin access first.
 */
export async function deleteUserAdmin(
  supabase: SupabaseClient,
  input: DeleteUserAdminInput
): Promise<DeleteUserAdminResult> {
  const { adminUserId, targetUserId, stripe, selfService = false } = input

  console.log(
    `[deleteUserAdmin] start adminUserId=${adminUserId} targetUserId=${targetUserId} selfService=${selfService}`
  )

  await assertCanDeleteTarget(supabase, input)

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

  await cancelStripeSubscriptions(
    targetUserId,
    stripe,
    profile?.stripe_customer_id
  )

  logStep({
    targetUserId,
    step: "Storage cleanup",
    table: "storage.objects",
  })
  await deleteUserStorageFiles(supabase, targetUserId)

  const { postIds, tradeIds } = await fetchUserContentIds(supabase, targetUserId)

  const { data: ownedRooms } = await supabase
    .from("rooms")
    .select("id")
    .eq("owner_user_id", targetUserId)
  const ownedRoomIds = (ownedRooms ?? []).map((r) => String(r.id))

  if (ownedRoomIds.length > 0) {
    await deleteWhereIn(
      step(targetUserId, "Owned room cleanup", "room_messages"),
      supabase,
      "room_id",
      ownedRoomIds
    )
    await deleteWhereIn(
      step(targetUserId, "Owned room cleanup", "room_members"),
      supabase,
      "room_id",
      ownedRoomIds
    )
    await deleteWhereIn(
      step(targetUserId, "Owned room cleanup", "room_bans"),
      supabase,
      "room_id",
      ownedRoomIds
    )
    await tryDeleteWhereIn(
      step(targetUserId, "Owned room cleanup", "room_presence"),
      supabase,
      "room_id",
      ownedRoomIds
    )
    await deleteWhereIn(
      step(targetUserId, "Owned room cleanup", "room_sections"),
      supabase,
      "room_id",
      ownedRoomIds
    )
    await deleteWhere(
      step(targetUserId, "Owned room cleanup", "rooms"),
      supabase,
      "owner_user_id",
      targetUserId
    )
  }

  await deleteWhere(
    step(targetUserId, "Room membership cleanup", "room_members"),
    supabase,
    "user_id",
    targetUserId
  )
  await deleteWhere(
    step(targetUserId, "Room ban cleanup", "room_bans"),
    supabase,
    "user_id",
    targetUserId
  )
  await deleteWhere(
    step(targetUserId, "Room bans issued cleanup", "room_bans"),
    supabase,
    "banned_by",
    targetUserId
  )
  await tryDeleteWhere(
    step(targetUserId, "Room presence cleanup", "room_presence"),
    supabase,
    "user_id",
    targetUserId
  )
  await deleteWhere(
    step(targetUserId, "Room message cleanup", "room_messages"),
    supabase,
    "user_id",
    targetUserId
  )

  await deleteOr(
    step(targetUserId, "Social graph cleanup", "followers"),
    supabase,
    `follower_id.eq.${targetUserId},following_id.eq.${targetUserId}`
  )
  await deleteOr(
    step(targetUserId, "Legacy follows cleanup", "follows"),
    supabase,
    `follower_id.eq.${targetUserId},following_id.eq.${targetUserId}`
  )
  await deleteOr(
    step(targetUserId, "Follow request cleanup", "follow_requests"),
    supabase,
    `requester_id.eq.${targetUserId},target_id.eq.${targetUserId}`
  )

  await deleteOr(
    step(targetUserId, "Notification cleanup", "notifications"),
    supabase,
    `user_id.eq.${targetUserId},sender_id.eq.${targetUserId}`
  )

  await deleteEngagementOnOwnedPosts(supabase, targetUserId, postIds)
  await deleteEngagementOnOwnedTrades(supabase, targetUserId, tradeIds)
  await deleteEngagementOnUserMessages(supabase, targetUserId)

  await deleteWhere(
    step(targetUserId, "Post likes cleanup", "likes"),
    supabase,
    "user_id",
    targetUserId
  )

  await deleteWhere(
    step(targetUserId, "Message likes cleanup", "message_likes"),
    supabase,
    "user_id",
    targetUserId
  )
  await deleteWhere(
    step(targetUserId, "Message comments cleanup", "message_comments"),
    supabase,
    "user_id",
    targetUserId
  )
  await deleteWhere(
    step(targetUserId, "Message deletions cleanup", "message_deletions"),
    supabase,
    "user_id",
    targetUserId
  )
  await deleteOr(
    step(targetUserId, "Legacy direct messages cleanup", "direct_messages"),
    supabase,
    `sender_id.eq.${targetUserId},recipient_id.eq.${targetUserId}`
  )
  await anonymizeUserDirectMessages(supabase, targetUserId)
  logStep({
    targetUserId,
    step: "Lobby message cleanup",
    table: "messages",
  })
  const { error: lobbyError } = await supabase
    .from("messages")
    .delete()
    .eq("user_id", targetUserId)
    .is("conversation_id", null)
  if (lobbyError) {
    throw new AdminUserDeletionStepError(
      "Lobby message cleanup",
      "messages",
      lobbyError.message
    )
  }
  await deleteWhere(
    step(targetUserId, "Conversation participant cleanup", "conversation_participants"),
    supabase,
    "user_id",
    targetUserId
  )

  await deleteWhere(
    step(targetUserId, "Trade likes cleanup", "trade_likes"),
    supabase,
    "user_id",
    targetUserId
  )
  await deleteWhere(
    step(targetUserId, "Trade comments cleanup", "trade_comments"),
    supabase,
    "user_id",
    targetUserId
  )
  await deleteWhere(
    step(targetUserId, "Post comments cleanup", "comments"),
    supabase,
    "user_id",
    targetUserId
  )

  await deleteWhere(
    step(targetUserId, "Posts cleanup", "posts"),
    supabase,
    "user_id",
    targetUserId
  )
  await deleteWhere(
    step(targetUserId, "Trades cleanup", "trades"),
    supabase,
    "user_id",
    targetUserId
  )

  await deleteWhere(
    step(targetUserId, "Profile posts cleanup", "profile_posts"),
    supabase,
    "user_id",
    targetUserId
  )
  await deleteWhere(
    step(targetUserId, "Stories cleanup", "stories"),
    supabase,
    "user_id",
    targetUserId
  )
  await deleteWhere(
    step(targetUserId, "Saved posts cleanup", "saved_posts"),
    supabase,
    "user_id",
    targetUserId
  )
  await deleteWhere(
    step(targetUserId, "Saved trades cleanup", "saved_trades"),
    supabase,
    "user_id",
    targetUserId
  )

  await tryDeleteWhere(
    step(targetUserId, "Clip likes cleanup", "reel_likes"),
    supabase,
    "user_id",
    targetUserId
  )
  await tryDeleteWhere(
    step(targetUserId, "Clip comments cleanup", "reel_comments"),
    supabase,
    "user_id",
    targetUserId
  )
  await tryDeleteWhere(
    step(targetUserId, "Clips cleanup", "reels"),
    supabase,
    "user_id",
    targetUserId
  )
  await tryDeleteWhere(
    step(targetUserId, "User reviews cleanup", "user_reviews"),
    supabase,
    "user_id",
    targetUserId
  )
  await tryDeleteWhere(
    step(targetUserId, "Achievement posts cleanup", "achievement_posts"),
    supabase,
    "user_id",
    targetUserId
  )
  await tryDeleteWhere(
    step(targetUserId, "Profile post likes cleanup", "profile_post_likes"),
    supabase,
    "user_id",
    targetUserId
  )
  await tryDeleteWhere(
    step(targetUserId, "Profile post comments cleanup", "profile_post_comments"),
    supabase,
    "user_id",
    targetUserId
  )
  await tryDeleteWhere(
    step(targetUserId, "Comment likes cleanup", "comment_likes"),
    supabase,
    "user_id",
    targetUserId
  )
  await tryDeleteWhere(
    step(targetUserId, "Room message reactions cleanup", "room_message_reactions"),
    supabase,
    "user_id",
    targetUserId
  )
  await tryDeleteWhere(
    step(targetUserId, "Room channel preferences cleanup", "room_member_channel_preferences"),
    supabase,
    "user_id",
    targetUserId
  )
  await tryDeleteWhere(
    step(targetUserId, "Beta testimonials cleanup", "beta_testimonials"),
    supabase,
    "user_id",
    targetUserId
  )
  await tryDeleteWhere(
    step(targetUserId, "Account payout cycles cleanup", "account_payout_cycles"),
    supabase,
    "user_id",
    targetUserId
  )

  await deleteWhere(
    step(targetUserId, "Affiliate payout cleanup", "affiliate_payout_requests"),
    supabase,
    "user_id",
    targetUserId
  )
  await deleteWhere(
    step(targetUserId, "Affiliate application cleanup", "affiliate_applications"),
    supabase,
    "user_id",
    targetUserId
  )
  await deleteWhere(
    step(targetUserId, "Affiliate record cleanup", "affiliates"),
    supabase,
    "user_id",
    targetUserId
  )

  await deleteWhere(
    step(targetUserId, "Achievements cleanup", "achievements"),
    supabase,
    "user_id",
    targetUserId
  )
  await deleteWhere(
    step(targetUserId, "Feedback cleanup", "feedback_submissions"),
    supabase,
    "user_id",
    targetUserId
  )
  await deleteWhere(
    step(targetUserId, "Support ticket cleanup", "support_tickets"),
    supabase,
    "user_id",
    targetUserId
  )
  await deleteWhere(
    step(targetUserId, "Bug report cleanup", "bug_reports"),
    supabase,
    "user_id",
    targetUserId
  )
  await deleteWhere(
    step(targetUserId, "Feature request cleanup", "feature_requests"),
    supabase,
    "user_id",
    targetUserId
  )
  await deleteWhere(
    step(targetUserId, "Presets cleanup", "presets"),
    supabase,
    "user_id",
    targetUserId
  )
  await deleteWhere(
    step(targetUserId, "Accounts cleanup", "accounts"),
    supabase,
    "user_id",
    targetUserId
  )
  await tryDeleteWhere(
    step(targetUserId, "User accounts cleanup", "user_accounts"),
    supabase,
    "user_id",
    targetUserId
  )
  await deleteWhere(
    step(targetUserId, "CSV support cleanup", "csv_support_requests"),
    supabase,
    "user_id",
    targetUserId
  )
  await tryDeleteWhere(
    step(targetUserId, "Account settings cleanup", "account_settings"),
    supabase,
    "id",
    targetUserId
  )
  await tryDeleteWhere(
    step(targetUserId, "Billing account cleanup", "billing_accounts"),
    supabase,
    "id",
    targetUserId
  )

  const referralFilter = `referrer_user_id.eq.${targetUserId},referred_user_id.eq.${targetUserId}`
  await tryDeleteOr(
    step(targetUserId, "Referral cleanup", "referrals"),
    supabase,
    referralFilter
  )
  await tryDeleteOr(
    step(targetUserId, "Referral cleanup", "referrals_ledger"),
    supabase,
    referralFilter
  )

  logStep({
    targetUserId,
    step: "Profile ban reference cleanup",
    table: "profiles",
  })
  await supabase
    .from("profiles")
    .update({ banned_by: null })
    .eq("banned_by", targetUserId)

  logStep({
    targetUserId,
    step: "Account settings ban reference cleanup",
    table: "account_settings",
  })
  await supabase
    .from("account_settings")
    .update({ banned_by: null })
    .eq("banned_by", targetUserId)

  await clearReviewerReferences(supabase, targetUserId)

  if (!selfService) {
    logStep({
      targetUserId,
      step: "Audit log",
      table: "admin_audit_log",
    })
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
      throw new AdminUserDeletionStepError(
        "Audit log",
        "admin_audit_log",
        auditError.message
      )
    }
  }

  if (profile?.id) {
    await deleteWhere(
      step(targetUserId, "Profile delete", "profiles"),
      supabase,
      "id",
      targetUserId
    )
  }

  if (authUser?.id) {
    logStep({
      targetUserId,
      step: "Auth session revoke",
      table: "auth.sessions",
    })
    const { error: signOutError } = await supabase.auth.admin.signOut(
      targetUserId,
      "global"
    )
    if (signOutError) {
      console.warn("[deleteUserAdmin] global signOut:", signOutError.message)
    }

    logStep({
      targetUserId,
      step: "Auth user delete",
      table: "auth.users",
    })
    const { error: authDeleteError } = await supabase.auth.admin.deleteUser(
      targetUserId
    )
    if (authDeleteError) {
      throw new AdminUserDeletionStepError(
        "Auth user delete",
        "auth.users",
        authDeleteError.message
      )
    }
  } else if (authError && authError.message !== "User not found") {
    throw new AdminUserDeletionStepError(
      "Auth user lookup",
      "auth.users",
      authError.message
    )
  }

  console.log(`[deleteUserAdmin] complete targetUserId=${targetUserId}`)

  return {
    ok: true,
    targetUserId,
    username,
    email,
  }
}
